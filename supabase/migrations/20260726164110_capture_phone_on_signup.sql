-- Customer app now collects a phone number at signup (Zomato/Blinkit-
-- style profile data), still via plain email/password auth for now --
-- phone/OTP login itself is on hold pending an SMS provider decision.
-- Store it the same way full_name already is: as signup metadata,
-- picked up here.

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
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'phone');

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
