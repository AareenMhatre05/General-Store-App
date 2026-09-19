-- Product catalog. stock_quantity is a cached total kept in sync by the
-- inventory_adjustments trigger (see the inventory_adjustments
-- migration) -- staff never update it directly.

create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories (id) on delete set null,
  name text not null,
  description text,
  unit text not null, -- free-form: "1 kg", "500 g pack", "piece", etc.
  price numeric(10, 2) not null check (price >= 0),
  mrp numeric(10, 2) check (mrp is null or mrp >= price),
  barcode text unique,
  stock_quantity integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column public.products.mrp is 'Printed maximum retail price, shown struck through next to the selling price when higher.';
comment on column public.products.stock_quantity is 'Cached running total; only ever changed by inserting into inventory_adjustments.';

create index products_category_id_idx on public.products (category_id);
create index products_barcode_idx on public.products (barcode);

create trigger products_set_updated_at
  before update on public.products
  for each row execute function public.set_updated_at();

alter table public.products enable row level security;

create policy "Anyone can view active products"
  on public.products for select
  to anon, authenticated
  using (is_active or public.is_staff_or_owner());

create policy "Staff and owner can create products"
  on public.products for insert
  to authenticated
  with check (public.is_staff_or_owner());

create policy "Staff and owner can update products"
  on public.products for update
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

create policy "Staff and owner can delete products"
  on public.products for delete
  to authenticated
  using (public.is_staff_or_owner());
