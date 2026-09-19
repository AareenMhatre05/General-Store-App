-- Live delivery tracking: a fourth role, order assignments, and the
-- partner's position while they are out.
--
-- Who may see a delivery partner's location is the whole design problem
-- here. A partner's live position is personal data, so it is readable by
-- exactly three parties: the partner themselves, staff/owner (who run
-- the shop), and the one customer whose order that partner is currently
-- carrying -- and that last one only while the order is genuinely in
-- flight. Once delivered, the customer stops seeing them.

-- 1. The role -------------------------------------------------------

alter type public.user_role add value if not exists 'delivery';

comment on type public.user_role is
  'customer | staff | owner | delivery. Delivery partners see only their assigned orders and the map -- never inventory, pricing or sales.';

-- 2. Assignments ----------------------------------------------------

create table public.delivery_assignments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  delivery_user_id uuid not null references public.profiles (id) on delete restrict,
  assigned_at timestamptz not null default now(),
  picked_up_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  -- One active assignment per order; reassigning replaces it.
  unique (order_id)
);

comment on table public.delivery_assignments is
  'Which delivery partner is carrying which order.';

create index delivery_assignments_user_idx
  on public.delivery_assignments (delivery_user_id);

alter table public.delivery_assignments enable row level security;

create policy "Staff and owner manage assignments"
  on public.delivery_assignments for all
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

create policy "Delivery partner sees own assignments"
  on public.delivery_assignments for select
  to authenticated
  using (delivery_user_id = auth.uid());

-- A partner marks their own pickup/delivery times, nothing else.
create policy "Delivery partner updates own assignment"
  on public.delivery_assignments for update
  to authenticated
  using (delivery_user_id = auth.uid())
  with check (delivery_user_id = auth.uid());

create policy "Customer sees who is bringing their order"
  on public.delivery_assignments for select
  to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = delivery_assignments.order_id
        and o.customer_id = auth.uid()
    )
  );

-- 3. Live position --------------------------------------------------

create table public.delivery_locations (
  delivery_user_id uuid primary key references public.profiles (id) on delete cascade,
  location extensions.geography(Point, 4326) not null,
  accuracy_meters numeric,
  updated_at timestamptz not null default now()
);

comment on table public.delivery_locations is
  'Latest known position of each delivery partner. One row per partner, overwritten -- this is a live position, not a history trail.';

alter table public.delivery_locations enable row level security;

create policy "Delivery partner writes own location"
  on public.delivery_locations for all
  to authenticated
  using (delivery_user_id = auth.uid())
  with check (delivery_user_id = auth.uid());

create policy "Staff and owner see all partners"
  on public.delivery_locations for select
  to authenticated
  using (public.is_staff_or_owner());

-- The narrow one: a customer sees a partner's position only while that
-- partner is carrying an order of theirs that is still in flight.
create policy "Customer sees the partner carrying their live order"
  on public.delivery_locations for select
  to authenticated
  using (
    exists (
      select 1
      from public.delivery_assignments da
      join public.orders o on o.id = da.order_id
      where da.delivery_user_id = delivery_locations.delivery_user_id
        and o.customer_id = auth.uid()
        and da.delivered_at is null
        and o.status in ('confirmed', 'preparing', 'out_for_delivery')
    )
  );

-- Plain lat/lng for clients (PostgREST cannot serialize geography).
create view public.delivery_locations_with_coords
with (security_invoker = true)
as
select
  l.delivery_user_id,
  extensions.st_y(l.location::extensions.geometry) as latitude,
  extensions.st_x(l.location::extensions.geometry) as longitude,
  l.accuracy_meters,
  l.updated_at
from public.delivery_locations l;

-- Write path, mirroring upsert_address: RPC because a REST payload
-- cannot build a PostGIS point.
create or replace function public.update_my_delivery_location(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters numeric default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'update_my_delivery_location: not signed in';
  end if;

  insert into public.delivery_locations
    (delivery_user_id, location, accuracy_meters, updated_at)
  values (
    auth.uid(),
    extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography,
    p_accuracy_meters,
    now()
  )
  on conflict (delivery_user_id) do update
    set location = excluded.location,
        accuracy_meters = excluded.accuracy_meters,
        updated_at = now();
end;
$$;

-- Both apps subscribe to position changes rather than polling.
alter publication supabase_realtime add table public.delivery_locations;
alter publication supabase_realtime add table public.delivery_assignments;
