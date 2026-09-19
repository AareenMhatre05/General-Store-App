-- Lets a client tell what actually changed on an order.
--
-- Realtime sends an `old_record` alongside every UPDATE, but by default
-- Postgres only puts the primary key in it. That is enough to know
-- *which* row changed and useless for knowing *what* changed: an app
-- watching for "the shop accepted my order" would see status='confirmed'
-- on every later edit too -- payment marked paid, a note added -- and
-- announce the acceptance again each time.
--
-- REPLICA IDENTITY FULL puts the whole previous row in the WAL, so
-- old_record carries the old status and the comparison is exact.
--
-- Cost: updates and deletes write more WAL. On a table this size -- a
-- neighbourhood shop's orders -- that is not a consideration. Realtime
-- still filters by RLS, so nobody sees a row they could not already
-- read.

alter table public.orders replica identity full;
