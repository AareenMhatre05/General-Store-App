-- Lets the owner invite a delivery partner.
--
-- `delivery` was added to the user_role enum when delivery tracking went
-- in, but staff_invites carries its own CHECK constraint listing the
-- roles an invite may grant, and that was never widened. The Team screen
-- offers Delivery as an option, so choosing it failed against
-- staff_invites_role_check.
--
-- The constraint is still worth having: it stops an invite ever handing
-- out 'customer', which would be a silent no-op, and it keeps the set of
-- grantable roles explicit rather than "whatever the enum happens to
-- contain".

alter table public.staff_invites
  drop constraint staff_invites_role_check;

alter table public.staff_invites
  add constraint staff_invites_role_check
  check (role in ('staff', 'owner', 'delivery'));
