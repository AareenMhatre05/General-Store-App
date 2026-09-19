-- "Special item": something the shop wants to shout about -- a fresh
-- arrival, a seasonal batch, a one-off deal. Staff tick it in the
-- inventory form; the customer app announces it.
--
-- Two columns, not one. `is_special` is the state; `special_since`
-- records when it most recently *became* special, which is what the
-- customer app orders by so it can announce the newest first and ignore
-- ones it has already shown.

alter table public.products
  add column is_special boolean not null default false,
  add column special_since timestamptz;

comment on column public.products.is_special is
  'Flagged by staff as a special item; surfaced prominently in the customer app.';
comment on column public.products.special_since is
  'When is_special last flipped on. Null when never flagged.';

create index products_special_idx
  on public.products (is_special, special_since desc)
  where is_special;

-- Stamp special_since automatically so it cannot drift from is_special.
create or replace function public.stamp_special_since()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_special and (tg_op = 'INSERT' or not old.is_special) then
    new.special_since := now();
  elsif not new.is_special then
    new.special_since := null;
  end if;
  return new;
end;
$$;

create trigger products_stamp_special_since
  before insert or update on public.products
  for each row execute function public.stamp_special_since();

-- The customer-facing read model gains the new columns automatically
-- only if we rebuild it: `select p.*` was expanded at creation time.
drop view if exists public.products_with_pricing;
create view public.products_with_pricing
with (security_invoker = true)
as
select
  p.*,
  public.effective_unit_price(p.id) as effective_price,
  o.id as offer_id,
  o.title as offer_title,
  o.discount_type as offer_discount_type,
  o.discount_value as offer_discount_value
from public.products p
left join lateral public.best_offer_for_product(p.id) o on true;

drop view if exists public.products_with_costs;
create view public.products_with_costs
with (security_invoker = true)
as
select
  p.*,
  public.effective_unit_price(p.id) as effective_price,
  c.cost_price,
  case
    when c.cost_price is null then null
    else round(p.price - c.cost_price, 2)
  end as margin_per_unit
from public.products p
left join public.product_costs c on c.product_id = p.id;
