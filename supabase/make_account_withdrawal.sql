-- Run this script in the Supabase SQL Editor for the Bank demo project.
-- This function performs a simulated withdrawal only; it never connects to a payment network.
-- SECURITY INVOKER keeps the caller's RLS permissions in force.

create or replace function public.make_account_withdrawal(
  p_account_number text,
  p_amount numeric,
  p_description text default 'Cash withdrawal'
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_account public.bank_accounts%rowtype;
  v_reference text;
begin
  if v_user_id is null then
    raise exception 'You must be signed in to make a withdrawal.';
  end if;

  if p_amount is null or p_amount <= 0 or round(p_amount, 2) <> p_amount then
    raise exception 'Enter a valid withdrawal amount with up to two decimal places.';
  end if;

  select *
    into v_account
    from public.bank_accounts
   where account_number = p_account_number
     and user_id = v_user_id
   for update;

  if not found then
    raise exception 'The selected account could not be found.';
  end if;

  if coalesce(v_account.account_status, '') <> 'active' then
    raise exception 'This account is not active.';
  end if;

  if p_amount > coalesce(v_account.available_balance, 0) then
    raise exception 'Insufficient available balance.';
  end if;

  update public.bank_accounts
     set available_balance = available_balance - p_amount
   where account_number = p_account_number
     and user_id = v_user_id;

  v_reference := 'WD' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 18));

  insert into public.bank_transactions (
    reference,
    sender_user_id,
    recipient_user_id,
    amount,
    currency_code,
    description,
    status,
    transaction_type,
    is_synthetic
  ) values (
    v_reference,
    v_user_id,
    null,
    p_amount,
    coalesce(v_account.currency_code, 'USD'),
    coalesce(nullif(trim(p_description), ''), 'Cash withdrawal'),
    'completed',
    'debit',
    true
  );

  return jsonb_build_object(
    'success', true,
    'reference', v_reference,
    'amount', p_amount,
    'currency_code', coalesce(v_account.currency_code, 'USD'),
    'account_number', p_account_number,
    'new_balance', v_account.available_balance - p_amount
  );
end;
$$;

grant execute on function public.make_account_withdrawal(text, numeric, text) to authenticated;
