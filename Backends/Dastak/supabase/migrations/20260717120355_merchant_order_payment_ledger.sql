alter table private.merchant_order_rate_cards
  add column merchant_commission_bps integer,
  add column courier_payout_paise integer;

update private.merchant_order_rate_cards
set merchant_commission_bps = 0,
    courier_payout_paise = delivery_fee_paise;

alter table private.merchant_order_rate_cards
  alter column merchant_commission_bps set not null,
  alter column courier_payout_paise set not null,
  alter column merchant_commission_bps set default 0,
  alter column courier_payout_paise set default 0,
  add constraint merchant_order_rate_cards_commission_check check (
    merchant_commission_bps between 0 and 10000
  ),
  add constraint merchant_order_rate_cards_courier_payout_check check (
    courier_payout_paise between 0 and delivery_fee_paise
  );

alter table private.merchant_order_quotes
  add column merchant_commission_bps integer,
  add column courier_payout_paise integer;

update private.merchant_order_quotes as quote
set merchant_commission_bps = rate.merchant_commission_bps,
    courier_payout_paise = rate.courier_payout_paise
from private.merchant_order_rate_cards as rate
where rate.id = quote.rate_card_id;

alter table private.merchant_order_quotes
  alter column merchant_commission_bps set not null,
  alter column courier_payout_paise set not null,
  add constraint merchant_order_quotes_commission_check check (
    merchant_commission_bps between 0 and 10000
  ),
  add constraint merchant_order_quotes_courier_payout_check check (
    courier_payout_paise between 0 and delivery_fee_paise
  );

alter table private.merchant_orders
  add column merchant_commission_bps integer,
  add column merchant_commission_paise bigint,
  add column merchant_payable_paise bigint,
  add column courier_payout_paise integer,
  add column platform_delivery_margin_paise integer;

update private.merchant_orders as merchant_order
set merchant_commission_bps = quote.merchant_commission_bps,
    merchant_commission_paise = (
      merchant_order.item_subtotal_paise * quote.merchant_commission_bps
    ) / 10000,
    merchant_payable_paise = merchant_order.item_subtotal_paise - (
      merchant_order.item_subtotal_paise * quote.merchant_commission_bps
    ) / 10000,
    courier_payout_paise = quote.courier_payout_paise,
    platform_delivery_margin_paise =
      merchant_order.delivery_fee_paise - quote.courier_payout_paise
from private.merchant_order_quotes as quote
where quote.id = merchant_order.quote_id;

alter table private.merchant_orders
  alter column merchant_commission_bps set not null,
  alter column merchant_commission_paise set not null,
  alter column merchant_payable_paise set not null,
  alter column courier_payout_paise set not null,
  alter column platform_delivery_margin_paise set not null,
  add constraint merchant_orders_commission_bps_check check (
    merchant_commission_bps between 0 and 10000
  ),
  add constraint merchant_orders_commission_amount_check check (
    merchant_commission_paise =
      (item_subtotal_paise * merchant_commission_bps) / 10000
  ),
  add constraint merchant_orders_merchant_payable_check check (
    merchant_payable_paise = item_subtotal_paise - merchant_commission_paise
    and merchant_payable_paise >= 0
  ),
  add constraint merchant_orders_courier_payout_check check (
    courier_payout_paise between 0 and delivery_fee_paise
  ),
  add constraint merchant_orders_delivery_margin_check check (
    platform_delivery_margin_paise = delivery_fee_paise - courier_payout_paise
  );

create table private.merchant_order_payment_records (
  order_id uuid primary key references private.merchant_orders(id),
  state text not null check (
    state in ('pending', 'captured', 'refund_pending', 'refunded', 'cancelled')
  ),
  settlement_state text not null default 'unallocated' check (
    settlement_state in ('unallocated', 'settled')
  ),
  currency text not null default 'INR' check (currency = 'INR'),
  expected_amount_paise bigint not null check (expected_amount_paise > 0),
  captured_amount_paise bigint not null default 0 check (captured_amount_paise >= 0),
  refund_reserved_paise bigint not null default 0 check (refund_reserved_paise >= 0),
  refunded_paise bigint not null default 0 check (refunded_paise >= 0),
  provider text check (
    provider is null or char_length(provider) between 1 and 40
  ),
  provider_order_reference text check (
    provider_order_reference is null
    or char_length(provider_order_reference) between 1 and 200
  ),
  provider_payment_reference text check (
    provider_payment_reference is null
    or char_length(provider_payment_reference) between 1 and 200
  ),
  captured_at timestamptz,
  refunded_at timestamptz,
  settled_at timestamptz,
  version bigint not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (captured_amount_paise <= expected_amount_paise),
  check (refund_reserved_paise <= captured_amount_paise),
  check (refunded_paise <= refund_reserved_paise),
  check (
    (state = 'pending' and captured_amount_paise = 0)
    or (state = 'cancelled' and captured_amount_paise = 0)
    or (
      state = 'captured'
      and captured_amount_paise = expected_amount_paise
      and refunded_paise = 0
    )
    or (
      state = 'refund_pending'
      and captured_amount_paise = expected_amount_paise
      and refund_reserved_paise > 0
      and refunded_paise = 0
    )
    or (
      state = 'refunded'
      and captured_amount_paise = expected_amount_paise
      and refund_reserved_paise > 0
      and refunded_paise = refund_reserved_paise
    )
  ),
  check (
    settlement_state = 'unallocated'
    or (
      settlement_state = 'settled'
      and state = 'captured'
      and refund_reserved_paise = 0
      and settled_at is not null
    )
  )
);

create table private.merchant_order_provider_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references private.merchant_orders(id),
  provider text not null check (char_length(provider) between 1 and 40),
  provider_event_id text not null check (
    char_length(provider_event_id) between 1 and 200
  ),
  event_type text not null check (
    event_type in ('payment_captured', 'refund_succeeded')
  ),
  provider_order_reference text check (
    provider_order_reference is null
    or char_length(provider_order_reference) between 1 and 200
  ),
  provider_payment_reference text check (
    provider_payment_reference is null
    or char_length(provider_payment_reference) between 1 and 200
  ),
  amount_paise bigint not null check (amount_paise > 0),
  occurred_at timestamptz not null,
  request_digest text not null check (
    char_length(request_digest) between 1 and 200
  ),
  response_body jsonb not null,
  response_status integer not null check (response_status between 100 and 599),
  created_at timestamptz not null default now(),
  unique (provider, provider_event_id)
);

create index merchant_order_provider_events_order_idx
  on private.merchant_order_provider_events (order_id, created_at desc);

create table private.merchant_order_ledger_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references private.merchant_orders(id),
  kind text not null check (
    kind in ('payment_capture', 'refund_reserve', 'refund_complete', 'order_settlement')
  ),
  source_event_id text not null check (
    char_length(source_event_id) between 1 and 200
  ),
  created_at timestamptz not null default now(),
  unique (id, order_id),
  unique (order_id, kind)
);

create index merchant_order_ledger_transactions_order_idx
  on private.merchant_order_ledger_transactions (order_id, created_at);

create table private.merchant_order_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null,
  order_id uuid not null,
  account_code text not null check (
    account_code in (
      'provider_clearing',
      'customer_funds_held',
      'refund_payable',
      'merchant_payable',
      'courier_payable',
      'platform_merchant_commission',
      'platform_delivery_margin'
    )
  ),
  side text not null check (side in ('debit', 'credit')),
  amount_paise bigint not null check (amount_paise > 0),
  created_at timestamptz not null default now(),
  foreign key (transaction_id, order_id)
    references private.merchant_order_ledger_transactions(id, order_id),
  unique (transaction_id, account_code, side)
);

create index merchant_order_ledger_entries_order_idx
  on private.merchant_order_ledger_entries (order_id, created_at);

alter table private.merchant_order_payment_records enable row level security;
alter table private.merchant_order_provider_events enable row level security;
alter table private.merchant_order_ledger_transactions enable row level security;
alter table private.merchant_order_ledger_entries enable row level security;

revoke all on table private.merchant_order_payment_records
  from public, anon, authenticated;
revoke all on table private.merchant_order_provider_events
  from public, anon, authenticated;
revoke all on table private.merchant_order_ledger_transactions
  from public, anon, authenticated;
revoke all on table private.merchant_order_ledger_entries
  from public, anon, authenticated;

grant select, insert, update on table private.merchant_order_payment_records
  to service_role;
grant select, insert on table private.merchant_order_provider_events
  to service_role;
grant select, insert on table private.merchant_order_ledger_transactions
  to service_role;
grant select, insert on table private.merchant_order_ledger_entries
  to service_role;

create function private.snapshot_merchant_order_quote_financial_terms()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_rate private.merchant_order_rate_cards%rowtype;
begin
  select rate.*
  into v_rate
  from private.merchant_order_rate_cards as rate
  where rate.id = new.rate_card_id
    and rate.version = new.rate_card_version
    and rate.delivery_fee_paise = new.delivery_fee_paise
  for share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'merchant_order_financial_terms_unavailable';
  end if;

  new.merchant_commission_bps := v_rate.merchant_commission_bps;
  new.courier_payout_paise := v_rate.courier_payout_paise;
  return new;
end;
$$;

create trigger merchant_order_quote_financial_terms
before insert on private.merchant_order_quotes
for each row execute function private.snapshot_merchant_order_quote_financial_terms();

create function private.snapshot_merchant_order_financial_terms()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_quote private.merchant_order_quotes%rowtype;
begin
  select quote.*
  into v_quote
  from private.merchant_order_quotes as quote
  where quote.id = new.quote_id
    and quote.item_subtotal_paise = new.item_subtotal_paise
    and quote.delivery_fee_paise = new.delivery_fee_paise
    and quote.total_paise = new.total_paise
  for share;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'merchant_order_financial_terms_unavailable';
  end if;

  new.merchant_commission_bps := v_quote.merchant_commission_bps;
  new.merchant_commission_paise :=
    (new.item_subtotal_paise * v_quote.merchant_commission_bps) / 10000;
  new.merchant_payable_paise :=
    new.item_subtotal_paise - new.merchant_commission_paise;
  new.courier_payout_paise := v_quote.courier_payout_paise;
  new.platform_delivery_margin_paise :=
    new.delivery_fee_paise - v_quote.courier_payout_paise;
  return new;
end;
$$;

create trigger merchant_order_financial_terms
before insert on private.merchant_orders
for each row execute function private.snapshot_merchant_order_financial_terms();

create function private.reject_merchant_order_ledger_mutation()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'merchant_order_ledger_immutable';
end;
$$;

create trigger merchant_order_ledger_transactions_immutable
before update or delete on private.merchant_order_ledger_transactions
for each row execute function private.reject_merchant_order_ledger_mutation();

create trigger merchant_order_ledger_entries_immutable
before update or delete on private.merchant_order_ledger_entries
for each row execute function private.reject_merchant_order_ledger_mutation();

create function private.reject_merchant_order_provider_event_mutation()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'merchant_order_provider_event_immutable';
end;
$$;

create trigger merchant_order_provider_events_immutable
before update or delete on private.merchant_order_provider_events
for each row execute function private.reject_merchant_order_provider_event_mutation();

create function private.assert_merchant_order_transaction_balanced(
  p_transaction_id uuid
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_debits bigint;
  v_credits bigint;
begin
  select
    coalesce(sum(entry.amount_paise) filter (where entry.side = 'debit'), 0),
    coalesce(sum(entry.amount_paise) filter (where entry.side = 'credit'), 0)
  into v_debits, v_credits
  from private.merchant_order_ledger_entries as entry
  where entry.transaction_id = p_transaction_id;

  if v_debits <= 0 or v_debits <> v_credits then
    raise exception using
      errcode = '23514',
      message = 'merchant_order_ledger_unbalanced';
  end if;
end;
$$;

create function private.post_merchant_order_capture(
  order_row private.merchant_orders,
  p_source_event_id text
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_transaction_id uuid;
begin
  insert into private.merchant_order_ledger_transactions (
    order_id, kind, source_event_id
  ) values (
    (order_row).id, 'payment_capture', p_source_event_id
  )
  on conflict (order_id, kind) do nothing
  returning id into v_transaction_id;

  if v_transaction_id is null then
    return;
  end if;

  insert into private.merchant_order_ledger_entries (
    transaction_id, order_id, account_code, side, amount_paise
  ) values
  (
    v_transaction_id, (order_row).id,
    'provider_clearing', 'debit', (order_row).total_paise
  ),
  (
    v_transaction_id, (order_row).id,
    'customer_funds_held', 'credit', (order_row).total_paise
  );

  perform private.assert_merchant_order_transaction_balanced(v_transaction_id);
end;
$$;

create function private.post_merchant_order_refund_reserve(
  p_order_id uuid,
  p_amount_paise bigint,
  p_source_event_id text
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_transaction_id uuid;
begin
  insert into private.merchant_order_ledger_transactions (
    order_id, kind, source_event_id
  ) values (
    p_order_id, 'refund_reserve', p_source_event_id
  )
  on conflict (order_id, kind) do nothing
  returning id into v_transaction_id;

  if v_transaction_id is null then
    return;
  end if;

  insert into private.merchant_order_ledger_entries (
    transaction_id, order_id, account_code, side, amount_paise
  ) values
  (
    v_transaction_id, p_order_id,
    'customer_funds_held', 'debit', p_amount_paise
  ),
  (
    v_transaction_id, p_order_id,
    'refund_payable', 'credit', p_amount_paise
  );

  perform private.assert_merchant_order_transaction_balanced(v_transaction_id);
end;
$$;

create function private.post_merchant_order_refund_complete(
  p_order_id uuid,
  p_amount_paise bigint,
  p_source_event_id text
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_transaction_id uuid;
begin
  insert into private.merchant_order_ledger_transactions (
    order_id, kind, source_event_id
  ) values (
    p_order_id, 'refund_complete', p_source_event_id
  )
  on conflict (order_id, kind) do nothing
  returning id into v_transaction_id;

  if v_transaction_id is null then
    return;
  end if;

  insert into private.merchant_order_ledger_entries (
    transaction_id, order_id, account_code, side, amount_paise
  ) values
  (
    v_transaction_id, p_order_id,
    'refund_payable', 'debit', p_amount_paise
  ),
  (
    v_transaction_id, p_order_id,
    'provider_clearing', 'credit', p_amount_paise
  );

  perform private.assert_merchant_order_transaction_balanced(v_transaction_id);
end;
$$;

create function private.post_merchant_order_settlement(
  order_row private.merchant_orders,
  p_source_event_id text
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_transaction_id uuid;
begin
  insert into private.merchant_order_ledger_transactions (
    order_id, kind, source_event_id
  ) values (
    (order_row).id, 'order_settlement', p_source_event_id
  )
  on conflict (order_id, kind) do nothing
  returning id into v_transaction_id;

  if v_transaction_id is null then
    return;
  end if;

  insert into private.merchant_order_ledger_entries (
    transaction_id, order_id, account_code, side, amount_paise
  ) values (
    v_transaction_id,
    (order_row).id,
    'customer_funds_held',
    'debit',
    (order_row).total_paise
  );

  insert into private.merchant_order_ledger_entries (
    transaction_id, order_id, account_code, side, amount_paise
  )
  select v_transaction_id, (order_row).id, allocation.account_code,
    'credit', allocation.amount_paise
  from (
    values
      ('merchant_payable'::text, (order_row).merchant_payable_paise),
      ('courier_payable'::text, (order_row).courier_payout_paise::bigint),
      ('platform_merchant_commission'::text, (order_row).merchant_commission_paise),
      ('platform_delivery_margin'::text, (order_row).platform_delivery_margin_paise::bigint)
  ) as allocation(account_code, amount_paise)
  where allocation.amount_paise > 0;

  perform private.assert_merchant_order_transaction_balanced(v_transaction_id);
end;
$$;

create function private.initialize_merchant_order_payment_record()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  insert into private.merchant_order_payment_records (
    order_id, state, settlement_state, expected_amount_paise,
    captured_amount_paise, refund_reserved_paise, refunded_paise,
    provider, provider_payment_reference, captured_at, refunded_at,
    settled_at
  ) values (
    new.id,
    case new.payment_state
      when 'payment_pending' then 'pending'
      when 'not_collected' then 'cancelled'
      when 'paid' then 'captured'
      when 'refund_pending' then 'refund_pending'
      when 'refunded' then 'refunded'
    end,
    case
      when new.status = 'delivered' and new.payment_state = 'paid'
        then 'settled'
      else 'unallocated'
    end,
    new.total_paise,
    case
      when new.payment_state in ('paid', 'refund_pending', 'refunded')
        then new.total_paise
      else 0
    end,
    case
      when new.payment_state in ('refund_pending', 'refunded')
        then new.total_paise
      else 0
    end,
    case when new.payment_state = 'refunded' then new.total_paise else 0 end,
    case when new.provider_payment_reference is null then null else 'foundation' end,
    new.provider_payment_reference,
    case
      when new.payment_state in ('paid', 'refund_pending', 'refunded')
        then pg_catalog.now()
      else null
    end,
    case when new.payment_state = 'refunded' then pg_catalog.now() end,
    case
      when new.status = 'delivered' and new.payment_state = 'paid'
        then coalesce(new.delivered_at, pg_catalog.now())
      else null
    end
  );

  if new.payment_state in ('paid', 'refund_pending', 'refunded') then
    perform private.post_merchant_order_capture(
      new,
      'order-insert:' || new.id::text || ':payment_capture'
    );
  end if;

  if new.payment_state in ('refund_pending', 'refunded') then
    perform private.post_merchant_order_refund_reserve(
      new.id,
      new.total_paise,
      'order-insert:' || new.id::text || ':refund_reserve'
    );
  end if;

  if new.payment_state = 'refunded' then
    perform private.post_merchant_order_refund_complete(
      new.id,
      new.total_paise,
      'order-insert:' || new.id::text || ':refund_complete'
    );
  end if;

  if new.status = 'delivered' and new.payment_state = 'paid' then
    perform private.post_merchant_order_settlement(
      new,
      'order-insert:' || new.id::text || ':order_settlement'
    );
  end if;

  return new;
end;
$$;

create trigger merchant_order_payment_record_created
after insert on private.merchant_orders
for each row execute function private.initialize_merchant_order_payment_record();

insert into private.merchant_order_payment_records (
  order_id, state, settlement_state, expected_amount_paise,
  captured_amount_paise, refund_reserved_paise, refunded_paise,
  provider, provider_payment_reference, captured_at, refunded_at,
  settled_at
)
select
  merchant_order.id,
  case merchant_order.payment_state
    when 'payment_pending' then 'pending'
    when 'not_collected' then 'cancelled'
    when 'paid' then 'captured'
    when 'refund_pending' then 'refund_pending'
    when 'refunded' then 'refunded'
  end,
  case
    when merchant_order.status = 'delivered'
      and merchant_order.payment_state = 'paid'
      then 'settled'
    else 'unallocated'
  end,
  merchant_order.total_paise,
  case
    when merchant_order.payment_state in ('paid', 'refund_pending', 'refunded')
      then merchant_order.total_paise
    else 0
  end,
  case
    when merchant_order.payment_state in ('refund_pending', 'refunded')
      then merchant_order.total_paise
    else 0
  end,
  case
    when merchant_order.payment_state = 'refunded'
      then merchant_order.total_paise
    else 0
  end,
  case when merchant_order.provider_payment_reference is null then null else 'foundation' end,
  merchant_order.provider_payment_reference,
  case
    when merchant_order.payment_state in ('paid', 'refund_pending', 'refunded')
      then merchant_order.updated_at
    else null
  end,
  case when merchant_order.payment_state = 'refunded' then merchant_order.updated_at end,
  case
    when merchant_order.status = 'delivered'
      and merchant_order.payment_state = 'paid'
      then merchant_order.delivered_at
    else null
  end
from private.merchant_orders as merchant_order;

do $$
declare
  v_order private.merchant_orders%rowtype;
  v_payment private.merchant_order_payment_records%rowtype;
begin
  for v_order in
    select merchant_order.*
    from private.merchant_orders as merchant_order
    where merchant_order.payment_state in ('paid', 'refund_pending', 'refunded')
  loop
    perform private.post_merchant_order_capture(v_order, 'migration:payment_capture');

    select payment.*
    into v_payment
    from private.merchant_order_payment_records as payment
    where payment.order_id = v_order.id;

    if v_payment.refund_reserved_paise > 0 then
      perform private.post_merchant_order_refund_reserve(
        v_order.id,
        v_payment.refund_reserved_paise,
        'migration:refund_reserve'
      );
    end if;

    if v_payment.refunded_paise > 0 then
      perform private.post_merchant_order_refund_complete(
        v_order.id,
        v_payment.refunded_paise,
        'migration:refund_complete'
      );
    end if;

    if v_payment.settlement_state = 'settled' then
      perform private.post_merchant_order_settlement(
        v_order,
        'migration:order_settlement'
      );
    end if;
  end loop;
end;
$$;

create function private.sync_merchant_order_financial_state()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_payment private.merchant_order_payment_records%rowtype;
begin
  select payment.*
  into v_payment
  from private.merchant_order_payment_records as payment
  where payment.order_id = new.id
  for update;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'merchant_order_payment_record_missing';
  end if;

  if old.payment_state is distinct from new.payment_state then
    case new.payment_state
      when 'paid' then
        if v_payment.state <> 'pending'
          or v_payment.expected_amount_paise <> new.total_paise
        then
          raise exception using
            errcode = '23514',
            message = 'merchant_order_payment_capture_invalid';
        end if;

        update private.merchant_order_payment_records as payment
        set state = 'captured',
            captured_amount_paise = payment.expected_amount_paise,
            provider = coalesce(payment.provider, 'foundation'),
            provider_payment_reference = coalesce(
              payment.provider_payment_reference,
              new.provider_payment_reference
            ),
            captured_at = coalesce(payment.captured_at, pg_catalog.now()),
            version = payment.version + 1,
            updated_at = pg_catalog.now()
        where payment.order_id = new.id;

        perform private.post_merchant_order_capture(
          new,
          'order-state:' || new.id::text || ':payment_capture'
        );
      when 'not_collected' then
        if v_payment.state <> 'pending' then
          raise exception using
            errcode = '23514',
            message = 'merchant_order_payment_cancellation_invalid';
        end if;

        update private.merchant_order_payment_records as payment
        set state = 'cancelled',
            version = payment.version + 1,
            updated_at = pg_catalog.now()
        where payment.order_id = new.id;
      when 'refunded' then
        if v_payment.state <> 'refund_pending'
          or v_payment.refund_reserved_paise <= 0
        then
          raise exception using
            errcode = '23514',
            message = 'merchant_order_refund_completion_invalid';
        end if;

        update private.merchant_order_payment_records as payment
        set state = 'refunded',
            refunded_paise = payment.refund_reserved_paise,
            refunded_at = coalesce(payment.refunded_at, pg_catalog.now()),
            version = payment.version + 1,
            updated_at = pg_catalog.now()
        where payment.order_id = new.id;

        perform private.post_merchant_order_refund_complete(
          new.id,
          v_payment.refund_reserved_paise,
          'order-state:' || new.id::text || ':refund_complete'
        );
      else
        null;
    end case;
  end if;

  if old.status is distinct from new.status and new.status = 'delivered' then
    select payment.*
    into v_payment
    from private.merchant_order_payment_records as payment
    where payment.order_id = new.id
    for update;

    if new.payment_state <> 'paid'
      or v_payment.state <> 'captured'
      or v_payment.settlement_state <> 'unallocated'
      or v_payment.refund_reserved_paise <> 0
    then
      raise exception using
        errcode = '23514',
        message = 'merchant_order_settlement_invalid';
    end if;

    update private.merchant_order_payment_records as payment
    set settlement_state = 'settled',
        settled_at = coalesce(new.delivered_at, pg_catalog.now()),
        version = payment.version + 1,
        updated_at = pg_catalog.now()
    where payment.order_id = new.id;

    perform private.post_merchant_order_settlement(
      new,
      'order-state:' || new.id::text || ':order_settlement'
    );
  end if;

  return new;
end;
$$;

create trigger merchant_order_financial_state_synced
after update of payment_state, status on private.merchant_orders
for each row
when (
  old.payment_state is distinct from new.payment_state
  or old.status is distinct from new.status
)
execute function private.sync_merchant_order_financial_state();

create function private.reserve_merchant_order_refund()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_amount_paise bigint;
  v_payment private.merchant_order_payment_records%rowtype;
begin
  if new.decision_status <> 'eligible'
    or new.item_refund_paise is null
    or new.delivery_fee_refund_paise is null
  then
    return new;
  end if;

  v_amount_paise := new.item_refund_paise + new.delivery_fee_refund_paise;
  if v_amount_paise <= 0 then
    return new;
  end if;

  select payment.*
  into v_payment
  from private.merchant_order_payment_records as payment
  where payment.order_id = new.order_id
  for update;

  if v_payment.state <> 'captured'
    or v_payment.settlement_state <> 'unallocated'
    or v_amount_paise > v_payment.captured_amount_paise
  then
    if v_payment.state = 'refund_pending'
      and v_payment.refund_reserved_paise = v_amount_paise
    then
      return new;
    end if;

    raise exception using
      errcode = '23514',
      message = 'merchant_order_refund_reservation_invalid';
  end if;

  update private.merchant_order_payment_records as payment
  set state = 'refund_pending',
      refund_reserved_paise = v_amount_paise,
      version = payment.version + 1,
      updated_at = pg_catalog.now()
  where payment.order_id = new.order_id;

  perform private.post_merchant_order_refund_reserve(
    new.order_id,
    v_amount_paise,
    'refund-decision:' || new.id::text
  );

  return new;
end;
$$;

create trigger merchant_order_refund_reserved
after insert on private.merchant_order_refund_decisions
for each row execute function private.reserve_merchant_order_refund();

create function private.merchant_order_financial_rate_card_json(
  rate_row private.merchant_order_rate_cards
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'serviceZoneId', (rate_row).service_zone_id,
    'deliveryFee', pg_catalog.jsonb_build_object(
      'paise', (rate_row).delivery_fee_paise
    ),
    'merchantCommissionBps', (rate_row).merchant_commission_bps,
    'courierPayout', pg_catalog.jsonb_build_object(
      'paise', (rate_row).courier_payout_paise
    ),
    'active', (rate_row).active,
    'version', (rate_row).version
  );
$$;

create function private.merchant_order_financial_json(
  order_row private.merchant_orders
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'orderId', (order_row).id,
    'paymentState', payment.state,
    'settlementState', payment.settlement_state,
    'currency', payment.currency,
    'gross', pg_catalog.jsonb_build_object(
      'paise', payment.expected_amount_paise
    ),
    'captured', pg_catalog.jsonb_build_object(
      'paise', payment.captured_amount_paise
    ),
    'refundReserved', pg_catalog.jsonb_build_object(
      'paise', payment.refund_reserved_paise
    ),
    'refunded', pg_catalog.jsonb_build_object(
      'paise', payment.refunded_paise
    ),
    'merchantPayable', pg_catalog.jsonb_build_object(
      'paise', (order_row).merchant_payable_paise
    ),
    'courierPayout', pg_catalog.jsonb_build_object(
      'paise', (order_row).courier_payout_paise
    ),
    'platformMerchantCommission', pg_catalog.jsonb_build_object(
      'paise', (order_row).merchant_commission_paise
    ),
    'platformDeliveryMargin', pg_catalog.jsonb_build_object(
      'paise', (order_row).platform_delivery_margin_paise
    ),
    'version', payment.version,
    'updatedAt', payment.updated_at
  )
  from private.merchant_order_payment_records as payment
  where payment.order_id = (order_row).id;
$$;

revoke execute on function private.snapshot_merchant_order_quote_financial_terms()
  from public, anon, authenticated;
revoke execute on function private.snapshot_merchant_order_financial_terms()
  from public, anon, authenticated;
revoke execute on function private.reject_merchant_order_ledger_mutation()
  from public, anon, authenticated;
revoke execute on function private.reject_merchant_order_provider_event_mutation()
  from public, anon, authenticated;
revoke execute on function private.assert_merchant_order_transaction_balanced(uuid)
  from public, anon, authenticated;
revoke execute on function private.post_merchant_order_capture(
  private.merchant_orders, text
) from public, anon, authenticated;
revoke execute on function private.post_merchant_order_refund_reserve(
  uuid, bigint, text
) from public, anon, authenticated;
revoke execute on function private.post_merchant_order_refund_complete(
  uuid, bigint, text
) from public, anon, authenticated;
revoke execute on function private.post_merchant_order_settlement(
  private.merchant_orders, text
) from public, anon, authenticated;
revoke execute on function private.initialize_merchant_order_payment_record()
  from public, anon, authenticated;
revoke execute on function private.sync_merchant_order_financial_state()
  from public, anon, authenticated;
revoke execute on function private.reserve_merchant_order_refund()
  from public, anon, authenticated;
revoke execute on function private.merchant_order_financial_rate_card_json(
  private.merchant_order_rate_cards
) from public, anon, authenticated;
revoke execute on function private.merchant_order_financial_json(
  private.merchant_orders
) from public, anon, authenticated;

grant execute on function private.snapshot_merchant_order_quote_financial_terms()
  to service_role;
grant execute on function private.snapshot_merchant_order_financial_terms()
  to service_role;
grant execute on function private.reject_merchant_order_ledger_mutation()
  to service_role;
grant execute on function private.reject_merchant_order_provider_event_mutation()
  to service_role;
grant execute on function private.assert_merchant_order_transaction_balanced(uuid)
  to service_role;
grant execute on function private.post_merchant_order_capture(
  private.merchant_orders, text
) to service_role;
grant execute on function private.post_merchant_order_refund_reserve(
  uuid, bigint, text
) to service_role;
grant execute on function private.post_merchant_order_refund_complete(
  uuid, bigint, text
) to service_role;
grant execute on function private.post_merchant_order_settlement(
  private.merchant_orders, text
) to service_role;
grant execute on function private.initialize_merchant_order_payment_record()
  to service_role;
grant execute on function private.sync_merchant_order_financial_state()
  to service_role;
grant execute on function private.reserve_merchant_order_refund()
  to service_role;
grant execute on function private.merchant_order_financial_rate_card_json(
  private.merchant_order_rate_cards
) to service_role;
grant execute on function private.merchant_order_financial_json(
  private.merchant_orders
) to service_role;

create function public.upsert_merchant_order_financial_rate_card(
  p_account_id uuid,
  p_service_zone_id uuid,
  p_delivery_fee_paise integer,
  p_merchant_commission_bps integer,
  p_courier_payout_paise integer,
  p_active boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_merchant_order_financial_rate_card';
  v_existing_dedup private.request_deduplication%rowtype;
  v_rate private.merchant_order_rate_cards%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_changed boolean := false;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    )
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak owner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_service_zone_id is null
    or p_delivery_fee_paise is null
    or p_delivery_fee_paise not between 0 and 100000000
    or p_merchant_commission_bps is null
    or p_merchant_commission_bps not between 0 and 10000
    or p_courier_payout_paise is null
    or p_courier_payout_paise not between 0 and p_delivery_fee_paise
    or p_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The merchant-order financial rate card is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );

  select dedup.*
  into v_existing_dedup
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing_dedup.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing_dedup.response_body;
      response_status := v_existing_dedup.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The idempotency key was already used with a different request.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  perform 1
  from public.service_zones as zone
  where zone.id = p_service_zone_id and zone.active = true
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'An active Dastak service zone is required.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_service_zone_id::text || ':merchant_order_rate', 0)
  );

  select rate.*
  into v_rate
  from private.merchant_order_rate_cards as rate
  where rate.service_zone_id = p_service_zone_id
  for update;

  if found then
    v_before_state := private.merchant_order_financial_rate_card_json(v_rate);
    if v_rate.delivery_fee_paise <> p_delivery_fee_paise
      or v_rate.merchant_commission_bps <> p_merchant_commission_bps
      or v_rate.courier_payout_paise <> p_courier_payout_paise
      or v_rate.active <> p_active
    then
      update private.merchant_order_rate_cards as rate
      set delivery_fee_paise = p_delivery_fee_paise,
          merchant_commission_bps = p_merchant_commission_bps,
          courier_payout_paise = p_courier_payout_paise,
          active = p_active,
          version = rate.version + 1,
          updated_at = pg_catalog.now()
      where rate.id = v_rate.id
      returning rate.* into v_rate;
      v_changed := true;
    end if;
  else
    insert into private.merchant_order_rate_cards (
      service_zone_id, delivery_fee_paise, merchant_commission_bps,
      courier_payout_paise, active
    ) values (
      p_service_zone_id, p_delivery_fee_paise, p_merchant_commission_bps,
      p_courier_payout_paise, p_active
    )
    returning * into v_rate;
    v_changed := true;
  end if;

  v_response_body := private.merchant_order_financial_rate_card_json(v_rate);

  if v_changed then
    insert into audit.events (
      actor_id, action, entity_type, entity_id, before_state, after_state
    ) values (
      p_account_id,
      'merchant_order_financial_rate_card_upserted',
      'merchant_order_rate_card',
      v_rate.id,
      v_before_state,
      v_response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id,
    v_function_name,
    pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest),
    v_response_body,
    200
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

create function public.get_owner_merchant_order_financial_snapshot(
  p_account_id uuid,
  p_order_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_order private.merchant_orders%rowtype;
begin
  perform 1
  from private.account_memberships as membership
  where membership.account_id = p_account_id
    and membership.role = 'owner'
    and membership.approved_at is not null
    and (
      membership.suspended_until is null
      or membership.suspended_until <= pg_catalog.now()
    );

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active Dastak owner account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  response_body := private.merchant_order_financial_json(v_order);
  response_status := 200;
  return next;
end;
$$;

create function public.record_merchant_order_payment_event(
  p_order_id uuid,
  p_provider text,
  p_provider_event_id text,
  p_event_type text,
  p_provider_order_reference text,
  p_provider_payment_reference text,
  p_amount_paise bigint,
  p_occurred_at timestamptz,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_provider text := pg_catalog.lower(pg_catalog.btrim(p_provider));
  v_provider_event_id text := pg_catalog.btrim(p_provider_event_id);
  v_event_type text := pg_catalog.btrim(p_event_type);
  v_existing_event private.merchant_order_provider_events%rowtype;
  v_order private.merchant_orders%rowtype;
  v_payment private.merchant_order_payment_records%rowtype;
  v_before_state jsonb;
  v_response_body jsonb;
  v_audit_action text;
begin
  if p_order_id is null
    or v_provider is null
    or v_provider !~ '^[a-z0-9][a-z0-9_-]{0,39}$'
    or nullif(v_provider_event_id, '') is null
    or pg_catalog.char_length(v_provider_event_id) > 200
    or v_event_type is null
    or v_event_type not in ('payment_captured', 'refund_succeeded')
    or p_amount_paise is null or p_amount_paise <= 0
    or p_occurred_at is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_request_digest)) > 200
    or (
      v_event_type = 'payment_captured'
      and (
        nullif(pg_catalog.btrim(p_provider_order_reference), '') is null
        or nullif(pg_catalog.btrim(p_provider_payment_reference), '') is null
      )
    )
    or pg_catalog.char_length(coalesce(pg_catalog.btrim(p_provider_order_reference), '')) > 200
    or pg_catalog.char_length(coalesce(pg_catalog.btrim(p_provider_payment_reference), '')) > 200
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The provider payment event is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_provider || ':' || v_provider_event_id, 0)
  );

  select provider_event.*
  into v_existing_event
  from private.merchant_order_provider_events as provider_event
  where provider_event.provider = v_provider
    and provider_event.provider_event_id = v_provider_event_id;

  if found then
    if v_existing_event.order_id = p_order_id
      and v_existing_event.request_digest = pg_catalog.btrim(p_request_digest)
    then
      response_body := v_existing_event.response_body;
      response_status := v_existing_event.response_status;
      return next;
      return;
    end if;

    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'idempotency_conflict',
        'message', 'The provider event identifier was already used.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_order_id::text || ':merchant_order_payment', 0)
  );

  select merchant_order.*
  into v_order
  from private.merchant_orders as merchant_order
  where merchant_order.id = p_order_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The merchant order was not found.'
      )
    );
    response_status := 404;
    return next;
    return;
  end if;

  select payment.*
  into v_payment
  from private.merchant_order_payment_records as payment
  where payment.order_id = v_order.id
  for update;

  v_before_state := private.merchant_order_financial_json(v_order);

  if v_event_type = 'payment_captured' then
    if v_order.status <> 'payment_pending'
      or v_order.payment_state <> 'payment_pending'
      or v_payment.state <> 'pending'
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'invalid_order_transition',
          'message', 'This order cannot accept a payment capture now.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    if p_amount_paise <> v_order.total_paise then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'payment_amount_mismatch',
          'message', 'The captured payment does not match the server order total.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    if exists (
      select 1
      from private.merchant_orders as other_order
      where other_order.provider_payment_reference =
        pg_catalog.btrim(p_provider_payment_reference)
        and other_order.id <> v_order.id
    ) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'provider_reference_conflict',
          'message', 'The provider payment reference is already in use.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    update private.merchant_order_payment_records as payment
    set provider = v_provider,
        provider_order_reference = pg_catalog.btrim(p_provider_order_reference),
        provider_payment_reference = pg_catalog.btrim(p_provider_payment_reference),
        updated_at = pg_catalog.now()
    where payment.order_id = v_order.id;

    update private.merchant_orders as merchant_order
    set status = 'paid',
        payment_state = 'paid',
        provider_payment_reference = pg_catalog.btrim(p_provider_payment_reference),
        state_version = merchant_order.state_version + 1,
        updated_at = pg_catalog.now()
    where merchant_order.id = v_order.id
    returning merchant_order.* into v_order;

    v_audit_action := 'merchant_order_payment_captured';
  else
    if v_order.payment_state <> 'refund_pending'
      or v_payment.state <> 'refund_pending'
      or v_payment.refund_reserved_paise <> p_amount_paise
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'refund_amount_mismatch',
          'message', 'The provider refund does not match the reserved refund.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    update private.merchant_orders as merchant_order
    set payment_state = 'refunded',
        state_version = merchant_order.state_version + 1,
        updated_at = pg_catalog.now()
    where merchant_order.id = v_order.id
    returning merchant_order.* into v_order;

    v_audit_action := 'merchant_order_refund_completed';
  end if;

  v_response_body := private.merchant_order_financial_json(v_order);

  insert into private.merchant_order_provider_events (
    order_id, provider, provider_event_id, event_type,
    provider_order_reference, provider_payment_reference,
    amount_paise, occurred_at, request_digest,
    response_body, response_status
  ) values (
    v_order.id,
    v_provider,
    v_provider_event_id,
    v_event_type,
    nullif(pg_catalog.btrim(p_provider_order_reference), ''),
    nullif(pg_catalog.btrim(p_provider_payment_reference), ''),
    p_amount_paise,
    p_occurred_at,
    pg_catalog.btrim(p_request_digest),
    v_response_body,
    200
  );

  insert into audit.events (
    action, entity_type, entity_id, before_state, after_state
  ) values (
    v_audit_action,
    'merchant_order_payment',
    v_order.id,
    v_before_state,
    v_response_body
  );

  response_body := v_response_body;
  response_status := 200;
  return next;
end;
$$;

revoke execute on function public.upsert_merchant_order_financial_rate_card(
  uuid, uuid, integer, integer, integer, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.upsert_merchant_order_financial_rate_card(
  uuid, uuid, integer, integer, integer, boolean, text, text
) to service_role;

revoke execute on function public.get_owner_merchant_order_financial_snapshot(
  uuid, uuid
) from public, anon, authenticated;
grant execute on function public.get_owner_merchant_order_financial_snapshot(
  uuid, uuid
) to service_role;

revoke execute on function public.record_merchant_order_payment_event(
  uuid, text, text, text, text, text, bigint, timestamp with time zone, text
) from public, anon, authenticated;
grant execute on function public.record_merchant_order_payment_event(
  uuid, text, text, text, text, text, bigint, timestamp with time zone, text
) to service_role;
