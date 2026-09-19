-- Bootstrapping the first owner account.
--
-- Chicken-and-egg problem: staff_invites is protected by
-- "Owner can manage staff invites" (is_owner()), so an owner is needed
-- to create the invite that makes someone an owner. The very first one
-- therefore has to be issued from an admin context -- the Supabase SQL
-- editor / service role -- where RLS does not apply.
--
-- This function is that admin entry point. Call it once, with the
-- email that should own the store:
--
--     select public.bootstrap_owner('store@example.com');
--
-- It handles both cases:
--   * no account yet  -> issues an owner invite and returns the code,
--                        which is typed into the staff app's signup
--                        screen (handle_new_user() then promotes the
--                        new profile to 'owner' -- see Decisions.md D8)
--   * account exists  -> promotes that profile to 'owner' directly and
--                        returns a message saying so
--
-- Deliberately NOT security definer, and execute is revoked from
-- PUBLIC: this must only ever run as a superuser/service role. If it
-- were callable by authenticated clients it would be a straight
-- privilege-escalation hole, since its whole job is handing out the
-- owner role.

create or replace function public.bootstrap_owner(p_email text)
returns text
language plpgsql
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_code text;
begin
  if p_email is null or position('@' in p_email) = 0 then
    raise exception 'bootstrap_owner: a valid email is required';
  end if;

  -- Already signed up? Promote in place -- a second signup with the
  -- same email would just fail with "user already registered".
  select p.id
  into v_profile_id
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(u.email) = lower(p_email)
  limit 1;

  if v_profile_id is not null then
    update public.profiles
    set role = 'owner'
    where id = v_profile_id;

    -- auth.uid() is null in this admin context, so
    -- prevent_role_self_escalation() lets this through (Decisions.md D9).
    return format('Existing account %s promoted to owner.', p_email);
  end if;

  -- Reuse an unused, unexpired invite rather than piling up rows if
  -- this gets called twice.
  select invite_code
  into v_code
  from public.staff_invites
  where lower(email) = lower(p_email)
    and role = 'owner'
    and used_at is null
    and expires_at > now()
  limit 1;

  if v_code is null then
    insert into public.staff_invites (email, role, expires_at)
    values (lower(p_email), 'owner', now() + interval '30 days')
    returning invite_code into v_code;
  end if;

  return format(
    'Owner invite for %s -- sign up in the staff app with this code: %s',
    p_email,
    v_code
  );
end;
$$;

comment on function public.bootstrap_owner(text) is
  'Admin-only: issues (or reuses) an owner invite for an email, or promotes that email''s existing account to owner. Run from the SQL editor / service role only.';

revoke execute on function public.bootstrap_owner(text) from public;
