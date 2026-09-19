-- Serviceability, and orders from outside the delivery area.
--
-- Two related things. The shop has a radius it will deliver to; beyond
-- it, a customer can still ASK, and the shop decides case by case --
-- which is how a neighbourhood store actually behaves. Refusing outright
-- would lose business the owner might want.

alter table public.store_settings
  add column if not exists max_delivery_meters numeric;

comment on column public.store_settings.max_delivery_meters is
  'Furthest the shop delivers as a matter of course. Null means no limit. Beyond it, customers may still request a personalised order.';

-- Entry states for an order that is not yet accepted.
alter type public.order_status add value if not exists 'requested';
alter type public.order_status add value if not exists 'declined';

comment on type public.order_status is
  'requested/declined cover out-of-area orders the shop must approve; the rest is the normal lifecycle.';

-- Is this point inside the delivery area? Null max = always yes.
create or replace function public.is_deliverable_to(
  p_latitude double precision,
  p_longitude double precision
)
returns table (deliverable boolean, distance_meters numeric, max_meters numeric)
language plpgsql
stable
set search_path = public
as $$
declare
  v_distance numeric;
  v_max numeric;
begin
  select
    extensions.st_distance(
      s.location,
      extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography
    )::numeric,
    s.max_delivery_meters
  into v_distance, v_max
  from public.store_settings s
  where s.id = 1;

  -- No store location set yet: do not claim undeliverable, because the
  -- distance is unknown rather than large.
  return query select
    (v_distance is null or v_max is null or v_distance <= v_max),
    v_distance,
    v_max;
end;
$$;
