-- Profiles + role model (customer / staff / owner).
--
-- Staff and owner accounts are not self-service: every new auth.users row
-- gets a 'customer' profile by default via the trigger below. Promoting
-- someone to 'staff' or 'owner' is a manual DB action (or a future
-- service-role Edge Function), never something a client can do to itself.

create type public.user_role as enum ('customer', 'staff', 'owner');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.user_role not null default 'customer',
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'One row per auth user; holds the customer/staff/owner role used by RLS policies.';

-- Helper functions used throughout RLS policies. security definer + a
-- fixed search_path so they can read public.profiles regardless of the
-- calling role's own RLS visibility into that table.
create or replace function public.current_role_name()
returns public.user_role
language sql
security definer
stable
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_staff_or_owner()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (select role in ('staff', 'owner') from public.profiles where id = auth.uid()),
    false
  );
$$;

create or replace function public.is_owner()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (select role = 'owner' from public.profiles where id = auth.uid()),
    false
  );
$$;

-- Auto-create a 'customer' profile whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Block role escalation through direct table updates: only an owner may
-- change someone's role. Everything else about a profile stays editable
-- by its own user.
create or replace function public.prevent_role_self_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role and not public.is_owner() then
    raise exception 'Only an owner can change a profile role';
  end if;
  return new;
end;
$$;

create trigger profiles_prevent_role_self_escalation
  before update on public.profiles
  for each row execute function public.prevent_role_self_escalation();

alter table public.profiles enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

create policy "Staff and owner can view all profiles"
  on public.profiles for select
  to authenticated
  using (public.is_staff_or_owner());

create policy "Users can update their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());
