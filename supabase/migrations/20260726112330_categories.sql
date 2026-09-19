-- Product categories, for browsing in the customer app and organizing
-- inventory in the staff app.

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger categories_set_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();

alter table public.categories enable row level security;

create policy "Anyone can view active categories"
  on public.categories for select
  to anon, authenticated
  using (is_active or public.is_staff_or_owner());

create policy "Staff and owner can manage categories"
  on public.categories for insert
  to authenticated
  with check (public.is_staff_or_owner());

create policy "Staff and owner can update categories"
  on public.categories for update
  to authenticated
  using (public.is_staff_or_owner())
  with check (public.is_staff_or_owner());

create policy "Staff and owner can delete categories"
  on public.categories for delete
  to authenticated
  using (public.is_staff_or_owner());
