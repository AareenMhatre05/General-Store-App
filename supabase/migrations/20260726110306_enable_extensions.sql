-- Extensions needed for distance-based delivery pricing (postgis)
-- and scheduled-order processing (pg_cron).
create extension if not exists postgis with schema extensions;
create extension if not exists pg_cron with schema extensions;
