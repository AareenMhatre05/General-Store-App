-- record_writeoff_stock() wrote to inventory_adjustments.notes, but the
-- column is called `note`. Every write-off therefore failed outright
-- with "column notes of relation inventory_adjustments does not exist",
-- so the feature could not have worked for staff at all.
--
-- Caught by running the flow as the owner rather than trusting that the
-- migration applying meant the trigger was correct: applying only proves
-- the function compiles, not that its body runs. plpgsql resolves column
-- names at execution time, so a wrong name is invisible until fired.

create or replace function public.record_writeoff_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.inventory_adjustments
    (product_id, change_quantity, reason, note)
  values (
    new.product_id,
    -new.quantity,
    'wastage',
    coalesce(new.notes, new.reason)
  );
  return new;
end;
$$;
