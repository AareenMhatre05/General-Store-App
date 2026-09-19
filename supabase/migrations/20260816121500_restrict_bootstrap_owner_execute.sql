-- `revoke execute ... from public` in the previous migration was not
-- enough: Supabase grants EXECUTE on public schema functions to the
-- anon and authenticated roles explicitly, and an explicit grant is not
-- removed by revoking from PUBLIC. So bootstrap_owner() was still
-- callable by any signed-in user.
--
-- In practice a client call would have failed anyway -- the function is
-- security invoker, so it hits "permission denied for table users" on
-- the auth.users lookup, and the staff_invites insert would be blocked
-- by RLS. But a function whose entire purpose is granting the owner
-- role should not be reachable from a client at all, regardless of what
-- stops it further in. Closing it explicitly.

revoke execute on function public.bootstrap_owner(text) from anon;
revoke execute on function public.bootstrap_owner(text) from authenticated;
