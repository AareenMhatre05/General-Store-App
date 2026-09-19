-- Two integrity gaps closed here:
--
-- 1. Nothing computed distance_meters/delivery_fee_amount server-side --
--    a client could otherwise submit whatever delivery fee it liked.
-- 2. Nothing kept orders.subtotal_amount/total_amount in sync with
--    order_items -- same problem, for the order total itself.
--
-- Both are now computed automatically and are not something the client
-- can override (they run as SECURITY DEFINER where they touch orders
-- via UPDATE, since customers have no UPDATE policy on that table).

create or replace function public.compute_delivery_fee_for_order()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_distance numeric;
begin
  if new.channel = 'delivery' then
    select extensions.st_distance(s.location, a.location)
    into v_distance
    from public.store_settings s, public.addresses a
    where s.id = 1 and a.id = new.delivery_address_id;

    new.distance_meters := v_distance;
    new.delivery_fee_amount := coalesce(public.get_delivery_fee(v_distance), 0);
  else
    new.distance_meters := null;
    new.delivery_fee_amount := 0;
  end if;

  return new;
end;
$$;

create trigger orders_compute_delivery_fee
  before insert on public.orders
  for each row execute function public.compute_delivery_fee_for_order();

create or replace function public.recalculate_order_totals(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.orders
  set subtotal_amount = coalesce(
        (select sum(subtotal) from public.order_items where order_id = p_order_id),
        0
      )
  where id = p_order_id;

  update public.orders
  set total_amount = subtotal_amount + delivery_fee_amount
  where id = p_order_id;
end;
$$;

create or replace function public.order_items_recalculate_totals()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalculate_order_totals(old.order_id);
    return old;
  else
    perform public.recalculate_order_totals(new.order_id);
    return new;
  end if;
end;
$$;

create trigger order_items_recalculate_totals
  after insert or update or delete on public.order_items
  for each row execute function public.order_items_recalculate_totals();
