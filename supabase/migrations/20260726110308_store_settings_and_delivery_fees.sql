-- Single-store settings (there is exactly one Kavita General Stores
-- location) and the distance-based delivery fee tiers.

create table public.store_settings (
  id smallint primary key default 1 check (id = 1),
  store_name text not null default 'Kavita General Stores',
  location extensions.geography(Point, 4326),
  address text,
  updated_at timestamptz not null default now()
);

comment on table public.store_settings is 'Singleton row holding the store''s location, used to price delivery by distance.';

insert into public.store_settings (id) values (1);

create trigger store_settings_set_updated_at
  before update on public.store_settings
  for each row execute function public.set_updated_at();

create table public.delivery_fee_tiers (
  id uuid primary key default gen_random_uuid(),
  min_distance_meters numeric not null,
  max_distance_meters numeric,
  fee_amount numeric(10, 2) not null,
  created_at timestamptz not null default now(),
  check (max_distance_meters is null or max_distance_meters > min_distance_meters)
);

comment on table public.delivery_fee_tiers is 'Ordered distance bands (in meters from the store) mapped to a delivery fee.';

-- Looks up the delivery fee for a straight-line distance from the store,
-- in meters. Returns null if no tier covers that distance (e.g. too far).
create or replace function public.get_delivery_fee(distance_meters numeric)
returns numeric
language sql
stable
set search_path = public
as $$
  select fee_amount
  from public.delivery_fee_tiers
  where distance_meters >= min_distance_meters
    and (max_distance_meters is null or distance_meters < max_distance_meters)
  order by min_distance_meters
  limit 1;
$$;

-- Convenience wrapper: delivery fee for a customer's location (as
-- lon/lat) based on the store's current location.
create or replace function public.get_delivery_fee_for_point(customer_location extensions.geography)
returns numeric
language sql
stable
set search_path = public
as $$
  select public.get_delivery_fee(
    extensions.st_distance(store_settings.location, customer_location)::numeric
  )
  from public.store_settings
  where id = 1;
$$;

alter table public.store_settings enable row level security;
alter table public.delivery_fee_tiers enable row level security;

-- Store location and fee tiers are not sensitive; the customer app needs
-- to read them (unauthenticated, while browsing) to show delivery pricing.
create policy "Anyone can view store settings"
  on public.store_settings for select
  to anon, authenticated
  using (true);

create policy "Staff and owner can update store settings"
  on public.store_settings for update
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

create policy "Anyone can view delivery fee tiers"
  on public.delivery_fee_tiers for select
  to anon, authenticated
  using (true);

create policy "Staff and owner can manage delivery fee tiers"
  on public.delivery_fee_tiers for all
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());
