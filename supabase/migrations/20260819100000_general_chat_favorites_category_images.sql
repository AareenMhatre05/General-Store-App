-- Three customer-facing additions.
--
-- 1. Chat with the shop directly, not only about a product.
-- 2. Per-customer favourites.
-- 3. Category images.

-- ---------------------------------------------------------------
-- 1. General chat
--
-- product_inquiries required a product_id, so the only way to talk to
-- the shop was to open an item first and use "Chat for Personalized
-- Order". A customer wanting to ask "do you have fresh coriander today"
-- had nowhere to start. A null product_id now means a general
-- conversation with the shop.
--
-- Still one thread per customer, never a shared room: the RLS below is
-- unchanged in shape, so a customer sees only rows where
-- customer_id = auth.uid().

alter table public.product_inquiries
  alter column product_id drop not null;

comment on column public.product_inquiries.product_id is
  'The product being asked about, or null for a general conversation with the shop.';

-- The chat inbox groups by (customer, product), and null product_id
-- must group as one thread rather than scatter -- this index supports
-- both the general and per-product lookups.
create index if not exists product_inquiries_general_idx
  on public.product_inquiries (customer_id, created_at desc)
  where product_id is null;

-- ---------------------------------------------------------------
-- 2. Favourites
--
-- A saved list per customer, surfaced as their own category. Deliberately
-- its own table rather than a flag on products: the same product is
-- favourited by different people independently.

create table public.favorites (
  customer_id uuid not null references public.profiles (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (customer_id, product_id)
);

comment on table public.favorites is
  'Per-customer saved products. Private to each customer.';

create index favorites_customer_idx on public.favorites (customer_id, created_at desc);

alter table public.favorites enable row level security;

-- Strictly private: not even staff need to see who favourited what, and
-- not collecting it is simpler than protecting it.
create policy "Customers manage their own favourites"
  on public.favorites for all
  to authenticated
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid());

-- ---------------------------------------------------------------
-- 3. Category images
--
-- categories.image_path already existed but nothing ever wrote it.
-- Images live in the existing public product-images bucket rather than a
-- new one: same access rules (anyone reads, staff write), one bucket to
-- configure, and a category picture is no more sensitive than a product
-- picture.

comment on column public.categories.image_path is
  'Storage path within the product-images bucket, or null for the default icon.';
