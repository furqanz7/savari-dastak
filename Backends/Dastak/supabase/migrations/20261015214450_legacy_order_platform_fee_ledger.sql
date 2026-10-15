-- The later platform-fee column increased the captured total, but the legacy
-- settlement allocation still credited only the original four components.
-- Keep existing journals immutable; only new settlements receive the extra leg.
set local lock_timeout='5s';
set local statement_timeout='30s';
alter table private.merchant_order_ledger_entries
  drop constraint merchant_order_ledger_entries_account_code_check;
alter table private.merchant_order_ledger_entries
  add constraint merchant_order_ledger_entries_account_code_check check (
    account_code in ('provider_clearing','customer_funds_held','refund_payable',
      'merchant_payable','courier_payable','platform_merchant_commission',
      'platform_delivery_margin','platform_fee')
  );

create or replace function private.post_merchant_order_settlement(
  order_row private.merchant_orders, p_source_event_id text
) returns void language plpgsql volatile security invoker set search_path='' as $$
declare v_transaction_id uuid;
begin
  insert into private.merchant_order_ledger_transactions(order_id,kind,source_event_id)
  values ((order_row).id,'order_settlement',p_source_event_id)
  on conflict (order_id,kind) do nothing returning id into v_transaction_id;
  if v_transaction_id is null then return; end if;
  insert into private.merchant_order_ledger_entries
    (transaction_id,order_id,account_code,side,amount_paise)
  values (v_transaction_id,(order_row).id,'customer_funds_held','debit',(order_row).total_paise);
  insert into private.merchant_order_ledger_entries
    (transaction_id,order_id,account_code,side,amount_paise)
  select v_transaction_id,(order_row).id,allocation.account_code,'credit',allocation.amount_paise
  from (values
    ('merchant_payable'::text,(order_row).merchant_payable_paise),
    ('courier_payable'::text,(order_row).courier_payout_paise::bigint),
    ('platform_merchant_commission'::text,(order_row).merchant_commission_paise),
    ('platform_delivery_margin'::text,(order_row).platform_delivery_margin_paise::bigint),
    ('platform_fee'::text,(order_row).platform_fee_paise)
  ) allocation(account_code,amount_paise) where allocation.amount_paise>0;
  perform private.assert_merchant_order_transaction_balanced(v_transaction_id);
end;
$$;
