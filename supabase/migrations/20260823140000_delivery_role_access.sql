-- Lets a delivery partner into the staff app, without showing them what
-- the shop pays its suppliers.
--
-- `is_staff_or_owner()` guards 36 policies, so widening it to include
-- 'delivery' is most of the job in one line. But two of those policies
-- cover product_costs and order_item_costs -- purchase prices and the
-- profit on every sale. That is the one thing in this database that
-- should not travel further than it has to, and a delivery partner has
-- no use for it.
--
-- So the old definition is kept under a new name and the two cost
-- tables are repointed at it. Staff and owner behaviour is unchanged;
-- delivery gains everything operational and nothing financial.

create or replace function public.can_see_costs()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role in ('staff', 'owner') from public.profiles where id = auth.uid()),
    false
  );
$$;

revoke execute on function public.can_see_costs() from public;
grant execute on function public.can_see_costs() to authenticated;

alter policy "Staff and owner can view product costs" on public.product_costs
  using (public.can_see_costs());
alter policy "Staff and owner can manage product costs" on public.product_costs
  using (public.can_see_costs()) with check (public.can_see_costs());

alter policy "Staff and owner can view order item costs" on public.order_item_costs
  using (public.can_see_costs());
alter policy "Staff and owner can manage order item costs" on public.order_item_costs
  using (public.can_see_costs()) with check (public.can_see_costs());

-- Now widen the general one. Everything still pointing at it -- orders,
-- products, chat, addresses, write-offs, store settings -- opens to
-- delivery as well.
create or replace function public.is_staff_or_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role in ('staff', 'owner', 'delivery')
       from public.profiles where id = auth.uid()),
    false
  );
$$;

-- Issuing invites stays owner-only: is_owner() is untouched, so a
-- delivery partner cannot add anybody to the team.
