-- PostgREST returns geography columns as raw WKB hex, not usable
-- lat/lng, when read directly through the table API. These views
-- expose plain latitude/longitude for reads, and these RPCs are the
-- write path (a REST insert/update payload can't embed a
-- ST_MakePoint(...) call, so clients build points through here instead
-- of writing to `location` directly).

create view public.addresses_with_coords
  with (security_invoker = true) as
select
  a.*,
  extensions.st_y(a.location::extensions.geometry) as latitude,
  extensions.st_x(a.location::extensions.geometry) as longitude
from public.addresses a;

create view public.store_settings_with_coords
  with (security_invoker = true) as
select
  s.*,
  extensions.st_y(s.location::extensions.geometry) as latitude,
  extensions.st_x(s.location::extensions.geometry) as longitude
from public.store_settings s;

create or replace function public.upsert_address(
  p_id uuid,
  p_label text,
  p_line1 text,
  p_line2 text,
  p_city text,
  p_pincode text,
  p_latitude double precision,
  p_longitude double precision,
  p_is_default boolean
)
returns public.addresses
language plpgsql
set search_path = public
as $$
declare
  v_row public.addresses;
  v_point extensions.geography;
begin
  v_point := extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography;

  if p_id is null then
    insert into public.addresses (customer_id, label, line1, line2, city, pincode, location, is_default)
    values (auth.uid(), p_label, p_line1, p_line2, p_city, p_pincode, v_point, p_is_default)
    returning * into v_row;
  else
    update public.addresses
    set label = p_label,
        line1 = p_line1,
        line2 = p_line2,
        city = p_city,
        pincode = p_pincode,
        location = v_point,
        is_default = p_is_default
    where id = p_id
    returning * into v_row;
  end if;

  return v_row;
end;
$$;

-- Friendlier wrapper around get_delivery_fee_for_point(): RPC calls
-- can't easily pass a raw `geography` value, so accept plain lat/lng.
create or replace function public.get_delivery_fee_for_coords(p_latitude double precision, p_longitude double precision)
returns numeric
language sql
stable
set search_path = public
as $$
  select public.get_delivery_fee_for_point(
    extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography
  );
$$;

create or replace function public.set_store_location(p_latitude double precision, p_longitude double precision)
returns public.store_settings
language plpgsql
set search_path = public
as $$
declare
  v_row public.store_settings;
begin
  if not public.is_staff_or_owner() then
    raise exception 'Only staff or owner can update the store location';
  end if;

  update public.store_settings
  set location = extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography
  where id = 1
  returning * into v_row;

  return v_row;
end;
$$;
