-- When an order transitions into 'cancelled', restore the stock that
-- was deducted for each of its line items.

create or replace function public.restock_on_order_cancellation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    insert into public.inventory_adjustments (product_id, change_quantity, reason, reference_order_id)
    select product_id, quantity, 'cancellation', new.id
    from public.order_items
    where order_id = new.id;
  end if;
  return new;
end;
$$;

create trigger orders_restock_on_cancellation
  after update on public.orders
  for each row execute function public.restock_on_order_cancellation();
