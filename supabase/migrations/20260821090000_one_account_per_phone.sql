-- One customer account per mobile number.
--
-- The point is to stop somebody opening a second account with a fresh
-- email address to claim a first-order offer twice. Three things have to
-- be true for it to actually work, and the obvious `unique (phone)` gets
-- all three wrong:
--
--   1. Numbers must be compared in a normalised form. 8766008705,
--      +918766008705, 08766008705 and "+91 87660 08705" are one number
--      and four different strings; a plain unique index stops none of it.
--   2. Phone has to be required, because a unique index permits any
--      number of NULLs -- while the field is optional the constraint is
--      decoration.
--   3. It has to apply to customers only. The shop's own number will
--      legitimately sit on the owner's profile and on staff profiles.
--
-- What this does NOT do is verify that the person owns the number --
-- that needs OTP, which was ruled out. It raises the bar; it is not
-- identity proof.

-- Last ten digits, which is how Indian mobile numbers are actually typed
-- however the country code is written.
alter table public.profiles
  add column phone_normalized text
  generated always as (
    nullif(right(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), 10), '')
  ) stored;

-- Server-side format check, because the client's validator is a
-- convenience and not a control.
alter table public.profiles
  add constraint profiles_phone_is_mobile
  check (
    phone is null
    or right(regexp_replace(phone, '[^0-9]', '', 'g'), 10) ~ '^[6-9][0-9]{9}$'
  );

-- Customers must have one; staff, delivery and the owner need not.
alter table public.profiles
  add constraint profiles_customer_has_phone
  check (role <> 'customer' or phone is not null);

create unique index profiles_customer_phone_unique
  on public.profiles (phone_normalized)
  where role = 'customer' and phone_normalized is not null;

-- handle_new_user inserted the profile as a customer and *then* promoted
-- it, which now breaks staff signup: the insert would trip
-- profiles_customer_has_phone before the role was corrected, and staff
-- are never asked for a number. Work out the role first and insert once.
-- It also means a signup no longer touches the role-escalation guard at
-- all.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.staff_invites;
  v_code text;
  v_role public.user_role := 'customer';
begin
  v_code := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'invite_code', '')), '');

  if v_code is not null then
    select * into v_invite
    from public.staff_invites
    where lower(btrim(email)) = lower(btrim(new.email))
      and upper(btrim(invite_code)) = upper(v_code)
    order by created_at desc
    limit 1;

    if v_invite.id is null then
      raise exception 'INVITE_NOT_FOUND';
    elsif v_invite.used_at is not null then
      raise exception 'INVITE_USED';
    elsif v_invite.expires_at <= now() then
      raise exception 'INVITE_EXPIRED';
    end if;

    v_role := v_invite.role;
  end if;

  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone',
    v_role
  );

  if v_invite.id is not null then
    update public.staff_invites
      set used_at = now(), used_by = new.id
      where id = v_invite.id;
  end if;

  return new;
end;
$$;

-- Asked before signing up, for the same reason as check_staff_invite:
-- a constraint violation raised inside handle_new_user reaches the app
-- as "Database error saving new user", which tells the person nothing.
--
-- Trade-off, stated plainly: this confirms whether a given number has an
-- account here. The caller must already know the full ten digits, so it
-- is a lookup rather than a way to enumerate customers, and for a
-- neighbourhood grocery the exposure is the same as the one every site
-- has on "email already registered". If that is ever unwelcome, delete
-- this function -- the unique index, not this, is what enforces the rule.
create or replace function public.phone_available(p_phone text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
    where role = 'customer'
      and phone_normalized is not null
      and phone_normalized = nullif(
            right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 10), '')
  );
$$;

revoke execute on function public.phone_available(text) from public;
grant execute on function public.phone_available(text) to anon, authenticated;
