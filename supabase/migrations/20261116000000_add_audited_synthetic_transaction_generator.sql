alter table public.bank_transactions
  add column if not exists is_synthetic boolean not null default false,
  add column if not exists synthetic_batch_id uuid;

alter table public.bank_transactions
  drop constraint if exists bank_transactions_transaction_type_check;
alter table public.bank_transactions
  add constraint bank_transactions_transaction_type_check
  check (transaction_type in ('transfer','debit','credit'));

create index if not exists bank_transactions_synthetic_batch_idx
  on public.bank_transactions (synthetic_batch_id)
  where is_synthetic = true;

create or replace function public.manager_generate_test_transactions(
  p_manager_user_id uuid,
  p_account_id uuid,
  p_transactions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_account public.bank_accounts%rowtype;
  v_item jsonb;
  v_amount numeric(14,2);
  v_type text;
  v_total_delta numeric(14,2) := 0;
  v_count integer := 0;
  v_batch uuid := gen_random_uuid();
  v_reference text;
  v_created_at timestamptz;
  v_description text;
begin
  if not exists (
    select 1 from public.manager_users
    where user_id = p_manager_user_id and role in ('manager','admin')
  ) then
    raise exception 'Manager authorization required';
  end if;

  if jsonb_typeof(p_transactions) <> 'array'
     or jsonb_array_length(p_transactions) < 1
     or jsonb_array_length(p_transactions) > 200 then
    raise exception 'Transaction count must be between 1 and 200';
  end if;

  select * into v_account
  from public.bank_accounts
  where id = p_account_id
  for update;

  if not found then raise exception 'Account not found'; end if;
  if v_account.account_status <> 'active' then
    raise exception 'Only active accounts can receive test activity';
  end if;

  for v_item in select value from jsonb_array_elements(p_transactions)
  loop
    v_amount := (v_item->>'amount')::numeric;
    v_type := v_item->>'type';
    v_created_at := (v_item->>'created_at')::timestamptz;
    v_description := left(coalesce(v_item->>'description','Test transaction'),120);

    if v_amount <= 0 or v_amount > 10000000 then
      raise exception 'Each amount must be greater than zero and no more than 10000000';
    end if;
    if v_type not in ('debit','credit') then
      raise exception 'Transaction type must be debit or credit';
    end if;
    if v_created_at is null then raise exception 'Transaction date is required'; end if;

    v_total_delta := v_total_delta + case when v_type='credit' then v_amount else -v_amount end;
    v_count := v_count + 1;
    v_reference := 'TEST-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,16));

    insert into public.bank_transactions (
      reference, sender_user_id, recipient_user_id,
      from_account_id, to_account_id, transaction_type,
      amount, currency_code, description, status, created_at,
      is_synthetic, synthetic_batch_id
    ) values (
      v_reference, v_account.user_id, v_account.user_id,
      case when v_type='debit' then v_account.id else null end,
      case when v_type='credit' then v_account.id else null end,
      v_type, v_amount, v_account.currency_code,
      'TEST RECORD · ' || v_description, 'completed', v_created_at,
      true, v_batch
    );
  end loop;

  if v_account.available_balance + v_total_delta < 0 then
    raise exception 'These debits exceed the available balance';
  end if;

  update public.bank_accounts
  set available_balance = available_balance + v_total_delta
  where id = p_account_id;

  insert into public.manager_audit_log (
    manager_user_id, bank_account_id, customer_user_id, action,
    old_balance, new_balance, old_status, new_status
  ) values (
    p_manager_user_id, p_account_id, v_account.user_id,
    'generated_test_transactions', v_account.available_balance,
    v_account.available_balance + v_total_delta,
    v_account.account_status, v_account.account_status
  );

  return jsonb_build_object(
    'batch_id', v_batch, 'count', v_count,
    'net_balance_change', v_total_delta,
    'new_balance', v_account.available_balance + v_total_delta
  );
end;
$$;

revoke all on function public.manager_generate_test_transactions(uuid,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.manager_generate_test_transactions(uuid,uuid,jsonb) to service_role;
