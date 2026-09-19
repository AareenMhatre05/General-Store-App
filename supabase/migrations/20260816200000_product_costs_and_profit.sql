-- What the shop pays its supplier, and therefore what it earns.
--
-- Cost lives in its own table rather than a column on `products`
-- because `products` is world-readable -- customers must read it to
-- shop. RLS is row-level, not column-level, so a cost column there
-- would publish supplier margins to anyone with the app. A separate
-- table can be locked to staff outright.

create table public.product_costs (
  product_id uuid primary key references public.products (id) on delete cascade,
  cost_price numeric(10, 2) not null check (cost_price >= 0),
  updated_at timestamptz not null default now()
);

comment on table public.product_costs is
  'Supplier cost per product. Staff/owner only -- never exposed to customers.';

create trigger product_costs_set_updated_at
  before update on public.product_costs
  for each row execute function public.set_updated_at();

alter table public.product_costs enable row level security;

create policy "Staff and owner can view product costs"
  on public.product_costs for select
  to authenticated
  using (public.is_staff_or_owner());

create policy "Staff and owner can manage product costs"
  on public.product_costs for all
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

-- Catalog plus margin, for the staff app's inventory and product form.
-- security_invoker keeps the caller's RLS: a customer reading this sees
-- products but null costs, because the join finds no rows they may read.
create or replace view public.products_with_costs
with (security_invoker = true)
as
select
  p.*,
  c.cost_price,
  case
    when c.cost_price is null then null
    else round(p.price - c.cost_price, 2)
  end as margin_per_unit
from public.products p
left join public.product_costs c on c.product_id = p.id;

comment on view public.products_with_costs is
  'Products with supplier cost and per-unit margin. Costs read as null for non-staff.';

-- Profit per order line: what it sold for, minus what it cost us.
--
-- Cost is joined live rather than snapshotted onto order_items, because
-- order_items is readable by the customer who placed the order -- a cost
-- column there would leak. The trade-off is that changing a product's
-- cost re-values past sales; acceptable for a single shop, and the
-- alternative leaks margins.
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
  c.cost_price,
  case
    when c.cost_price is null then null
    else round(oi.subtotal - (c.cost_price * oi.quantity), 2)
  end as profit
from public.order_items oi
left join public.product_costs c on c.product_id = oi.product_id;

-- Totals for a date range, for the Sales screen. Staff-only by its own
-- check: a customer calling it gets an exception rather than silence,
-- so a mistake is loud.
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
    coalesce(sum(c.cost_price * oi.quantity), 0)::numeric as cost,
    coalesce(sum(oi.subtotal - coalesce(c.cost_price, 0) * oi.quantity), 0)::numeric
      as profit,
    count(*) filter (where c.cost_price is not null) as costed_items,
    count(*) filter (where c.cost_price is null) as uncosted_items
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  left join public.product_costs c on c.product_id = oi.product_id
  where o.created_at >= p_from
    and o.created_at < p_to
    and o.status <> 'cancelled';
end;
$$;

revoke execute on function public.sales_profit_between(timestamptz, timestamptz) from anon;
