-- The delivery partner is the one who takes the cash, so they are the
-- one who can mark it received.
--
-- Everything here is cash on delivery, which means the money changes
-- hands at the door. Until now only staff could set payment_status, so
-- the shop's outstanding figure stayed wrong until somebody at the
-- counter remembered to tick it off an order they were not present for.
--
-- The previous guard refused any update that was not a status change,
-- which included this one. It now allows exactly two things on an
-- assigned order: moving it through the last two phases, and recording
-- payment as received. Amounts, addresses and ownership stay untouchable.

create or replace function public.restrict_delivery_order_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce((select role from public.profiles where id = auth.uid()), 'customer')
     is distinct from 'delivery' then
    return new;
  end if;

  -- A status change, if there is one, may only be to these two.
  if new.status is distinct from old.status
     and new.status not in ('out_for_delivery', 'delivered') then
    raise exception 'A delivery partner can only mark an order picked up or delivered';
  end if;

  -- Payment may only move forward to paid. Not back to pending, and not
  -- to refunded -- a refund is the shop's decision, not the courier's.
  if new.payment_status is distinct from old.payment_status
     and new.payment_status <> 'paid' then
    raise exception 'A delivery partner can only record payment as received';
  end if;

  if new.customer_id is distinct from old.customer_id
     or new.delivery_address_id is distinct from old.delivery_address_id
     or new.total_amount is distinct from old.total_amount
     or new.subtotal_amount is distinct from old.subtotal_amount
     or new.delivery_fee_amount is distinct from old.delivery_fee_amount
     or new.channel is distinct from old.channel then
    raise exception 'A delivery partner can only change the status of an order';
  end if;

  return new;
end;
$$;
