-- Freeze supplier cost at the moment of sale.
--
-- Profit was computed by joining product_costs live, so re-pricing a
-- product retroactively re-valued every past sale: an item bought at ₹8
-- and sold at ₹10 showed ₹2 profit, and still should -- but once the
-- cost changed, last month's sales silently reported today's margin.
-- That is not imprecision, it is wrong history.
--
-- The selling side was already correct: order_items.unit_price is
-- stamped by set_order_item_price() on insert. This does the same for
-- cost.
--
-- Cost cannot simply become a column on order_items, because a customer
-- can read their own order lines and would then read supplier costs.
-- So the snapshot lives in a side table locked to staff -- the same
-- reasoning as product_costs itself (Decisions.md D50).

create table public.order_item_costs (
  order_item_id uuid primary key
    references public.order_items (id) on delete cascade,
  cost_price numeric(10, 2) not null check (cost_price >= 0),
  captured_at timestamptz not null default now()
);

comment on table public.order_item_costs is
  'Supplier cost as it stood when the line was sold. Staff/owner only. Never updated by later cost changes -- that is the entire point.';

alter table public.order_item_costs enable row level security;

create policy "Staff and owner can view order item costs"
  on public.order_item_costs for select
  to authenticated
  using (public.is_staff_or_owner());

create policy "Staff and owner can manage order item costs"
  on public.order_item_costs for all
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

-- Capture on insert, and re-capture only if the line is moved to a
-- different product. A quantity change keeps the original unit cost --
-- correcting "2 tins" to "3 tins" does not re-price the first two.
create or replace function public.snapshot_order_item_cost()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cost numeric;
begin
  if tg_op = 'UPDATE' and new.product_id = old.product_id then
    return new;
  end if;

  select cost_price into v_cost
  from public.product_costs
  where product_id = new.product_id;

  -- No cost recorded: leave the snapshot absent rather than guessing a
  -- zero, so the Sales screen can say "this figure is incomplete"
  -- instead of quietly reporting the full sale price as profit.
  if v_cost is null then
    delete from public.order_item_costs where order_item_id = new.id;
    return new;
  end if;

  insert into public.order_item_costs (order_item_id, cost_price)
  values (new.id, v_cost)
  on conflict (order_item_id)
    do update set cost_price = excluded.cost_price, captured_at = now();

  return new;
end;
$$;

create trigger order_items_snapshot_cost
  after insert or update on public.order_items
  for each row execute function public.snapshot_order_item_cost();

-- Backfill what history we can. Existing lines predate the snapshot, so
-- the current cost is the only figure available for them -- recorded
-- once, now, and frozen from here on.
insert into public.order_item_costs (order_item_id, cost_price)
select oi.id, c.cost_price
from public.order_items oi
join public.product_costs c on c.product_id = oi.product_id
on conflict (order_item_id) do nothing;

-- Profit now reads the snapshot, never the live cost.
create or replace view public.order_item_profit
with (security_invoker = true)
as
select
  oi.id,
  oi.order_id,
  oi.product_id,
  oi.quantity,
  oi.unit_price,
  oi.subtotal,
  ic.cost_price,
  case
    when ic.cost_price is null then null
    else round(oi.subtotal - (ic.cost_price * oi.quantity), 2)
  end as profit
from public.order_items oi
left join public.order_item_costs ic on ic.order_item_id = oi.id;

create or replace function public.sales_profit_between(
  p_from timestamptz,
  p_to timestamptz
)
returns table (
  revenue numeric,
  cost numeric,
  profit numeric,
  costed_items bigint,
  uncosted_items bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_staff_or_owner() then
    raise exception 'sales_profit_between: staff or owner only';
  end if;

  return query
  select
    coalesce(sum(oi.subtotal), 0)::numeric as revenue,
    coalesce(sum(ic.cost_price * oi.quantity), 0)::numeric as cost,
    coalesce(sum(oi.subtotal - coalesce(ic.cost_price, 0) * oi.quantity), 0)::numeric
      as profit,
    count(*) filter (where ic.cost_price is not null) as costed_items,
    count(*) filter (where ic.cost_price is null) as uncosted_items
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  left join public.order_item_costs ic on ic.order_item_id = oi.id
  where o.created_at >= p_from
    and o.created_at < p_to
    and o.status <> 'cancelled';
end;
$$;

revoke execute on function public.sales_profit_between(timestamptz, timestamptz) from anon;
