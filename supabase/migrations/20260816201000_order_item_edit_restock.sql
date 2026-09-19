-- Editing a recorded sale has to keep stock honest.
--
-- record_sale_inventory_adjustment() fires only on INSERT, so removing a
-- line from a sale left its stock deducted forever, and changing a
-- quantity deducted the difference not at all. Staff can now correct a
-- mis-rung sale, so both cases need handling.
--
-- Both run as SECURITY DEFINER for the same reason the insert trigger
-- does: inventory_adjustments is staff-writable, but the ledger write
-- must succeed regardless of who triggered it.

create or replace function public.restock_on_order_item_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.inventory_adjustments
    (product_id, change_quantity, reason, reference_order_id)
  values (old.product_id, old.quantity, 'correction', old.order_id);
  return old;
end;
$$;

create trigger order_items_restock_on_delete
  after delete on public.order_items
  for each row execute function public.restock_on_order_item_delete();

create or replace function public.adjust_stock_on_order_item_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_delta integer;
begin
  -- A line moved to a different product: put the old one back whole and
  -- take the new one out whole.
  if new.product_id <> old.product_id then
    insert into public.inventory_adjustments
      (product_id, change_quantity, reason, reference_order_id)
    values (old.product_id, old.quantity, 'correction', old.order_id);

    insert into public.inventory_adjustments
      (product_id, change_quantity, reason, reference_order_id)
    values (new.product_id, -new.quantity, 'correction', new.order_id);

    return new;
  end if;

  -- Same product, changed quantity: move only the difference. Ordering
  -- one more unit deducts one more; ordering one fewer returns one.
  v_delta := old.quantity - new.quantity;
  if v_delta <> 0 then
    insert into public.inventory_adjustments
      (product_id, change_quantity, reason, reference_order_id)
    values (new.product_id, v_delta, 'correction', new.order_id);
  end if;

  return new;
end;
$$;

create trigger order_items_adjust_stock_on_update
  after update on public.order_items
  for each row execute function public.adjust_stock_on_order_item_update();
