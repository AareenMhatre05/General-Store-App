-- restock_on_order_item_delete() wrote the ledger row with
-- reference_order_id = old.order_id. That is right when a single line is
-- removed from a sale, but wrong when the whole order is deleted: the
-- cascade removes the parent first, so the foreign key has nothing to
-- point at and the delete fails outright.
--
-- Found by a test that deleted its own fixture order. The app never
-- deletes orders (it voids them, keeping the record), so nothing in
-- production hit it -- but a landmine that only goes off later is still
-- a landmine.
--
-- The restock itself is still correct in both cases: the goods came
-- back either way. Only the reference is dropped.

create or replace function public.restock_on_order_item_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_exists boolean;
begin
  select exists (select 1 from public.orders where id = old.order_id)
  into v_order_exists;

  insert into public.inventory_adjustments
    (product_id, change_quantity, reason, reference_order_id)
  values (
    old.product_id,
    old.quantity,
    'correction',
    case when v_order_exists then old.order_id else null end
  );

  return old;
end;
$$;
