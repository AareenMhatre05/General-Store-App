-- Scheduled orders: a customer can place an order for a future delivery
-- slot (status = 'scheduled', scheduled_for = the requested time). This
-- job promotes it to 'confirmed' once that time arrives, so staff pick
-- it up in their normal queue.
--
-- This is intentionally minimal (a status flip) -- notifying the staff
-- app / customer in real time can be layered on later via a Realtime
-- subscription or an Edge Function, once that workflow is designed.

select cron.schedule(
  'promote-scheduled-orders',
  '* * * * *',
  $$
    update public.orders
    set status = 'confirmed'
    where status = 'scheduled'
      and scheduled_for <= now();
  $$
);
