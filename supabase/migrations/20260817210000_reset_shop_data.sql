-- A clean-slate switch for the end of testing.
--
-- During testing the shop fills up with invented products, fake orders
-- and throwaway categories. This wipes that so the owner starts from
-- nothing, WITHOUT destroying the things that took real effort to set
-- up: accounts and their roles, the shop's location, and the delivery
-- fee bands.
--
-- Three safeguards, because this is irreversible:
--
--   1. A confirmation phrase must be passed. No stray `select
--      reset_shop_data()` can fire it.
--   2. EXECUTE is revoked from anon and authenticated, so it is
--      unreachable from either app no matter who is signed in -- the
--      lesson from Decisions.md D33.
--   3. It reports what it deleted, so the result is visible rather than
--      assumed.
--
-- Run from the SQL editor only:
--   select public.reset_shop_data('DELETE ALL SHOP DATA');

create or replace function public.reset_shop_data(p_confirm text)
returns text
language plpgsql
set search_path = public
as $$
declare
  n_orders int; n_products int; n_categories int;
  n_offers int; n_inquiries int; n_adjustments int;
  n_addresses int; n_images int;
begin
  if p_confirm is distinct from 'DELETE ALL SHOP DATA' then
    raise exception
      'reset_shop_data: pass the exact phrase DELETE ALL SHOP DATA to confirm';
  end if;

  -- Counted before deleting, so the report is truthful.
  select count(*) into n_orders from public.orders;
  select count(*) into n_products from public.products;
  select count(*) into n_categories from public.categories;
  select count(*) into n_offers from public.offers;
  select count(*) into n_inquiries from public.product_inquiries;
  select count(*) into n_adjustments from public.inventory_adjustments;
  select count(*) into n_addresses from public.addresses;
  select count(*) into n_images from public.product_images;

  -- Order matters. Orders first: deleting them cascades to order_items,
  -- their cost snapshots and any delivery assignment. The restock
  -- trigger fires along the way and writes ledger rows -- harmless,
  -- because the ledger is cleared immediately after.
  delete from public.orders;
  delete from public.inventory_adjustments;

  delete from public.product_inquiries;
  delete from public.offers;
  delete from public.product_images;
  delete from public.product_costs;
  delete from public.products;      -- safe now: nothing references them
  delete from public.categories;

  -- Test delivery addresses go too; orders referencing them are gone.
  delete from public.addresses;
  delete from public.delivery_locations;

  -- Uploaded photos. The rows go here; if any files linger in the
  -- bucket, clear them from Dashboard -> Storage -> product-images.
  delete from storage.objects where bucket_id = 'product-images';

  -- DELIBERATELY KEPT:
  --   profiles / auth.users  -- accounts and roles survive
  --   store_settings         -- shop location and address
  --   delivery_fee_tiers     -- the distance bands
  --   staff_invites          -- unused invites stay usable

  return format(
    'Cleared: %s orders, %s products, %s categories, %s offers, %s inquiries, '
    '%s stock adjustments, %s addresses, %s images. '
    'Kept: accounts, roles, store location, delivery fee bands.',
    n_orders, n_products, n_categories, n_offers, n_inquiries,
    n_adjustments, n_addresses, n_images
  );
end;
$$;

comment on function public.reset_shop_data(text) is
  'Admin-only clean slate for the end of testing. Wipes catalog and orders; keeps accounts, store location and fee bands. Requires the confirmation phrase.';

revoke execute on function public.reset_shop_data(text) from public;
revoke execute on function public.reset_shop_data(text) from anon;
revoke execute on function public.reset_shop_data(text) from authenticated;
