-- The original prevent_role_self_escalation() checked is_owner(), which
-- reads auth.uid() -- but auth.uid() is NULL for anything run without a
-- user JWT (Supabase Dashboard's Table/SQL Editor, or a service-role
-- Edge Function). That accidentally blocked the store owner from
-- promoting staff/owner accounts by hand, which is the intended
-- provisioning path (there is no in-app self-service signup for staff).
--
-- Fix: only block the change when there IS an authenticated end-user
-- session and that user isn't an owner. Admin/dashboard/service-role
-- actions (no JWT) are always allowed through.

create or replace function public.prevent_role_self_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and auth.uid() is not null
     and not public.is_owner() then
    raise exception 'Only an owner can change a profile role';
  end if;
  return new;
end;
$$;
