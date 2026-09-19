-- Product photos. Files live in the public "product-images" storage
-- bucket; this table just tracks which paths belong to which product
-- and their display order.

create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  storage_path text not null,
  is_primary boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index product_images_product_id_idx on public.product_images (product_id);

alter table public.product_images enable row level security;

create policy "Anyone can view product image records"
  on public.product_images for select
  to anon, authenticated
  using (true);

create policy "Staff and owner can manage product images"
  on public.product_images for all
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

-- Storage bucket + policies for the actual image files.
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

create policy "Anyone can view product image files"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'product-images');

create policy "Staff and owner can upload product image files"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'product-images' and public.is_staff_or_owner());

create policy "Staff and owner can update product image files"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'product-images' and public.is_staff_or_owner())
  with check (bucket_id = 'product-images' and public.is_staff_or_owner());

create policy "Staff and owner can delete product image files"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'product-images' and public.is_staff_or_owner());
