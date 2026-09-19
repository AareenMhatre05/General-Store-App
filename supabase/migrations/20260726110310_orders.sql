-- Orders: covers both customer-app deliveries and staff-app in-store
-- sales, tagged by channel so sales records can be split by channel.
--
-- Status/payment transitions (payment confirmation, cancellation, etc.)
-- are expected to go through Edge Functions using the service role, not
-- direct client updates -- so there is deliberately no update/delete RLS
-- policy for customers here.

create type public.order_channel as enum ('delivery', 'in_store');

create type public.order_status as enum (
  'pending_payment',
  'scheduled',
  'confirmed',
  'preparing',
  'out_for_delivery',
  'delivered',
  'cancelled'
);

create type public.payment_status as enum ('pending', 'paid', 'failed', 'refunded');

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.profiles (id) on delete set null,
  channel public.order_channel not null,
  status public.order_status not null default 'pending_payment',
  delivery_address_id uuid references public.addresses (id) on delete restrict,
  distance_meters numeric,
  subtotal_amount numeric(10, 2) not null default 0,
  delivery_fee_amount numeric(10, 2) not null default 0,
  total_amount numeric(10, 2) not null default 0,
  scheduled_for timestamptz,
  payment_status public.payment_status not null default 'pending',
  razorpay_order_id text,
  razorpay_payment_id text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (channel = 'delivery' and customer_id is not null and delivery_address_id is not null)
    or (channel = 'in_store' and delivery_address_id is null)
  )
);

comment on table public.orders is 'One row per order/sale; channel distinguishes home delivery from in-store sales.';

create index orders_customer_id_idx on public.orders (customer_id);
create index orders_status_idx on public.orders (status);
create index orders_channel_idx on public.orders (channel);

create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function public.set_updated_at();

alter table public.orders enable row level security;

create policy "Customers can view their own orders"
  on public.orders for select
  to authenticated
  using (customer_id = auth.uid());

create policy "Customers can place their own delivery orders"
  on public.orders for insert
  to authenticated
  with check (customer_id = auth.uid() and channel = 'delivery');

create policy "Staff and owner can view all orders"
  on public.orders for select
  to authenticated
  using (public.is_staff_or_owner());

create policy "Staff and owner can create orders"
  on public.orders for insert
  to authenticated
  with check (public.is_staff_or_owner());

create policy "Staff and owner can update orders"
  on public.orders for update
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());
