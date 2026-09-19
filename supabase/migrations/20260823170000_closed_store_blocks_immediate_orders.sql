-- A closed shop does not take orders for right now.
--
-- The customer app hides the button, but a hidden button is not a rule:
-- anything that can talk to PostgREST can still insert a row. This is
-- where "we are closed" is actually enforced.
--
-- Scheduled orders are deliberately still allowed. Ordering at ten at
-- night for tomorrow morning is the whole point of scheduling, and the
-- shop still gets to confirm or decline the slot when it opens.
--
-- Counter sales are unaffected: the toggle is about accepting orders
-- through the app, not about whether anyone is in the building.

create or replace function public.reject_orders_while_closed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open boolean;
begin
  if new.channel is distinct from 'delivery' then
    return new;
  end if;

  -- Staff placing an order on someone's behalf are already in the shop.
  if public.is_staff_or_owner() then
    return new;
  end if;

  if new.scheduled_for is not null or new.status = 'scheduled' then
    return new;
  end if;

  select is_open into v_open from public.store_settings limit 1;

  if coalesce(v_open, true) = false then
    raise exception 'STORE_CLOSED'
      using hint = 'The shop is closed. Schedule this order instead, or try again once it opens.';
  end if;

  return new;
end;
$$;

create trigger orders_reject_while_closed
  before insert on public.orders
  for each row execute function public.reject_orders_while_closed();

-- The customer's live tracking needs to see the partner move, which
-- means the position row has to arrive over Realtime rather than being
-- polled. The read is already fenced: a customer may only select rows
-- for the partner currently carrying one of their live orders.
alter publication supabase_realtime add table public.store_settings;
