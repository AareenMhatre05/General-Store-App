-- Line items for an order. unit_price is snapshotted at the time of
-- purchase so historical orders don't change if the product's price
-- changes later.

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete restrict,
  quantity integer not null check (quantity > 0),
  unit_price numeric(10, 2) not null check (unit_price >= 0),
  subtotal numeric(10, 2) generated always as (quantity * unit_price) stored,
  created_at timestamptz not null default now()
);

create index order_items_order_id_idx on public.order_items (order_id);
create index order_items_product_id_idx on public.order_items (product_id);

-- Every order_item represents a sale: deduct it from stock immediately.
create or replace function public.record_sale_inventory_adjustment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.inventory_adjustments (product_id, change_quantity, reason, reference_order_id)
  values (new.product_id, -new.quantity, 'sale', new.order_id);
  return new;
end;
$$;

create trigger order_items_record_sale
  after insert on public.order_items
  for each row execute function public.record_sale_inventory_adjustment();

alter table public.order_items enable row level security;

create policy "Customers can view their own order items"
  on public.order_items for select
  to authenticated
  using (
    exists (
      select 1 from public.orders
      where orders.id = order_items.order_id
        and orders.customer_id = auth.uid()
    )
  );

create policy "Customers can add items to their own orders"
  on public.order_items for insert
  to authenticated
  with check (
    exists (
      select 1 from public.orders
      where orders.id = order_items.order_id
        and orders.customer_id = auth.uid()
    )
  );

create policy "Staff and owner can view all order items"
  on public.order_items for select
  to authenticated
  using (public.is_staff_or_owner());

create policy "Staff and owner can manage all order items"
  on public.order_items for all
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());
