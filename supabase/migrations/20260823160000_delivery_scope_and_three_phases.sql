-- Two changes: delivery partners see only their own work, and the
-- "preparing" phase goes away.
--
-- ---------------------------------------------------------------
-- 1. Narrow the delivery role
-- ---------------------------------------------------------------
-- The previous migration put 'delivery' inside is_staff_or_owner(),
-- which is referenced by 36 policies. That was too blunt: it handed a
-- delivery partner every order, every customer's address and every
-- profile in the shop, when what they need is the handful of drops
-- assigned to them.
--
-- is_staff_or_owner() goes back to meaning exactly what its name says.
-- Delivery access is then granted table by table, each one restricted to
-- orders actually assigned to the caller.

create or replace function public.is_staff_or_owner()
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

-- True when this order is currently assigned to the caller. SECURITY
-- DEFINER so the check itself does not recurse through the policies it
-- is used by.
create or replace function public.is_my_delivery(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.delivery_assignments
    where order_id = p_order_id
      and delivery_user_id = auth.uid()
  );
$$;

revoke execute on function public.is_my_delivery(uuid) from public;
grant execute on function public.is_my_delivery(uuid) to authenticated;

-- The order itself, and what is in it.
create policy "Delivery partner sees assigned orders" on public.orders
  for select using (public.is_my_delivery(id));

-- Marking a drop as collected or delivered. Restricted to assigned
-- orders; the status values they may set are enforced by the trigger
-- below rather than here, because a WITH CHECK cannot see the old row.
create policy "Delivery partner updates assigned orders" on public.orders
  for update using (public.is_my_delivery(id))
  with check (public.is_my_delivery(id));

create policy "Delivery partner sees assigned order items" on public.order_items
  for select using (public.is_my_delivery(order_id));

-- Where to take it.
create policy "Delivery partner sees the drop address" on public.addresses
  for select using (
    exists (
      select 1 from public.orders o
      where o.delivery_address_id = addresses.id
        and public.is_my_delivery(o.id)
    )
  );

-- Who to hand it to, and the number to ring when they cannot find the
-- door. Only the customer on an assigned order -- not the whole
-- customer list, and not other staff.
create policy "Delivery partner sees the recipient" on public.profiles
  for select using (
    exists (
      select 1 from public.orders o
      where o.customer_id = profiles.id
        and public.is_my_delivery(o.id)
    )
  );

-- A delivery partner may move an order along its last two steps and
-- nothing else -- not back to confirmed, not to cancelled, and no edits
-- to totals or addresses.
create or replace function public.restrict_delivery_order_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Staff, owner and the customer's own actions are governed by their
  -- own policies; this guard is only for the delivery role.
  if coalesce((select role from public.profiles where id = auth.uid()), 'customer')
     is distinct from 'delivery' then
    return new;
  end if;

  if new.status not in ('out_for_delivery', 'delivered') then
    raise exception 'A delivery partner can only mark an order picked up or delivered';
  end if;

  if new.customer_id is distinct from old.customer_id
     or new.delivery_address_id is distinct from old.delivery_address_id
     or new.total_amount is distinct from old.total_amount
     or new.subtotal_amount is distinct from old.subtotal_amount
     or new.delivery_fee_amount is distinct from old.delivery_fee_amount then
    raise exception 'A delivery partner can only change the status of an order';
  end if;

  return new;
end;
$$;

create trigger orders_restrict_delivery_updates
  before update on public.orders
  for each row execute function public.restrict_delivery_order_updates();

-- ---------------------------------------------------------------
-- 2. Three phases, not four
-- ---------------------------------------------------------------
-- An order now goes confirmed -> out_for_delivery -> delivered.
-- "preparing" sat between the first two and told the customer nothing
-- they could act on.
--
-- The enum value itself stays: Postgres has no DROP VALUE, and removing
-- it would mean rebuilding the type and every column, view and policy
-- that mentions it. Nothing writes it any more, and nothing reads it --
-- no rows currently use it, so there is nothing to migrate either. Left
-- deliberately, not overlooked.
update public.orders set status = 'confirmed' where status = 'preparing';

-- One policy still listed it as a state in which a customer may watch
-- their partner move.
alter policy "Customer sees the partner carrying their live order"
  on public.delivery_locations
  using (
    exists (
      select 1
      from public.delivery_assignments da
      join public.orders o on o.id = da.order_id
      where da.delivery_user_id = delivery_locations.delivery_user_id
        and o.customer_id = auth.uid()
        and da.delivered_at is null
        and o.status in ('confirmed', 'out_for_delivery')
    )
  );

-- ---------------------------------------------------------------
-- 3. Live updates
-- ---------------------------------------------------------------
-- Realtime already carries product_inquiries, delivery_assignments and
-- delivery_locations. Orders are the thing everyone actually watches --
-- the shop for new ones, the customer for progress -- and were the
-- reason both apps needed a pull-to-refresh.
alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.order_items;
