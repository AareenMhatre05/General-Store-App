-- Backs the "Chat for Personalized Order" feature on the product detail
-- screen: a customer can ask staff a question about a specific product
-- before ordering. Scoped narrowly to product Q&A -- a separate
-- post-order delivery chat (if wanted later) is a distinct concern.

create table public.product_inquiries (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  product_id uuid not null references public.products (id) on delete cascade,
  sender_role public.user_role not null,
  message text not null,
  created_at timestamptz not null default now()
);

comment on table public.product_inquiries is 'Pre-purchase Q&A between a customer and staff about a specific product.';

create index product_inquiries_customer_product_idx
  on public.product_inquiries (customer_id, product_id, created_at);

alter table public.product_inquiries enable row level security;

create policy "Customers can view their own inquiries"
  on public.product_inquiries for select
  to authenticated
  using (customer_id = auth.uid());

create policy "Customers can send their own inquiry messages"
  on public.product_inquiries for insert
  to authenticated
  with check (customer_id = auth.uid() and sender_role = 'customer');

create policy "Staff and owner can view all inquiries"
  on public.product_inquiries for select
  to authenticated
  using (public.is_staff_or_owner());

create policy "Staff and owner can reply to inquiries"
  on public.product_inquiries for insert
  to authenticated
  with check (public.is_staff_or_owner() and sender_role in ('staff', 'owner'));

alter publication supabase_realtime add table public.product_inquiries;
