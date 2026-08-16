-- Dastak order state is owned by Postgres. Clients may request actions, but
-- cannot invent transitions or treat realtime payloads as authoritative data.

create or replace function private.is_valid_merchant_order_transition(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_from = p_to or (p_from, p_to) in (
    ('payment_pending', 'paid'),
    ('payment_pending', 'cancelled'),
    ('paid', 'merchant_accepted'),
    ('paid', 'cancelled'),
    ('merchant_accepted', 'ready'),
    ('merchant_accepted', 'cancelled'),
    ('ready', 'assigned'),
    ('ready', 'cancelled'),
    ('assigned', 'ready'), -- Recovery when an accepted assignment disappears.
    ('assigned', 'en_route_to_pickup'),
    ('assigned', 'cancelled'),
    ('en_route_to_pickup', 'at_store'),
    ('en_route_to_pickup', 'cancelled'),
    ('at_store', 'picked_up'),
    ('at_store', 'cancelled'),
    ('picked_up', 'in_transit'),
    ('picked_up', 'returning_to_merchant'),
    ('in_transit', 'delivered'),
    ('in_transit', 'returning_to_merchant'),
    ('returning_to_merchant', 'cancelled')
  );
$$;

create or replace function private.is_valid_merchant_payment_transition(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_from = p_to or (p_from, p_to) in (
    ('payment_pending', 'paid'),
    ('payment_pending', 'not_collected'),
    ('paid', 'refund_pending'),
    ('refund_pending', 'refunded')
  );
$$;

create or replace function private.is_valid_parcel_transition(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_from = p_to or (p_from, p_to) in (
    ('payment_pending', 'paid'),
    ('payment_pending', 'cancelled'),
    ('paid', 'assigned'),
    ('paid', 'cancelled'),
    ('assigned', 'paid'), -- Recovery after an expired or orphaned offer.
    ('assigned', 'en_route_to_pickup'),
    ('assigned', 'cancelled'),
    ('en_route_to_pickup', 'picked_up'),
    ('en_route_to_pickup', 'cancelled'),
    ('picked_up', 'in_transit'),
    ('in_transit', 'delivered')
  );
$$;

create or replace function private.is_valid_parcel_payment_transition(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_from = p_to or (p_from, p_to) in (
    ('pending', 'paid'),
    ('pending', 'failed'),
    ('pending', 'cancelled'),
    ('paid', 'refund_pending'),
    ('refund_pending', 'refunded')
  );
$$;

create or replace function private.is_valid_parcel_refund_transition(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_from = p_to or (p_from, p_to) in (
    ('not_requested', 'pending'),
    ('pending', 'completed')
  );
$$;

create or replace function private.is_valid_merchant_assignment_transition(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_from = p_to or (p_from, p_to) in (
    ('offered', 'accepted'),
    ('offered', 'declined'),
    ('offered', 'expired'),
    ('offered', 'cancelled'),
    ('accepted', 'completed'),
    ('accepted', 'cancelled')
  );
$$;

create or replace function private.is_valid_parcel_assignment_transition(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select p_from = p_to or (p_from, p_to) in (
    ('offered', 'acknowledged'),
    ('offered', 'declined'),
    ('offered', 'expired'),
    ('offered', 'cancelled'),
    ('acknowledged', 'completed'),
    ('acknowledged', 'cancelled')
  );
$$;

create table private.order_state_transitions (
  id bigint generated always as identity primary key,
  entity_kind text not null check (
    entity_kind in (
      'merchant_order', 'parcel', 'merchant_assignment', 'parcel_assignment'
    )
  ),
  entity_id uuid not null,
  transition_kind text not null check (
    transition_kind in ('created', 'status', 'payment', 'refund', 'state', 'assignment')
  ),
  from_status text,
  to_status text not null,
  from_payment_state text,
  to_payment_state text,
  from_state_version bigint,
  to_state_version bigint,
  is_recovery boolean not null default false,
  actor_account_id uuid,
  transaction_id bigint not null default pg_catalog.txid_current(),
  occurred_at timestamptz not null default pg_catalog.now()
);

create index order_state_transitions_entity_idx
  on private.order_state_transitions(entity_kind, entity_id, occurred_at desc, id desc);
create index order_state_transitions_recovery_idx
  on private.order_state_transitions(occurred_at desc)
  where is_recovery;

revoke all on table private.order_state_transitions from public, anon, authenticated;
grant select on table private.order_state_transitions to service_role;

create or replace function private.reject_order_state_transition_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'order state transitions are append-only';
end;
$$;

create trigger order_state_transitions_immutable
before update or delete on private.order_state_transitions
for each row execute function private.reject_order_state_transition_mutation();

create or replace function private.guard_merchant_order_state()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status
    and not private.is_valid_merchant_order_transition(old.status, new.status)
  then
    raise exception using
      errcode = '23514',
      message = 'invalid merchant order transition',
      detail = old.status || ' -> ' || new.status,
      constraint = 'merchant_order_canonical_transition';
  end if;

  if old.payment_state is distinct from new.payment_state
    and not private.is_valid_merchant_payment_transition(
      old.payment_state,
      new.payment_state
    )
  then
    raise exception using
      errcode = '23514',
      message = 'invalid merchant payment transition',
      detail = old.payment_state || ' -> ' || new.payment_state,
      constraint = 'merchant_payment_canonical_transition';
  end if;

  if new.state_version < old.state_version
    or (
      new.state_version <> old.state_version
      and new.state_version <> old.state_version + 1
    )
    or (
      (
        old.status is distinct from new.status
        or old.payment_state is distinct from new.payment_state
      )
      and new.state_version <> old.state_version + 1
    )
  then
    raise exception using
      errcode = '23514',
      message = 'invalid merchant order state version',
      detail = old.state_version::text || ' -> ' || new.state_version::text,
      constraint = 'merchant_order_state_version_sequence';
  end if;

  return new;
end;
$$;

create or replace function private.guard_parcel_state()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status
    and not private.is_valid_parcel_transition(old.status, new.status)
  then
    raise exception using
      errcode = '23514',
      message = 'invalid parcel transition',
      detail = old.status || ' -> ' || new.status,
      constraint = 'parcel_canonical_transition';
  end if;

  if old.payment_status is distinct from new.payment_status
    and not private.is_valid_parcel_payment_transition(
      old.payment_status,
      new.payment_status
    )
  then
    raise exception using
      errcode = '23514',
      message = 'invalid parcel payment transition',
      detail = old.payment_status || ' -> ' || new.payment_status,
      constraint = 'parcel_payment_canonical_transition';
  end if;

  if old.refund_status is distinct from new.refund_status
    and not private.is_valid_parcel_refund_transition(
      old.refund_status,
      new.refund_status
    )
  then
    raise exception using
      errcode = '23514',
      message = 'invalid parcel refund transition',
      detail = old.refund_status || ' -> ' || new.refund_status,
      constraint = 'parcel_refund_canonical_transition';
  end if;

  if new.state_version < old.state_version
    or (
      new.state_version <> old.state_version
      and new.state_version <> old.state_version + 1
    )
    or (
      (
        old.status is distinct from new.status
        or old.payment_status is distinct from new.payment_status
        or old.refund_status is distinct from new.refund_status
      )
      and new.state_version <> old.state_version + 1
    )
  then
    raise exception using
      errcode = '23514',
      message = 'invalid parcel state version',
      detail = old.state_version::text || ' -> ' || new.state_version::text,
      constraint = 'parcel_state_version_sequence';
  end if;

  return new;
end;
$$;

create or replace function private.guard_merchant_assignment_state()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status
    and not private.is_valid_merchant_assignment_transition(old.status, new.status)
  then
    raise exception using
      errcode = '23514',
      message = 'invalid merchant assignment transition',
      detail = old.status || ' -> ' || new.status,
      constraint = 'merchant_assignment_canonical_transition';
  end if;
  return new;
end;
$$;

create or replace function private.guard_parcel_assignment_state()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status
    and not private.is_valid_parcel_assignment_transition(old.status, new.status)
  then
    raise exception using
      errcode = '23514',
      message = 'invalid parcel assignment transition',
      detail = old.status || ' -> ' || new.status,
      constraint = 'parcel_assignment_canonical_transition';
  end if;
  return new;
end;
$$;

drop trigger if exists zz_merchant_order_state_guard on private.merchant_orders;
create trigger zz_merchant_order_state_guard
before update of status, payment_state, state_version
on private.merchant_orders
for each row execute function private.guard_merchant_order_state();

drop trigger if exists zz_parcel_state_guard on private.parcel_deliveries;
create trigger zz_parcel_state_guard
before update of status, payment_status, refund_status, state_version
on private.parcel_deliveries
for each row execute function private.guard_parcel_state();

drop trigger if exists zz_merchant_assignment_state_guard
  on private.delivery_assignment_attempts;
create trigger zz_merchant_assignment_state_guard
before update of status on private.delivery_assignment_attempts
for each row execute function private.guard_merchant_assignment_state();

drop trigger if exists zz_parcel_assignment_state_guard
  on private.parcel_assignment_attempts;
create trigger zz_parcel_assignment_state_guard
before update of status on private.parcel_assignment_attempts
for each row execute function private.guard_parcel_assignment_state();

create or replace function private.record_merchant_order_state()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if tg_op = 'INSERT' then
    v_kind := 'created';
  elsif old.status is distinct from new.status then
    v_kind := 'status';
  elsif old.payment_state is distinct from new.payment_state then
    v_kind := 'payment';
  elsif old.state_version is distinct from new.state_version then
    v_kind := 'state';
  else
    return new;
  end if;

  insert into private.order_state_transitions (
    entity_kind, entity_id, transition_kind,
    from_status, to_status, from_payment_state, to_payment_state,
    from_state_version, to_state_version, is_recovery, actor_account_id
  ) values (
    'merchant_order', new.id, v_kind,
    case when tg_op = 'UPDATE' then old.status end,
    new.status,
    case when tg_op = 'UPDATE' then old.payment_state end,
    new.payment_state,
    case when tg_op = 'UPDATE' then old.state_version end,
    new.state_version,
    (
      (tg_op = 'UPDATE' and old.status = 'assigned' and new.status = 'ready')
      or new.status = 'returning_to_merchant'
      or new.payment_state in ('refund_pending', 'refunded')
    ),
    auth.uid()
  );
  return new;
end;
$$;

create or replace function private.record_parcel_state()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if tg_op = 'INSERT' then
    v_kind := 'created';
  elsif old.status is distinct from new.status then
    v_kind := 'status';
  elsif old.payment_status is distinct from new.payment_status then
    v_kind := 'payment';
  elsif old.refund_status is distinct from new.refund_status then
    v_kind := 'refund';
  elsif old.state_version is distinct from new.state_version then
    v_kind := 'state';
  else
    return new;
  end if;

  insert into private.order_state_transitions (
    entity_kind, entity_id, transition_kind,
    from_status, to_status, from_payment_state, to_payment_state,
    from_state_version, to_state_version, is_recovery, actor_account_id
  ) values (
    'parcel', new.id, v_kind,
    case when tg_op = 'UPDATE' then old.status end,
    new.status,
    case when tg_op = 'UPDATE' then old.payment_status end,
    new.payment_status,
    case when tg_op = 'UPDATE' then old.state_version end,
    new.state_version,
    (
      (tg_op = 'UPDATE' and old.status = 'assigned' and new.status = 'paid')
      or new.payment_status in ('refund_pending', 'refunded')
    ),
    auth.uid()
  );
  return new;
end;
$$;

create or replace function private.record_assignment_state()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_entity_kind text;
begin
  if tg_op = 'UPDATE' and old.status is not distinct from new.status then
    return new;
  end if;

  v_entity_kind := case tg_table_name
    when 'delivery_assignment_attempts' then 'merchant_assignment'
    else 'parcel_assignment'
  end;

  insert into private.order_state_transitions (
    entity_kind, entity_id, transition_kind,
    from_status, to_status, is_recovery, actor_account_id
  ) values (
    v_entity_kind,
    new.id,
    case when tg_op = 'INSERT' then 'created' else 'assignment' end,
    case when tg_op = 'UPDATE' then old.status end,
    new.status,
    new.status in ('expired', 'cancelled'),
    auth.uid()
  );
  return new;
end;
$$;

drop trigger if exists zz_merchant_order_state_journal on private.merchant_orders;
create trigger zz_merchant_order_state_journal
after insert or update of status, payment_state, state_version
on private.merchant_orders
for each row execute function private.record_merchant_order_state();

drop trigger if exists zz_parcel_state_journal on private.parcel_deliveries;
create trigger zz_parcel_state_journal
after insert or update of status, payment_status, refund_status, state_version
on private.parcel_deliveries
for each row execute function private.record_parcel_state();

drop trigger if exists zz_merchant_assignment_state_journal
  on private.delivery_assignment_attempts;
create trigger zz_merchant_assignment_state_journal
after insert or update of status on private.delivery_assignment_attempts
for each row execute function private.record_assignment_state();

drop trigger if exists zz_parcel_assignment_state_journal
  on private.parcel_assignment_attempts;
create trigger zz_parcel_assignment_state_journal
after insert or update of status on private.parcel_assignment_attempts
for each row execute function private.record_assignment_state();

-- Realtime payloads are invalidation signals, not snapshots. Every recipient
-- must call an authenticated snapshot endpoint after receiving one.
create or replace function private.send_order_change(
  p_account_id uuid,
  p_entity_kind text,
  p_entity_id uuid,
  p_state_version bigint default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_account_id is null then
    return;
  end if;

  perform realtime.send(
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'entityKind', p_entity_kind,
      'entityId', p_entity_id,
      'stateVersion', p_state_version
    )),
    'order_changed',
    'order-account:' || p_account_id::text,
    true
  );
end;
$$;

create or replace function private.broadcast_merchant_order_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account_id uuid;
begin
  perform private.send_order_change(
    new.customer_account_id,
    'merchant_order',
    new.id,
    new.state_version
  );

  select store.merchant_account_id
  into v_account_id
  from private.merchant_stores as store
  where store.id = new.store_id;

  perform private.send_order_change(
    v_account_id,
    'merchant_order',
    new.id,
    new.state_version
  );

  for v_account_id in
    select distinct assignment.partner_account_id
    from private.delivery_assignment_attempts as assignment
    where assignment.order_id = new.id
      and assignment.status = 'accepted'
  loop
    perform private.send_order_change(
      v_account_id,
      'merchant_order',
      new.id,
      new.state_version
    );
  end loop;

  return new;
end;
$$;

create or replace function private.broadcast_parcel_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_account_id uuid;
begin
  perform private.send_order_change(
    new.customer_account_id,
    'parcel',
    new.id,
    new.state_version
  );
  perform private.send_order_change(
    new.recipient_account_id,
    'parcel',
    new.id,
    new.state_version
  );

  for v_account_id in
    select distinct assignment.partner_account_id
    from private.parcel_assignment_attempts as assignment
    where assignment.parcel_id = new.id
      and assignment.status in ('offered', 'acknowledged')
  loop
    perform private.send_order_change(
      v_account_id,
      'parcel',
      new.id,
      new.state_version
    );
  end loop;

  return new;
end;
$$;

create or replace function private.broadcast_assignment_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_entity_kind text;
  v_entity_id uuid;
  v_state_version bigint;
begin
  if tg_table_name = 'delivery_assignment_attempts' then
    v_entity_kind := 'merchant_order';
    v_entity_id := new.order_id;
    select merchant_order.state_version
    into v_state_version
    from private.merchant_orders as merchant_order
    where merchant_order.id = new.order_id;
  else
    v_entity_kind := 'parcel';
    v_entity_id := new.parcel_id;
    select parcel.state_version
    into v_state_version
    from private.parcel_deliveries as parcel
    where parcel.id = new.parcel_id;
  end if;

  perform private.send_order_change(
    new.partner_account_id,
    v_entity_kind,
    v_entity_id,
    v_state_version
  );
  return new;
end;
$$;

drop trigger if exists zzz_merchant_order_realtime on private.merchant_orders;
create trigger zzz_merchant_order_realtime
after insert or update of status, payment_state, state_version
on private.merchant_orders
for each row execute function private.broadcast_merchant_order_change();

drop trigger if exists zzz_parcel_realtime on private.parcel_deliveries;
create trigger zzz_parcel_realtime
after insert or update of status, payment_status, refund_status, state_version
on private.parcel_deliveries
for each row execute function private.broadcast_parcel_change();

drop trigger if exists zzz_merchant_assignment_realtime
  on private.delivery_assignment_attempts;
create trigger zzz_merchant_assignment_realtime
after insert or update of status on private.delivery_assignment_attempts
for each row execute function private.broadcast_assignment_change();

drop trigger if exists zzz_parcel_assignment_realtime
  on private.parcel_assignment_attempts;
create trigger zzz_parcel_assignment_realtime
after insert or update of status on private.parcel_assignment_attempts
for each row execute function private.broadcast_assignment_change();

drop policy if exists "dastak_account_order_events" on realtime.messages;
create policy "dastak_account_order_events"
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (select auth.uid()) is not null
  and (select realtime.topic()) = 'order-account:' || (select auth.uid())::text
);

-- Safe reconciliation repairs only impossible assignment states. Payment and
-- refund anomalies remain visible in the journal and are never guessed away.
create or replace function private.reconcile_order_lifecycle()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_merchant_recovered integer := 0;
  v_parcel_recovered integer := 0;
  v_merchant_dispatched integer := 0;
  v_parcel_dispatched integer := 0;
begin
  update private.merchant_orders as merchant_order
  set status = 'ready',
      assigned_at = null,
      state_version = merchant_order.state_version + 1,
      updated_at = pg_catalog.now()
  where merchant_order.status = 'assigned'
    and not exists (
      select 1
      from private.delivery_assignment_attempts as assignment
      where assignment.order_id = merchant_order.id
        and assignment.status = 'accepted'
    );
  get diagnostics v_merchant_recovered = row_count;

  update private.parcel_deliveries as parcel
  set status = 'paid',
      assigned_at = null,
      state_version = parcel.state_version + 1,
      updated_at = pg_catalog.now()
  where parcel.status = 'assigned'
    and parcel.payment_status = 'paid'
    and not exists (
      select 1
      from private.parcel_assignment_attempts as assignment
      where assignment.parcel_id = parcel.id
        and assignment.status in ('offered', 'acknowledged')
    );
  get diagnostics v_parcel_recovered = row_count;

  v_merchant_dispatched := private.process_courier_dispatch();
  v_parcel_dispatched := private.process_parcel_dispatch();

  return pg_catalog.jsonb_build_object(
    'merchantOrdersRecovered', v_merchant_recovered,
    'parcelsRecovered', v_parcel_recovered,
    'merchantOffersCreated', v_merchant_dispatched,
    'parcelOffersCreated', v_parcel_dispatched,
    'reconciledAt', pg_catalog.now()
  );
end;
$$;

do $$
declare
  v_job_id bigint;
begin
  select job.jobid
  into v_job_id
  from cron.job as job
  where job.jobname = 'dastak-order-lifecycle-reconciliation';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;
end;
$$;

select cron.schedule(
  'dastak-order-lifecycle-reconciliation',
  '* * * * *',
  'select private.reconcile_order_lifecycle();'
);

revoke execute on function private.is_valid_merchant_order_transition(text, text)
  from public, anon, authenticated;
revoke execute on function private.is_valid_merchant_payment_transition(text, text)
  from public, anon, authenticated;
revoke execute on function private.is_valid_parcel_transition(text, text)
  from public, anon, authenticated;
revoke execute on function private.is_valid_parcel_payment_transition(text, text)
  from public, anon, authenticated;
revoke execute on function private.is_valid_parcel_refund_transition(text, text)
  from public, anon, authenticated;
revoke execute on function private.is_valid_merchant_assignment_transition(text, text)
  from public, anon, authenticated;
revoke execute on function private.is_valid_parcel_assignment_transition(text, text)
  from public, anon, authenticated;
revoke execute on function private.guard_merchant_order_state()
  from public, anon, authenticated;
revoke execute on function private.reject_order_state_transition_mutation()
  from public, anon, authenticated;
revoke execute on function private.guard_parcel_state()
  from public, anon, authenticated;
revoke execute on function private.guard_merchant_assignment_state()
  from public, anon, authenticated;
revoke execute on function private.guard_parcel_assignment_state()
  from public, anon, authenticated;
revoke execute on function private.record_merchant_order_state()
  from public, anon, authenticated;
revoke execute on function private.record_parcel_state()
  from public, anon, authenticated;
revoke execute on function private.record_assignment_state()
  from public, anon, authenticated;
revoke execute on function private.send_order_change(uuid, text, uuid, bigint)
  from public, anon, authenticated;
revoke execute on function private.broadcast_merchant_order_change()
  from public, anon, authenticated;
revoke execute on function private.broadcast_parcel_change()
  from public, anon, authenticated;
revoke execute on function private.broadcast_assignment_change()
  from public, anon, authenticated;
revoke execute on function private.reconcile_order_lifecycle()
  from public, anon, authenticated;

grant execute on function private.reconcile_order_lifecycle() to service_role;

comment on table private.order_state_transitions is
  'Immutable canonical journal for Dastak order and assignment state changes.';
comment on function private.reconcile_order_lifecycle() is
  'Repairs orphaned assignment states and resumes automatic dispatch without changing money state.';
