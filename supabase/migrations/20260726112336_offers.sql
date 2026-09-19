-- Offers created and managed by staff/owner, visible to customers while
-- active and within their date window.

create type public.discount_type as enum ('percentage', 'flat');
create type public.offer_scope as enum ('all_products', 'category', 'product');

create table public.offers (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  discount_type public.discount_type not null,
  discount_value numeric(10, 2) not null check (discount_value > 0),
  scope public.offer_scope not null,
  category_id uuid references public.categories (id) on delete cascade,
  product_id uuid references public.products (id) on delete cascade,
  banner_image_path text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at),
  check (
    (scope = 'all_products' and category_id is null and product_id is null)
    or (scope = 'category' and category_id is not null and product_id is null)
    or (scope = 'product' and product_id is not null and category_id is null)
  ),
  check (discount_type <> 'percentage' or discount_value <= 100)
);

create index offers_category_id_idx on public.offers (category_id);
create index offers_product_id_idx on public.offers (product_id);

create trigger offers_set_updated_at
  before update on public.offers
  for each row execute function public.set_updated_at();

alter table public.offers enable row level security;

create policy "Anyone can view active current offers"
  on public.offers for select
  to anon, authenticated
  using (
    (is_active and now() >= starts_at and (ends_at is null or now() <= ends_at))
    or public.is_staff_or_owner()
  );

create policy "Staff and owner can create offers"
  on public.offers for insert
  to authenticated
  with check (public.is_staff_or_owner());

create policy "Staff and owner can update offers"
  on public.offers for update
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

create policy "Staff and owner can delete offers"
  on public.offers for delete
  to authenticated
  using (public.is_staff_or_owner());
