-- Two problems closed together, because they're the same problem.
--
-- 1. Offers did nothing. Staff could create one and customers could see
--    the banner, but no code path ever reduced a price by it. Discounts
--    were decorative.
--
-- 2. order_items.unit_price was whatever the client sent. A modified
--    client could have bought anything for ₹0.01. That contradicts the
--    rule that money is computed server-side (Decisions.md D10) -- the
--    order totals were derived correctly, but from a number the client
--    chose.
--
-- Fixing (1) properly means the server has to know the real price of a
-- product at any moment, which is exactly what (2) needs too.

-- The single best offer applying to a product right now, or null.
-- Precedence is specificity first: a product-specific offer beats a
-- category one, which beats a store-wide one. Ties inside the same
-- scope go to whichever helps the customer most.
create or replace function public.best_offer_for_product(p_product_id uuid)
returns public.offers
language sql
stable
set search_path = public
as $$
  select o.*
  from public.offers o
  join public.products p on p.id = p_product_id
  where o.is_active
    and now() >= o.starts_at
    and (o.ends_at is null or now() <= o.ends_at)
    and (
      (o.scope = 'product' and o.product_id = p.id)
      or (o.scope = 'category' and o.category_id = p.category_id)
      or (o.scope = 'all_products')
    )
  order by
    case o.scope
      when 'product' then 0
      when 'category' then 1
      else 2
    end,
    case o.discount_type
      when 'percentage' then p.price * o.discount_value / 100
      else o.discount_value
    end desc
  limit 1;
$$;

-- What a customer actually pays for one unit right now. Never negative,
-- always rounded to paise.
create or replace function public.effective_unit_price(p_product_id uuid)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  v_price numeric;
  v_offer public.offers;
begin
  select price into v_price from public.products where id = p_product_id;
  if v_price is null then
    raise exception 'effective_unit_price: unknown product %', p_product_id;
  end if;

  v_offer := public.best_offer_for_product(p_product_id);
  if v_offer.id is null then
    return v_price;
  end if;

  if v_offer.discount_type = 'percentage' then
    v_price := v_price - (v_price * v_offer.discount_value / 100);
  else
    v_price := v_price - v_offer.discount_value;
  end if;

  return round(greatest(v_price, 0), 2);
end;
$$;

-- Prices are now set by the server on the way in.
--
-- Staff keep the ability to override: an in-store sale sometimes goes
-- out at a negotiated price, and the person entering it is trusted.
-- Customers never can -- whatever their client sends is discarded.
create or replace function public.set_order_item_price()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_is_staff boolean := public.is_staff_or_owner();
begin
  if not v_is_staff or new.unit_price is null or new.unit_price <= 0 then
    new.unit_price := public.effective_unit_price(new.product_id);
  end if;
  return new;
end;
$$;

create trigger order_items_set_price
  before insert on public.order_items
  for each row execute function public.set_order_item_price();

-- Read model for the catalog: list price, what it actually costs today,
-- and which offer is responsible -- so the apps can show "₹40" struck
-- through next to "₹32" and name the offer, without each client
-- re-implementing the discount rules.
--
-- security_invoker so the caller's RLS on products still applies.
create or replace view public.products_with_pricing
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

comment on view public.products_with_pricing is
  'Products plus the price a customer pays today after the best applicable offer.';
