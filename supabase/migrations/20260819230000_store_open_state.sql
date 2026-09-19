-- Whether the shop is currently serving.
--
-- A single flag the staff flip, rather than opening-hours rules: a
-- corner shop closes early for a wedding, opens late after a delivery,
-- and shuts entirely when the owner is ill. A schedule would be wrong
-- more often than it was right, and staff would end up overriding it
-- anyway.

alter table public.store_settings
  add column if not exists is_open boolean not null default true,
  add column if not exists closed_message text,
  add column if not exists status_changed_at timestamptz;

comment on column public.store_settings.is_open is
  'Flipped by staff. Customers see a closed banner when false.';
comment on column public.store_settings.closed_message is
  'Optional line shown to customers instead of the default closed text.';

-- Stamp the change so the customer app can say how long it has been
-- shut, and so a stale flag is obvious when reading the row.
create or replace function public.stamp_store_status_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_open is distinct from old.is_open then
    new.status_changed_at := now();
  end if;
  return new;
end;
$$;

create trigger store_settings_stamp_status
  before update on public.store_settings
  for each row execute function public.stamp_store_status_change();

-- Rebuild the coords view so the new columns come through it: the
-- original `select s.*` was expanded when the view was created.
drop view if exists public.store_settings_with_coords;
create view public.store_settings_with_coords
with (security_invoker = true)
as
select
  s.*,
  extensions.st_y(s.location::extensions.geometry) as latitude,
  extensions.st_x(s.location::extensions.geometry) as longitude
from public.store_settings s;
