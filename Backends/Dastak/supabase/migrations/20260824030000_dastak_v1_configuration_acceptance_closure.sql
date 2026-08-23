-- Dastak V1 Batch D: close operational configuration and acceptance gaps.
-- Business-owned values deliberately have no defaults. Production must set them
-- explicitly; absence is a SYSTEM_CONFIGURATION_ERROR, never unavailability.

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values
  (
    'merchant.reachability_stale_seconds', 'DURATION_SECONDS',
    'Maximum age of a merchant branch heartbeat before new work is withheld.',
    null, '{"minimum":30,"maximum":86400}'::jsonb, true, true
  ),
  (
    'delivery.customer_unreachable_policy', 'JSON',
    'Operations-owned wait and contact policy snapshotted when a customer is unreachable.',
    null, '{}'::jsonb, true, true
  ),
  (
    'observability.alert_thresholds', 'JSON',
    'Launch operational backlog and escalation alert thresholds.',
    null, '{}'::jsonb, true, true
  ),
  (
    'settlement.payout_cadence', 'JSON',
    'Business-owned bank payout cadence policy snapshotted when payout is recorded.',
    null, '{}'::jsonb, true, true
  );

update dastak_v1.setting_definitions
set default_value = null,
    requires_explicit_value = true,
    updated_at = pg_catalog.now()
where setting_key = 'observability.outbox_stale_seconds';

create function dastak_v1_api.customer_unreachable_policy()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_policy jsonb := dastak_v1_api.effective_setting_json(
    'delivery.customer_unreachable_policy'
  );
  v_wait numeric;
  v_attempts numeric;
begin
  if v_policy is null
    or pg_catalog.jsonb_typeof(v_policy) <> 'object'
    or v_policy -> 'waitSeconds' is null
    or pg_catalog.jsonb_typeof(v_policy -> 'waitSeconds') <> 'number'
    or v_policy -> 'minimumContactAttempts' is null
    or pg_catalog.jsonb_typeof(v_policy -> 'minimumContactAttempts') <> 'number'
    or v_policy -> 'contactChannels' is null
    or pg_catalog.jsonb_typeof(v_policy -> 'contactChannels') <> 'array'
    or pg_catalog.jsonb_array_length(v_policy -> 'contactChannels') < 1 then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'delivery.customer_unreachable_policy must define waitSeconds, minimumContactAttempts and contactChannels.';
  end if;
  v_wait := (v_policy ->> 'waitSeconds')::numeric;
  v_attempts := (v_policy ->> 'minimumContactAttempts')::numeric;
  if v_wait < 0 or v_wait <> pg_catalog.trunc(v_wait)
    or v_attempts < 1 or v_attempts <> pg_catalog.trunc(v_attempts)
    or exists (
      select 1 from pg_catalog.jsonb_array_elements(v_policy -> 'contactChannels') channel
      where pg_catalog.jsonb_typeof(channel) <> 'string'
        or pg_catalog.char_length(pg_catalog.btrim(channel #>> '{}')) < 1
    ) then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'delivery.customer_unreachable_policy contains invalid wait/contact values.';
  end if;
  return v_policy;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'delivery.customer_unreachable_policy contains invalid numeric values.';
end;
$$;

create function dastak_v1_api.operational_alert_thresholds()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_thresholds jsonb := dastak_v1_api.effective_setting_json(
    'observability.alert_thresholds'
  );
  v_key text;
  v_value numeric;
begin
  if v_thresholds is null
    or pg_catalog.jsonb_typeof(v_thresholds) <> 'object' then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'observability.alert_thresholds must be an object.';
  end if;
  foreach v_key in array array[
    'outboxPendingCount', 'notificationPendingCount',
    'paymentReconciliationOpenCount', 'riderEscalationOpenCount',
    'merchantUnreachableBranchCount', 'customerUnreachableDueCount'
  ] loop
    if v_thresholds -> v_key is null
      or pg_catalog.jsonb_typeof(v_thresholds -> v_key) <> 'number' then
      raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
        detail = 'observability.alert_thresholds is missing a required numeric threshold.';
    end if;
    v_value := (v_thresholds ->> v_key)::numeric;
    if v_value < 0 or v_value <> pg_catalog.trunc(v_value) then
      raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
        detail = 'observability.alert_thresholds values must be non-negative integers.';
    end if;
  end loop;
  return v_thresholds;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'observability.alert_thresholds contains invalid numeric values.';
end;
$$;

create function dastak_v1_api.payout_cadence_policy()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_policy jsonb := dastak_v1_api.effective_setting_json('settlement.payout_cadence');
begin
  if v_policy is null
    or pg_catalog.jsonb_typeof(v_policy) <> 'object'
    or v_policy -> 'mode' is null
    or pg_catalog.jsonb_typeof(v_policy -> 'mode') <> 'string'
    or pg_catalog.char_length(pg_catalog.btrim(v_policy ->> 'mode')) < 1 then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'settlement.payout_cadence must define a non-empty mode.';
  end if;
  return v_policy;
end;
$$;

create table dastak_v1.merchant_branch_reachability (
  branch_id uuid primary key references dastak_v1.merchant_branches(id),
  last_seen_at timestamptz not null,
  reported_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0)
);

create index merchant_branch_reachability_seen_idx
  on dastak_v1.merchant_branch_reachability (last_seen_at, branch_id);
create index merchant_branch_reachability_actor_idx
  on dastak_v1.merchant_branch_reachability (reported_by, last_seen_at desc);

create function dastak_v1.guard_merchant_branch_reachability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.branch_id is distinct from old.branch_id
    or new.created_at is distinct from old.created_at then
    raise exception 'merchant reachability identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'merchant reachability version must increment exactly once';
  end if;
  if new.last_seen_at < old.last_seen_at then
    raise exception 'merchant heartbeat cannot move backwards';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create trigger merchant_branch_reachability_guard
before update on dastak_v1.merchant_branch_reachability
for each row execute function dastak_v1.guard_merchant_branch_reachability();
create trigger merchant_branch_reachability_no_delete
before delete on dastak_v1.merchant_branch_reachability
for each row execute function dastak_v1.reject_delete();

alter table dastak_v1.merchant_branch_reachability enable row level security;
revoke all on table dastak_v1.merchant_branch_reachability from public, anon, authenticated;
grant select, insert, update on table dastak_v1.merchant_branch_reachability to service_role;

create function dastak_v1.record_branch_state_heartbeat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into dastak_v1.merchant_branch_reachability (
    branch_id, last_seen_at, reported_by
  ) values (
    new.branch_id, pg_catalog.clock_timestamp(), new.updated_by
  ) on conflict (branch_id) do update
  set last_seen_at = greatest(
        dastak_v1.merchant_branch_reachability.last_seen_at,
        excluded.last_seen_at
      ),
      reported_by = excluded.reported_by,
      version = dastak_v1.merchant_branch_reachability.version + 1;
  return new;
end;
$$;

create trigger branch_operational_state_records_heartbeat
after insert or update on dastak_v1.branch_operational_states
for each row execute function dastak_v1.record_branch_state_heartbeat();

create function dastak_v1_api.branch_reachability_stale_seconds(p_branch_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch dastak_v1.merchant_branches%rowtype;
  v_value jsonb;
  v_seconds numeric;
begin
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch where branch.id = p_branch_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'merchant branch not found';
  end if;
  v_value := dastak_v1_api.effective_setting_json(
    'merchant.reachability_stale_seconds',
    v_branch.id, v_branch.organization_id, v_branch.service_zone_id
  );
  if v_value is null or pg_catalog.jsonb_typeof(v_value) <> 'number' then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'merchant.reachability_stale_seconds is required.';
  end if;
  v_seconds := (v_value #>> '{}')::numeric;
  if v_seconds < 30 or v_seconds > 86400
    or v_seconds <> pg_catalog.trunc(v_seconds) then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'merchant.reachability_stale_seconds is invalid.';
  end if;
  return v_seconds::integer;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '55000', message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'merchant.reachability_stale_seconds is invalid.';
end;
$$;

create function dastak_v1_api.branch_is_reachable(
  p_branch_id uuid,
  p_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from dastak_v1.merchant_branch_reachability reachability
    where reachability.branch_id = p_branch_id
      and reachability.last_seen_at >= p_at - pg_catalog.make_interval(
        secs => dastak_v1_api.branch_reachability_stale_seconds(p_branch_id)
      )
  );
$$;

create function dastak_v1_api.branch_reachability_json(
  p_branch_id uuid,
  p_at timestamptz default pg_catalog.statement_timestamp()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'reachable', dastak_v1_api.branch_is_reachable(p_branch_id, p_at),
    'lastSeenAt', reachability.last_seen_at,
    'staleAfterSeconds', dastak_v1_api.branch_reachability_stale_seconds(p_branch_id),
    'observedAt', p_at
  )
  from (select 1) singleton
  left join dastak_v1.merchant_branch_reachability reachability
    on reachability.branch_id = p_branch_id;
$$;

create function dastak_v1_api.record_actor_merchant_heartbeats(
  p_actor_id uuid,
  p_at timestamptz default pg_catalog.clock_timestamp()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  with permitted as (
    select branch.id
    from dastak_v1.merchant_branches branch
    where branch.status = 'ACTIVE'
      and (
        dastak_v1_api.actor_has_wave1_merchant_permission(
          p_actor_id, branch.organization_id, 'merchant.opportunities.respond', branch.id
        )
        or dastak_v1_api.actor_has_wave1_merchant_permission(
          p_actor_id, branch.organization_id, 'merchant.fulfilment.manage', branch.id
        )
        or dastak_v1_api.actor_has_wave1_merchant_permission(
          p_actor_id, branch.organization_id, 'merchant.branch.manage', branch.id
        )
      )
  ), upserted as (
    insert into dastak_v1.merchant_branch_reachability (
      branch_id, last_seen_at, reported_by
    )
    select permitted.id, p_at, p_actor_id from permitted
    on conflict (branch_id) do update
    set last_seen_at = greatest(
          dastak_v1.merchant_branch_reachability.last_seen_at,
          excluded.last_seen_at
        ),
        reported_by = excluded.reported_by,
        version = dastak_v1.merchant_branch_reachability.version + 1
    returning branch_id
  )
  select count(*) into v_count from upserted;
  return v_count;
end;
$$;

alter function public.dastak_v1_list_merchant_opportunities(integer)
  rename to dastak_v1_list_merchant_opportunities_pre_reachability;

create function public.dastak_v1_list_merchant_opportunities(
  p_limit integer default 50
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform dastak_v1_api.record_actor_merchant_heartbeats(
    auth.uid(), pg_catalog.clock_timestamp()
  );
  return public.dastak_v1_list_merchant_opportunities_pre_reachability(p_limit);
end;
$$;

create function dastak_v1.enforce_opportunity_branch_reachability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if not dastak_v1_api.branch_is_reachable(
      new.branch_id, pg_catalog.clock_timestamp()
    ) then
      return null;
    end if;
  elsif old.status is distinct from 'SELECTED' and new.status = 'SELECTED'
    and not dastak_v1_api.branch_is_reachable(
      new.branch_id, pg_catalog.clock_timestamp()
    ) then
    raise exception using errcode = '55000', message = 'MERCHANT_BRANCH_UNREACHABLE';
  end if;
  return new;
end;
$$;

create trigger aa_merchant_opportunities_reachability
before insert or update on dastak_v1.merchant_opportunities
for each row execute function dastak_v1.enforce_opportunity_branch_reachability();

create function dastak_v1.enforce_restaurant_request_reachability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and not dastak_v1_api.branch_is_reachable(
    new.branch_id, pg_catalog.clock_timestamp()
  ) then
    raise exception using errcode = '55000', message = 'RESTAURANT_BRANCH_UNREACHABLE';
  end if;
  if tg_op = 'UPDATE'
    and old.status is distinct from 'CONFIRMED' and new.status = 'CONFIRMED'
    and not dastak_v1_api.branch_is_reachable(
      new.branch_id, pg_catalog.clock_timestamp()
    ) then
    raise exception using errcode = '55000', message = 'RESTAURANT_BRANCH_UNREACHABLE';
  end if;
  return new;
end;
$$;

create trigger aa_restaurant_requests_reachability
before insert or update on dastak_v1.restaurant_order_requests
for each row execute function dastak_v1.enforce_restaurant_request_reachability();

create or replace function dastak_v1_api.list_customer_restaurants(
  p_actor_id uuid,
  p_query text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform dastak_v1_api.assert_customer_actor(p_actor_id);
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'invalid restaurant limit';
  end if;
  return pg_catalog.jsonb_build_object(
    'restaurants', coalesce((
      select pg_catalog.jsonb_agg(
        dastak_v1_api.restaurant_menu_json(visible.id, false)
        order by visible.display_name, visible.id
      )
      from (
        select branch.id, organization.display_name
        from dastak_v1.merchant_branches branch
        join dastak_v1.merchant_organizations organization
          on organization.id = branch.organization_id
        join dastak_v1.branch_operational_states operating
          on operating.branch_id = branch.id
        join public.service_zones zone
          on zone.id = branch.service_zone_id and zone.active
        where organization.merchant_type = 'RESTAURANT_CAFE'
          and organization.status = 'ACTIVE'
          and branch.status = 'ACTIVE'
          and operating.is_open and operating.accepting_orders
          and dastak_v1_api.branch_is_reachable(
            branch.id, pg_catalog.statement_timestamp()
          )
          and (
            p_query is null
            or organization.display_name ilike '%' || p_query || '%'
            or branch.display_name ilike '%' || p_query || '%'
            or exists (
              select 1 from dastak_v1.restaurant_menu_items item
              where item.branch_id = branch.id and item.status = 'ACTIVE'
                and item.name ilike '%' || p_query || '%'
            )
          )
          and not exists (
            select 1 from dastak_v1.operational_pause_controls control
            where control.active and (
              (control.scope = 'MERCHANT_BRANCH' and control.branch_id = branch.id)
              or (control.scope = 'ZONE_FOOD' and control.service_zone_id = branch.service_zone_id)
            )
          )
          and exists (
            select 1 from dastak_v1.restaurant_menu_items item
            join dastak_v1.restaurant_menu_categories category
              on category.id = item.category_id and category.status = 'ACTIVE'
            where item.branch_id = branch.id and item.status = 'ACTIVE'
          )
        order by organization.display_name, branch.id
        limit p_limit
      ) visible
    ), '[]'::jsonb)
  );
end;
$$;

alter table dastak_v1.delivery_problem_reports
  add column problem_code text not null default 'OTHER' check (
    problem_code in ('OTHER', 'CUSTOMER_UNREACHABLE')
  ),
  add column operational_policy_snapshot jsonb check (
    operational_policy_snapshot is null
    or pg_catalog.jsonb_typeof(operational_policy_snapshot) = 'object'
  ),
  add column next_action_at timestamptz,
  add constraint delivery_problem_customer_unreachable_policy_check check (
    (problem_code = 'OTHER' and operational_policy_snapshot is null and next_action_at is null)
    or (problem_code = 'CUSTOMER_UNREACHABLE'
      and operational_policy_snapshot is not null and next_action_at is not null)
  );

alter table dastak_v1.recovery_cases
  add column delivery_problem_code text check (
    delivery_problem_code is null
    or delivery_problem_code in ('OTHER', 'CUSTOMER_UNREACHABLE')
  ),
  add column operational_policy_snapshot jsonb check (
    operational_policy_snapshot is null
    or pg_catalog.jsonb_typeof(operational_policy_snapshot) = 'object'
  ),
  add column next_action_at timestamptz;

create index recovery_cases_next_action_idx
  on dastak_v1.recovery_cases (next_action_at, status)
  where next_action_at is not null;

create function dastak_v1.apply_delivery_problem_policy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := nullif(
    pg_catalog.current_setting('dastak_v1.delivery_problem_code', true), ''
  );
  v_policy_text text := nullif(
    pg_catalog.current_setting('dastak_v1.delivery_problem_policy', true), ''
  );
  v_policy jsonb;
begin
  if v_code = 'CUSTOMER_UNREACHABLE' then
    if new.mission_status_at_report not in ('OUT_FOR_DELIVERY', 'ARRIVED') then
      raise exception using errcode = '55000',
        message = 'CUSTOMER_UNREACHABLE_NOT_ALLOWED';
    end if;
    v_policy := v_policy_text::jsonb;
    new.problem_code := v_code;
    new.operational_policy_snapshot := v_policy;
    new.next_action_at := new.reported_at + pg_catalog.make_interval(
      secs => (v_policy ->> 'waitSeconds')::integer
    );
  end if;
  return new;
end;
$$;

create trigger aa_delivery_problem_policy
before insert on dastak_v1.delivery_problem_reports
for each row execute function dastak_v1.apply_delivery_problem_policy();

create or replace function dastak_v1.open_delivery_recovery_case()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem dastak_v1.delivery_problem_reports%rowtype;
  v_case_id uuid;
begin
  if old.status is distinct from 'DELIVERY_RECOVERY'
    and new.status = 'DELIVERY_RECOVERY' then
    select problem.* into v_problem
    from dastak_v1.delivery_problem_reports problem
    where problem.mission_id = new.id
    order by problem.reported_at desc, problem.id desc limit 1;
    insert into dastak_v1.recovery_cases (
      case_type, order_id, delivery_mission_id, status,
      fault_source, reason, opened_by, opened_at,
      delivery_problem_code, operational_policy_snapshot, next_action_at
    ) values (
      'DELIVERY', new.order_id, new.id, 'ACTION_REQUIRED',
      'UNKNOWN', coalesce(v_problem.reason, 'Delivery recovery requires Operations.'),
      coalesce(v_problem.reported_by, new.assigned_rider_id),
      coalesce(v_problem.reported_at, pg_catalog.clock_timestamp()),
      coalesce(v_problem.problem_code, 'OTHER'),
      v_problem.operational_policy_snapshot, v_problem.next_action_at
    ) on conflict do nothing returning id into v_case_id;
    if v_case_id is not null then
      insert into dastak_v1.domain_events_outbox (
        event_key, aggregate_type, aggregate_id, aggregate_version,
        event_type, actor_id, payload
      ) values (
        v_case_id::text || ':DELIVERY_RECOVERY_STARTED:1',
        'RECOVERY_CASE', v_case_id, 1, 'DELIVERY_RECOVERY_STARTED',
        coalesce(v_problem.reported_by, new.assigned_rider_id),
        pg_catalog.jsonb_build_object(
          'orderId', new.order_id, 'missionId', new.id,
          'recoveryCaseId', v_case_id, 'custodyRetainedByRider', true,
          'problemCode', coalesce(v_problem.problem_code, 'OTHER'),
          'nextActionAt', v_problem.next_action_at
        )
      );
    end if;
  end if;
  return new;
end;
$$;

alter function public.dastak_v1_advance_delivery_mission(
  uuid, uuid, text, uuid, integer, text, text, text, text
) rename to dastak_v1_advance_delivery_mission_pre_acceptance_closure;

create function public.dastak_v1_advance_delivery_mission(
  p_account_id uuid,
  p_mission_id uuid,
  p_action text,
  p_stop_id uuid,
  p_accounted_package_count integer,
  p_verification_code text,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_action text := p_action;
  v_policy jsonb;
begin
  perform pg_catalog.set_config('dastak_v1.delivery_problem_code', '', true);
  perform pg_catalog.set_config('dastak_v1.delivery_problem_policy', '', true);
  if p_action = 'REPORT_CUSTOMER_UNREACHABLE' then
    v_policy := dastak_v1_api.customer_unreachable_policy();
    perform pg_catalog.set_config(
      'dastak_v1.delivery_problem_code', 'CUSTOMER_UNREACHABLE', true
    );
    perform pg_catalog.set_config(
      'dastak_v1.delivery_problem_policy', v_policy::text, true
    );
    v_action := 'REPORT_DELIVERY_PROBLEM';
  end if;
  return query
  select result.response_body, result.response_status
  from public.dastak_v1_advance_delivery_mission_pre_acceptance_closure(
    p_account_id, p_mission_id, v_action, p_stop_id,
    p_accounted_package_count, p_verification_code, p_reason,
    p_idempotency_key, p_request_digest
  ) result;
end;
$$;

alter table dastak_v1.settlement_entries
  add column payout_cadence_snapshot jsonb check (
    payout_cadence_snapshot is null
    or pg_catalog.jsonb_typeof(payout_cadence_snapshot) = 'object'
  );

create or replace function dastak_v1.guard_settlement_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.entry_key is distinct from old.entry_key
    or new.subject_type is distinct from old.subject_type
    or new.subject_id is distinct from old.subject_id
    or new.order_id is distinct from old.order_id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.delivery_mission_id is distinct from old.delivery_mission_id
    or new.order_line_id is distinct from old.order_line_id
    or new.refund_id is distinct from old.refund_id
    or new.entry_type is distinct from old.entry_type
    or new.gross_amount_paise is distinct from old.gross_amount_paise
    or new.currency_code is distinct from old.currency_code
    or new.created_at is distinct from old.created_at then
    raise exception 'settlement ledger identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'settlement entry version must increment exactly once';
  end if;
  if old.calculation_status = 'CALCULATED' and (
    new.calculation_status is distinct from old.calculation_status
    or new.amount_paise is distinct from old.amount_paise
    or new.calculation_snapshot is distinct from old.calculation_snapshot
  ) then
    raise exception 'calculated settlement amount cannot be rewritten';
  end if;
  if old.calculation_status = 'SYSTEM_CONFIGURATION_REQUIRED'
    and new.calculation_status = 'CALCULATED'
    and old.status <> 'PENDING' then
    raise exception 'only pending settlement can finish calculation';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'PENDING' and new.status = 'ELIGIBLE')
    or (old.status = 'ELIGIBLE' and new.status = 'SETTLED')
  ) then
    raise exception 'invalid settlement transition: % -> %', old.status, new.status;
  end if;
  if old.status = 'ELIGIBLE' and new.status = 'SETTLED' then
    new.payout_cadence_snapshot := dastak_v1_api.payout_cadence_policy();
  elsif new.payout_cadence_snapshot is distinct from old.payout_cadence_snapshot then
    raise exception 'settlement payout cadence snapshot cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

alter function dastak_v1_api.system_health_snapshot(uuid)
  rename to system_health_snapshot_pre_operational_alerts;

create function dastak_v1_api.system_health_snapshot(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_thresholds jsonb;
  v_outbox_pending integer;
  v_notification_pending integer;
  v_payment_open integer;
  v_rider_escalations integer;
  v_merchant_unreachable integer;
  v_customer_unreachable_due integer;
  v_breached boolean;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  perform dastak_v1_api.required_setting_integer('observability.outbox_stale_seconds');
  v_thresholds := dastak_v1_api.operational_alert_thresholds();
  v_base := dastak_v1_api.system_health_snapshot_pre_operational_alerts(p_actor_id);
  v_outbox_pending := (v_base #>> '{outbox,pending}')::integer;
  v_notification_pending := (v_base #>> '{notifications,pending}')::integer;
  v_payment_open := (v_base ->> 'paymentReconciliationOpen')::integer;
  select count(*) into v_rider_escalations
  from dastak_v1.delivery_missions mission
  where mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
    and mission.escalation_state in ('STALLED', 'UNRESPONSIVE', 'DELIVERY_RECOVERY');
  select count(*) into v_merchant_unreachable
  from dastak_v1.merchant_branches branch
  join dastak_v1.branch_operational_states operating on operating.branch_id = branch.id
  where branch.status = 'ACTIVE' and operating.is_open and operating.accepting_orders
    and not dastak_v1_api.branch_is_reachable(branch.id, v_now);
  select count(*) into v_customer_unreachable_due
  from dastak_v1.recovery_cases recovery
  where recovery.case_type = 'DELIVERY'
    and recovery.delivery_problem_code = 'CUSTOMER_UNREACHABLE'
    and recovery.status = 'ACTION_REQUIRED'
    and recovery.next_action_at <= v_now;
  v_breached :=
    v_outbox_pending > (v_thresholds ->> 'outboxPendingCount')::integer
    or v_notification_pending > (v_thresholds ->> 'notificationPendingCount')::integer
    or v_payment_open > (v_thresholds ->> 'paymentReconciliationOpenCount')::integer
    or v_rider_escalations > (v_thresholds ->> 'riderEscalationOpenCount')::integer
    or v_merchant_unreachable > (v_thresholds ->> 'merchantUnreachableBranchCount')::integer
    or v_customer_unreachable_due > (v_thresholds ->> 'customerUnreachableDueCount')::integer;
  return v_base || pg_catalog.jsonb_build_object(
    'healthy', coalesce((v_base ->> 'healthy')::boolean, false) and not v_breached,
    'operationalAlerts', pg_catalog.jsonb_build_object(
      'breached', v_breached,
      'thresholds', v_thresholds,
      'counts', pg_catalog.jsonb_build_object(
        'outboxPendingCount', v_outbox_pending,
        'notificationPendingCount', v_notification_pending,
        'paymentReconciliationOpenCount', v_payment_open,
        'riderEscalationOpenCount', v_rider_escalations,
        'merchantUnreachableBranchCount', v_merchant_unreachable,
        'customerUnreachableDueCount', v_customer_unreachable_due
      )
    )
  );
end;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_pre_acceptance_closure;

create function dastak_v1_api.admin_execution_trace(
  p_actor_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trace jsonb;
begin
  v_trace := dastak_v1_api.admin_execution_trace_pre_acceptance_closure(
    p_actor_id, p_order_id
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace,
    '{failureAndFinance,recoveryCases}',
    coalesce((
      select pg_catalog.jsonb_agg(
        case_value || pg_catalog.jsonb_build_object(
          'problemCode', recovery.delivery_problem_code,
          'operationalPolicySnapshot', recovery.operational_policy_snapshot,
          'nextActionAt', recovery.next_action_at
        ) order by case_value ->> 'openedAt', case_value ->> 'id'
      )
      from pg_catalog.jsonb_array_elements(
        coalesce(v_trace #> '{failureAndFinance,recoveryCases}', '[]'::jsonb)
      ) case_value
      left join dastak_v1.recovery_cases recovery
        on recovery.id = (case_value ->> 'id')::uuid
    ), '[]'::jsonb),
    true
  );
  v_trace := pg_catalog.jsonb_set(
    v_trace,
    '{failureAndFinance,settlements}',
    coalesce((
      select pg_catalog.jsonb_agg(
        entry_value || pg_catalog.jsonb_build_object(
          'payoutCadenceSnapshot', entry.payout_cadence_snapshot
        ) order by entry_value ->> 'id'
      )
      from pg_catalog.jsonb_array_elements(
        coalesce(v_trace #> '{failureAndFinance,settlements}', '[]'::jsonb)
      ) entry_value
      left join dastak_v1.settlement_entries entry
        on entry.id = (entry_value ->> 'id')::uuid
    ), '[]'::jsonb),
    true
  );
  return v_trace;
end;
$$;

revoke all on function dastak_v1_api.customer_unreachable_policy() from public, anon, authenticated;
revoke all on function dastak_v1_api.operational_alert_thresholds() from public, anon, authenticated;
revoke all on function dastak_v1_api.payout_cadence_policy() from public, anon, authenticated;
revoke all on function dastak_v1_api.branch_reachability_stale_seconds(uuid) from public, anon, authenticated;
revoke all on function dastak_v1_api.branch_is_reachable(uuid, timestamptz) from public, anon, authenticated;
revoke all on function dastak_v1_api.branch_reachability_json(uuid, timestamptz) from public, anon, authenticated;
revoke all on function dastak_v1_api.record_actor_merchant_heartbeats(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.dastak_v1_list_merchant_opportunities_pre_reachability(integer) from public, anon, authenticated;
revoke all on function public.dastak_v1_list_merchant_opportunities(integer) from public, anon;
revoke all on function public.dastak_v1_advance_delivery_mission_pre_acceptance_closure(uuid, uuid, text, uuid, integer, text, text, text, text) from public, anon, authenticated;
revoke all on function public.dastak_v1_advance_delivery_mission(uuid, uuid, text, uuid, integer, text, text, text, text) from public, anon;
revoke all on function dastak_v1_api.system_health_snapshot_pre_operational_alerts(uuid) from public, anon, authenticated;
revoke all on function dastak_v1_api.system_health_snapshot(uuid) from public, anon, authenticated;
revoke all on function dastak_v1_api.admin_execution_trace_pre_acceptance_closure(uuid, uuid) from public, anon, authenticated;
revoke all on function dastak_v1_api.admin_execution_trace(uuid, uuid) from public, anon, authenticated;

grant execute on function dastak_v1_api.customer_unreachable_policy() to service_role;
grant execute on function dastak_v1_api.operational_alert_thresholds() to service_role;
grant execute on function dastak_v1_api.payout_cadence_policy() to service_role;
grant execute on function dastak_v1_api.branch_reachability_stale_seconds(uuid) to service_role;
grant execute on function dastak_v1_api.branch_is_reachable(uuid, timestamptz) to service_role;
grant execute on function dastak_v1_api.branch_reachability_json(uuid, timestamptz) to service_role;
grant execute on function dastak_v1_api.record_actor_merchant_heartbeats(uuid, timestamptz) to authenticated, service_role;
grant execute on function public.dastak_v1_list_merchant_opportunities_pre_reachability(integer) to authenticated, service_role;
grant execute on function public.dastak_v1_list_merchant_opportunities(integer) to authenticated, service_role;
grant execute on function public.dastak_v1_advance_delivery_mission_pre_acceptance_closure(uuid, uuid, text, uuid, integer, text, text, text, text) to authenticated, service_role;
grant execute on function public.dastak_v1_advance_delivery_mission(uuid, uuid, text, uuid, integer, text, text, text, text) to authenticated, service_role;
grant execute on function dastak_v1_api.system_health_snapshot_pre_operational_alerts(uuid) to service_role;
grant execute on function dastak_v1_api.system_health_snapshot(uuid) to service_role;
grant execute on function dastak_v1_api.admin_execution_trace_pre_acceptance_closure(uuid, uuid) to service_role;
grant execute on function dastak_v1_api.admin_execution_trace(uuid, uuid) to service_role;

comment on function dastak_v1_api.branch_is_reachable(uuid, timestamptz) is
  'Authoritative branch staleness gate. Missing configuration raises SYSTEM_CONFIGURATION_ERROR.';
comment on column dastak_v1.settlement_entries.payout_cadence_snapshot is
  'Immutable business payout-cadence policy captured when an eligible entry is settled.';
