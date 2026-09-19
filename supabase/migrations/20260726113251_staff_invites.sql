-- Staff/owner accounts are provisioned by the store owner, not
-- self-service. The owner creates an invite for a specific email +
-- role; the staff app's signup screen collects email/password/code and
-- passes the code through as auth signup metadata. handle_new_user()
-- below checks it and promotes the new profile automatically -- or
-- rejects the signup outright if the code doesn't match.

create table public.staff_invites (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  role public.user_role not null default 'staff' check (role in ('staff', 'owner')),
  invite_code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_at timestamptz,
  used_by uuid references public.profiles (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

comment on table public.staff_invites is 'Pre-registered email + one-time code, created by the owner, that lets one signup land as staff/owner instead of customer.';

create index staff_invites_email_idx on public.staff_invites (lower(email));

alter table public.staff_invites enable row level security;

create policy "Owner can manage staff invites"
  on public.staff_invites for all
  to authenticated
  using (public.is_owner())
  with check (public.is_owner());

-- Replace handle_new_user() to also apply a matching invite, if the
-- signup metadata included one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.staff_invites;
  v_code text;
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');

  v_code := new.raw_user_meta_data ->> 'invite_code';

  if v_code is not null then
    select * into v_invite
    from public.staff_invites
    where lower(email) = lower(new.email)
      and invite_code = v_code
      and used_at is null
      and expires_at > now()
    limit 1;

    if v_invite.id is null then
      raise exception 'Invalid or expired staff invite code';
    end if;

    update public.profiles set role = v_invite.role where id = new.id;
    update public.staff_invites set used_at = now(), used_by = new.id where id = v_invite.id;
  end if;

  return new;
end;
$$;
