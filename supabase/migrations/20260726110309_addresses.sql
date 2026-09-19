-- Customer delivery addresses. A customer only ever sees their own;
-- staff/owner can see all of them (needed to fulfill deliveries).

create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  label text,
  line1 text not null,
  line2 text,
  city text not null,
  pincode text not null,
  location extensions.geography(Point, 4326) not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.addresses is 'Saved delivery addresses; location is captured from the customer''s foreground location or manual pin.';

create index addresses_customer_id_idx on public.addresses (customer_id);

create trigger addresses_set_updated_at
  before update on public.addresses
  for each row execute function public.set_updated_at();

alter table public.addresses enable row level security;

create policy "Customers can view their own addresses"
  on public.addresses for select
  to authenticated
  using (customer_id = auth.uid());

create policy "Customers can insert their own addresses"
  on public.addresses for insert
  to authenticated
  with check (customer_id = auth.uid());

create policy "Customers can update their own addresses"
  on public.addresses for update
  to authenticated
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid());

create policy "Customers can delete their own addresses"
  on public.addresses for delete
  to authenticated
  using (customer_id = auth.uid());

create policy "Staff and owner can view all addresses"
  on public.addresses for select
  to authenticated
  using (public.is_staff_or_owner());
