-- upsert_address() returned `public.addresses` -- the raw table row.
-- That row carries the PostGIS `location` column and no latitude or
-- longitude, so every client call blew up in Address.fromJson, which
-- reads json['latitude'] and got null. Saving an address could never
-- have worked; the failure was just masked by a "could not save, try
-- again" catch-all.
--
-- It now returns the same shape the read path uses
-- (addresses_with_coords), so one parser handles both.
--
-- The return type changes, which create-or-replace cannot do, hence the
-- explicit drop. The signature is otherwise identical, so no client
-- change is needed beyond this.

drop function if exists public.upsert_address(
  uuid, text, text, text, text, text, double precision, double precision, boolean
);

create function public.upsert_address(
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
returns public.addresses_with_coords
language plpgsql
set search_path = public
as $$
declare
  v_id uuid;
  v_point extensions.geography;
  v_result public.addresses_with_coords;
begin
  v_point := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude), 4326
  )::extensions.geography;

  if p_id is null then
    insert into public.addresses (customer_id, label, line1, line2, city, pincode, location, is_default)
    values (auth.uid(), p_label, p_line1, p_line2, p_city, p_pincode, v_point, p_is_default)
    returning id into v_id;
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
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'upsert_address: no address was written (id % not yours?)', p_id;
  end if;

  -- Only one address per customer can be the default.
  if p_is_default then
    update public.addresses
    set is_default = false
    where customer_id = auth.uid() and id <> v_id and is_default;
  end if;

  select * into v_result from public.addresses_with_coords where id = v_id;
  return v_result;
end;
$$;
