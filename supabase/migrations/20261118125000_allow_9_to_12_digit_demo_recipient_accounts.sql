-- Keep demo recipient account numbers consistent with the customer transfer form.
-- The application accepts 9–12 numeric digits; the database must accept the same range.
alter table public.demo_recipients
  drop constraint if exists demo_recipients_account_number_check;

alter table public.demo_recipients
  add constraint demo_recipients_account_number_check
  check (account_number ~ '^[0-9]{9,12}$');
