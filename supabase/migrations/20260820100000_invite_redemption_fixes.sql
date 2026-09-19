-- Makes staff invites actually redeemable.
--
-- Three defects, all of which made a correct code look wrong:
--
--   1. Codes are generated uppercase but matched with `=`. Someone who
--      typed theirs in lowercase -- which a phone keyboard will happily
--      do -- got "invalid code" for a perfectly good invite.
--   2. Every failure raised the same message, and GoTrue flattens a
--      trigger error into "Database error saving new user" anyway, so
--      the app could not tell "wrong code" from "already used" from
--      "you signed up with a different email".
--   3. The trigger only runs on *new* accounts. Inviting someone who
--      already shops with the customer app did nothing at all: their
--      signup failed as a duplicate and the invite sat unused forever.
--      That is the common case, not the edge case.

-- Match case- and whitespace-insensitively, and say which of the four
-- things went wrong.
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
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone'
  );

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

    update public.profiles set role = v_invite.role where id = new.id;
    update public.staff_invites
      set used_at = now(), used_by = new.id
      where id = v_invite.id;
  end if;

  return new;
end;
$$;

-- Checked *before* signing up, so the person gets a real explanation
-- instead of a 500 from the auth service.
--
-- Callable without a session, because there is no session yet at signup.
-- Every detailed answer requires already knowing the exact code, so this
-- confirms nothing to somebody who only knows an email address.
create or replace function public.check_staff_invite(p_email text, p_code text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_invite public.staff_invites;
begin
  if p_email is null or p_code is null then
    return 'not_found';
  end if;

  select * into v_invite
  from public.staff_invites
  where lower(btrim(email)) = lower(btrim(p_email))
    and upper(btrim(invite_code)) = upper(btrim(p_code))
  order by created_at desc
  limit 1;

  if v_invite.id is null then return 'not_found'; end if;
  if v_invite.used_at is not null then return 'used'; end if;
  if v_invite.expires_at <= now() then return 'expired'; end if;
  return 'ok';
end;
$$;

-- Lets somebody who already has an account redeem an invite, which the
-- signup trigger cannot do -- it only ever fires once, at account
-- creation. Promotes the caller and nobody else: the invite has to have
-- been issued to the email address on their own session.
create or replace function public.redeem_staff_invite(p_code text)
returns public.user_role
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.staff_invites;
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'NOT_SIGNED_IN';
  end if;

  select email into v_email from auth.users where id = auth.uid();

  select * into v_invite
  from public.staff_invites
  where lower(btrim(email)) = lower(btrim(v_email))
    and upper(btrim(invite_code)) = upper(btrim(coalesce(p_code, '')))
  order by created_at desc
  limit 1;

  if v_invite.id is null then raise exception 'INVITE_NOT_FOUND'; end if;
  if v_invite.used_at is not null then raise exception 'INVITE_USED'; end if;
  if v_invite.expires_at <= now() then raise exception 'INVITE_EXPIRED'; end if;

  -- The role guard blocks anyone but an owner from changing a role, and
  -- it is right to. This is the one sanctioned exception: the invite has
  -- already been verified against the caller's own email, and the flag is
  -- transaction-local and cannot be set from outside this function.
  perform set_config('app.invite_redemption', 'on', true);

  update public.profiles set role = v_invite.role where id = auth.uid();
  update public.staff_invites
    set used_at = now(), used_by = auth.uid()
    where id = v_invite.id;

  return v_invite.role;
end;
$$;

create or replace function public.prevent_role_self_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and auth.uid() is not null
     and not public.is_owner()
     and coalesce(current_setting('app.invite_redemption', true), '') <> 'on' then
    raise exception 'Only an owner can change a profile role';
  end if;
  return new;
end;
$$;

revoke execute on function public.check_staff_invite(text, text) from public;
revoke execute on function public.redeem_staff_invite(text) from public;
grant execute on function public.check_staff_invite(text, text) to anon, authenticated;
grant execute on function public.redeem_staff_invite(text) to authenticated;
