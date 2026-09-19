-- Expired and damaged stock, and whether the supplier made it good.
--
-- Two outcomes that look identical on the shelf but are opposite on the
-- books: some suppliers credit the shop for expired goods, some do not.
-- The first is a wash; the second is a straight loss of what the shop
-- paid. Recording them the same way would quietly overstate profit.
--
-- Sits alongside inventory_adjustments rather than inside it: the ledger
-- records how many units moved, this records the money, and the reason
-- enum already has 'wastage' for the stock side.

create table public.stock_writeoffs (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete restrict,
  quantity integer not null check (quantity > 0),
  -- Snapshotted, for the same reason order lines snapshot cost: a later
  -- price change must not rewrite what this write-off cost the shop.
  unit_cost numeric(10, 2),
  reason text not null default 'expired',
  refunded boolean not null default false,
  refund_amount numeric(10, 2) not null default 0 check (refund_amount >= 0),
  notes text,
  recorded_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  -- A refund without an amount, or an amount without a refund, is a
  -- half-entered record that would skew the totals either way.
  check (
    (refunded and refund_amount > 0) or (not refunded and refund_amount = 0)
  )
);

comment on table public.stock_writeoffs is
  'Expired/damaged stock. refunded = supplier credited the shop; otherwise the unrecovered cost is a loss.';

create index stock_writeoffs_product_idx on public.stock_writeoffs (product_id);
create index stock_writeoffs_created_idx on public.stock_writeoffs (created_at desc);

alter table public.stock_writeoffs enable row level security;

create policy "Staff and owner manage write-offs"
  on public.stock_writeoffs for all
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

-- Removing the stock is part of writing it off, so it happens here
-- rather than relying on staff to remember a second step. Goes through
-- the ledger like every other stock movement.
create or replace function public.record_writeoff_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.inventory_adjustments
    (product_id, change_quantity, reason, notes)
  values (
    new.product_id,
    -new.quantity,
    'wastage',
    coalesce(new.notes, new.reason)
  );
  return new;
end;
$$;

create trigger stock_writeoffs_adjust_stock
  after insert on public.stock_writeoffs
  for each row execute function public.record_writeoff_stock();

-- Fill in the cost from the product's current cost when not supplied,
-- so the loss figure is right even if staff leave the field blank.
create or replace function public.default_writeoff_cost()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.unit_cost is null then
    select cost_price into new.unit_cost
    from public.product_costs where product_id = new.product_id;
  end if;
  return new;
end;
$$;

create trigger stock_writeoffs_default_cost
  before insert on public.stock_writeoffs
  for each row execute function public.default_writeoff_cost();

-- What the shop actually lost in a period.
create or replace function public.writeoff_totals_between(
  p_from timestamptz,
  p_to timestamptz
)
returns table (
  units integer,
  cost_of_goods numeric,
  refunded_amount numeric,
  net_loss numeric,
  entries bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_staff_or_owner() then
    raise exception 'writeoff_totals_between: staff or owner only';
  end if;

  return query
  select
    coalesce(sum(w.quantity), 0)::integer,
    coalesce(sum(coalesce(w.unit_cost, 0) * w.quantity), 0)::numeric,
    coalesce(sum(w.refund_amount), 0)::numeric,
    -- The loss is what was paid for the goods minus whatever came back.
    greatest(
      coalesce(sum(coalesce(w.unit_cost, 0) * w.quantity), 0)
        - coalesce(sum(w.refund_amount), 0),
      0
    )::numeric,
    count(*)
  from public.stock_writeoffs w
  where w.created_at >= p_from and w.created_at < p_to;
end;
$$;

revoke execute on function public.writeoff_totals_between(timestamptz, timestamptz) from anon;
