-- Admin C2.1: establish narrowly-scoped launch-governance permissions and a
-- reviewed, searchable projection over both append-only audit stores.

insert into dastak_v1.permission_definitions (
  permission_key,
  description,
  sensitivity
) values
  ('platform.merchants.manage', 'Govern approved Merchant organizations and branches.', 'HIGHLY_SENSITIVE'),
  ('platform.delivery_partners.manage', 'Govern approved Delivery Partner accounts and transport eligibility.', 'HIGHLY_SENSITIVE'),
  ('platform.accounts.recover', 'Perform governed customer account and session recovery.', 'HIGHLY_SENSITIVE'),
  ('platform.audit.read', 'Read the reviewed cross-generation Admin audit history.', 'HIGHLY_SENSITIVE'),
  ('platform.catalogue.assets.manage', 'Govern canonical catalogue media and evidence assets.', 'HIGHLY_SENSITIVE')
on conflict (permission_key) do update
set description = excluded.description,
    sensitivity = excluded.sensitivity;

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
select bundle.id, permission.permission_key
from dastak_v1.permission_bundles bundle
cross join (
  values
    ('platform.merchants.manage'::text),
    ('platform.delivery_partners.manage'::text),
    ('platform.accounts.recover'::text),
    ('platform.audit.read'::text),
    ('platform.catalogue.assets.manage'::text)
) permission(permission_key)
where bundle.scope = 'PLATFORM'
  and bundle.active
  and bundle.bundle_key in ('platform_super_admin', 'executive_admin')
on conflict (bundle_id, permission_key) do nothing;

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
select bundle.id, 'platform.catalogue.assets.manage'
from dastak_v1.permission_bundles bundle
where bundle.scope = 'PLATFORM'
  and bundle.active
  and bundle.bundle_key = 'catalogue_admin'
on conflict (bundle_id, permission_key) do nothing;

create index if not exists legacy_audit_events_page_idx
  on audit.events (created_at desc, id desc);
create index if not exists legacy_audit_events_actor_page_idx
  on audit.events (actor_id, created_at desc, id desc);
create index if not exists legacy_audit_events_action_page_idx
  on audit.events (action, created_at desc, id desc);
create index if not exists legacy_audit_events_resource_page_idx
  on audit.events (entity_type, entity_id, created_at desc, id desc);
create index if not exists v1_audit_events_page_idx
  on dastak_v1.audit_events (occurred_at desc, id desc);
create index if not exists v1_audit_events_action_page_idx
  on dastak_v1.audit_events (action, occurred_at desc, id desc);

create or replace function dastak_v1_api.safe_audit_uuid(p_value text)
returns uuid
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then p_value::uuid
    else null
  end
$$;

revoke all on function dastak_v1_api.safe_audit_uuid(text)
  from public, anon, authenticated, service_role;

create or replace function dastak_v1_api.admin_audit_history_page(
  p_actor_id uuid,
  p_from_occurred_at timestamptz default null,
  p_to_occurred_at timestamptz default null,
  p_actor_query text default null,
  p_action text default null,
  p_resource_type text default null,
  p_resource_id uuid default null,
  p_order_id uuid default null,
  p_branch_id uuid default null,
  p_account_id uuid default null,
  p_event_id text default null,
  p_limit integer default 50,
  p_after_occurred_at timestamptz default null,
  p_after_event_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_query text := nullif(pg_catalog.btrim(coalesce(p_actor_query, '')), '');
  v_action text := nullif(pg_catalog.btrim(coalesce(p_action, '')), '');
  v_resource_type text := nullif(pg_catalog.btrim(coalesce(p_resource_type, '')), '');
  v_event_id text := nullif(pg_catalog.btrim(coalesce(p_event_id, '')), '');
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_events jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.audit.read');
  if dastak_v1_api.admin_role_for_actor(p_actor_id) is null then
    raise exception using
      errcode = '42501',
      message = 'active Admin assignment required';
  end if;

  if v_actor_query is not null and pg_catalog.char_length(v_actor_query) > 100 then
    raise exception using errcode = '22023', message = 'audit actor filter is too long';
  end if;
  if v_action is not null and pg_catalog.char_length(v_action) > 120 then
    raise exception using errcode = '22023', message = 'audit action filter is too long';
  end if;
  if v_resource_type is not null and pg_catalog.char_length(v_resource_type) > 120 then
    raise exception using errcode = '22023', message = 'audit resource filter is too long';
  end if;
  if v_event_id is not null and (
    pg_catalog.char_length(v_event_id) > 80
    or v_event_id !~ '^(legacy:[0-9a-fA-F-]{36}|v1:[0-9]+)$'
  ) then
    raise exception using errcode = '22023', message = 'invalid audit event identifier';
  end if;
  if p_from_occurred_at is not null and p_to_occurred_at is not null
    and p_from_occurred_at > p_to_occurred_at then
    raise exception using errcode = '22023', message = 'invalid audit time range';
  end if;
  if (p_after_occurred_at is null) <> (p_after_event_id is null) then
    raise exception using errcode = '22023', message = 'complete audit cursor required';
  end if;
  if p_after_event_id is not null and (
    pg_catalog.char_length(p_after_event_id) > 80
    or p_after_event_id !~ '^(legacy:[0-9a-fA-F-]{36}|v1:[0-9]+)$'
  ) then
    raise exception using errcode = '22023', message = 'invalid audit cursor';
  end if;

  with normalized as not materialized (
    select
      'LEGACY'::text as source,
      'legacy:' || event.id::text as event_id,
      event.created_at as occurred_at,
      event.actor_id,
      account.display_name as actor_display_name,
      pg_catalog.left(event.action, 120) as action,
      pg_catalog.left(event.entity_type, 120) as resource_type,
      event.entity_id as resource_id,
      nullif(pg_catalog.left(pg_catalog.btrim(coalesce(event.reason, '')), 500), '') as reason,
      pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'beforeStatus', pg_catalog.left(coalesce(event.before_state ->> 'status', event.before_state ->> 'state'), 160),
        'afterStatus', pg_catalog.left(coalesce(event.after_state ->> 'status', event.after_state ->> 'state'), 160),
        'beforeVersion', pg_catalog.left(event.before_state ->> 'version', 80),
        'afterVersion', pg_catalog.left(event.after_state ->> 'version', 80),
        'decision', pg_catalog.left(event.after_state ->> 'decision', 160),
        'outcome', pg_catalog.left(event.after_state ->> 'outcome', 160)
      )) as summary,
      case when event.entity_type ilike '%order%' then event.entity_id
        else dastak_v1_api.safe_audit_uuid(coalesce(event.after_state ->> 'orderId', event.after_state ->> 'order_id', event.before_state ->> 'orderId', event.before_state ->> 'order_id')) end as order_id,
      case when event.entity_type ilike '%branch%' then event.entity_id
        else dastak_v1_api.safe_audit_uuid(coalesce(event.after_state ->> 'branchId', event.after_state ->> 'branch_id', event.before_state ->> 'branchId', event.before_state ->> 'branch_id')) end as branch_id,
      case when event.entity_type ilike '%account%' then event.entity_id
        else dastak_v1_api.safe_audit_uuid(coalesce(event.after_state ->> 'accountId', event.after_state ->> 'account_id', event.before_state ->> 'accountId', event.before_state ->> 'account_id')) end as account_id
    from audit.events event
    left join public.accounts account on account.id = event.actor_id

    union all

    select
      'V1'::text,
      'v1:' || event.id::text,
      event.occurred_at,
      event.actor_id,
      account.display_name,
      pg_catalog.left(event.action, 120),
      pg_catalog.left(event.resource_type, 120),
      event.resource_id,
      nullif(pg_catalog.left(pg_catalog.btrim(coalesce(event.metadata ->> 'reason', '')), 500), ''),
      pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'fromStatus', pg_catalog.left(coalesce(event.metadata ->> 'fromStatus', event.metadata ->> 'from_status'), 160),
        'toStatus', pg_catalog.left(coalesce(event.metadata ->> 'toStatus', event.metadata ->> 'to_status'), 160),
        'status', pg_catalog.left(event.metadata ->> 'status', 160),
        'decision', pg_catalog.left(event.metadata ->> 'decision', 160),
        'outcome', pg_catalog.left(event.metadata ->> 'outcome', 160),
        'scope', pg_catalog.left(event.metadata ->> 'scope', 160),
        'version', pg_catalog.left(coalesce(event.metadata ->> 'version', event.metadata ->> 'orderVersion'), 80)
      )),
      case when event.resource_type ilike '%order%' then event.resource_id
        else dastak_v1_api.safe_audit_uuid(coalesce(event.metadata ->> 'orderId', event.metadata ->> 'order_id')) end,
      case when event.resource_type ilike '%branch%' then event.resource_id
        else dastak_v1_api.safe_audit_uuid(coalesce(event.metadata ->> 'branchId', event.metadata ->> 'branch_id')) end,
      case when event.resource_type ilike '%account%' then event.resource_id
        else dastak_v1_api.safe_audit_uuid(coalesce(event.metadata ->> 'accountId', event.metadata ->> 'account_id')) end
    from dastak_v1.audit_events event
    left join public.accounts account on account.id = event.actor_id
  ), matched as materialized (
    select *
    from normalized event
    where (p_from_occurred_at is null or event.occurred_at >= p_from_occurred_at)
      and (p_to_occurred_at is null or event.occurred_at <= p_to_occurred_at)
      and (
        v_actor_query is null
        or event.actor_id::text = v_actor_query
        or event.actor_display_name ilike '%' || v_actor_query || '%'
      )
      and (v_action is null or event.action = v_action)
      and (v_resource_type is null or event.resource_type = v_resource_type)
      and (p_resource_id is null or event.resource_id = p_resource_id)
      and (p_order_id is null or event.order_id = p_order_id)
      and (p_branch_id is null or event.branch_id = p_branch_id)
      and (p_account_id is null or event.account_id = p_account_id or event.actor_id = p_account_id)
      and (v_event_id is null or event.event_id = v_event_id)
      and (
        p_after_occurred_at is null
        or (event.occurred_at, event.event_id) < (p_after_occurred_at, p_after_event_id)
      )
    order by event.occurred_at desc, event.event_id desc
    limit v_limit + 1
  ), selected as (
    select * from matched
    order by occurred_at desc, event_id desc
    limit v_limit
  )
  select
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'source', event.source,
          'eventId', event.event_id,
          'occurredAt', event.occurred_at,
          'actor', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
            'id', event.actor_id,
            'displayName', coalesce(event.actor_display_name, case when event.actor_id is null then 'System' else 'Unknown account' end)
          )),
          'action', event.action,
          'resource', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
            'type', event.resource_type,
            'id', event.resource_id
          )),
          'reason', event.reason,
          'summary', event.summary,
          'references', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
            'orderId', event.order_id,
            'branchId', event.branch_id,
            'accountId', event.account_id
          ))
        ) order by event.occurred_at desc, event.event_id desc
      ) from selected event
    ), '[]'::jsonb),
    (select pg_catalog.count(*) > v_limit from matched),
    case when (select pg_catalog.count(*) > v_limit from matched) then (
      select pg_catalog.jsonb_build_object(
        'occurredAt', event.occurred_at,
        'eventId', event.event_id
      )
      from selected event
      order by event.occurred_at, event.event_id
      limit 1
    ) else null end
  into v_events, v_has_more, v_next_cursor;

  return pg_catalog.jsonb_build_object(
    'events', v_events,
    'hasMore', v_has_more,
    'nextCursor', v_next_cursor
  );
end;
$$;

create or replace function public.dastak_v1_admin_audit_history_page(
  p_from_occurred_at timestamptz default null,
  p_to_occurred_at timestamptz default null,
  p_actor_query text default null,
  p_action text default null,
  p_resource_type text default null,
  p_resource_id uuid default null,
  p_order_id uuid default null,
  p_branch_id uuid default null,
  p_account_id uuid default null,
  p_event_id text default null,
  p_limit integer default 50,
  p_after_occurred_at timestamptz default null,
  p_after_event_id text default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_audit_history_page(
    auth.uid(),
    p_from_occurred_at,
    p_to_occurred_at,
    p_actor_query,
    p_action,
    p_resource_type,
    p_resource_id,
    p_order_id,
    p_branch_id,
    p_account_id,
    p_event_id,
    p_limit,
    p_after_occurred_at,
    p_after_event_id
  )
$$;

revoke all on function dastak_v1_api.admin_audit_history_page(
  uuid,timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text
) from public, anon;
grant execute on function dastak_v1_api.admin_audit_history_page(
  uuid,timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text
) to authenticated, service_role;

revoke all on function public.dastak_v1_admin_audit_history_page(
  timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text
) from public, anon;
grant execute on function public.dastak_v1_admin_audit_history_page(
  timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text
) to authenticated, service_role;

comment on function public.dastak_v1_admin_audit_history_page(
  timestamptz,timestamptz,text,text,text,uuid,uuid,uuid,uuid,text,integer,timestamptz,text
) is 'Caller-bound, active-Admin audit history projection with reviewed fields and opaque keyset pagination.';

-- Add the audit workspace to the existing authenticated Admin invalidation lane.
create or replace function private.send_admin_change(
  p_workspaces text[],
  p_entity_id uuid default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspaces text[];
begin
  select pg_catalog.array_agg(candidate.workspace order by candidate.workspace)
  into v_workspaces
  from (
    select distinct workspace
    from pg_catalog.unnest(p_workspaces) workspace
    where workspace = any (array[
      'operations', 'liveOrders', 'adminAccess', 'commandCenter',
      'merchantApprovals', 'deliveryApprovals', 'systemHealth',
      'operationalSafety', 'royaltyPayouts', 'network', 'catalogue',
      'auditHistory'
    ]::text[])
  ) candidate;

  if coalesce(pg_catalog.cardinality(v_workspaces), 0) = 0 then
    return;
  end if;

  perform realtime.send(
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'workspaces', v_workspaces,
      'entityId', p_entity_id
    )),
    'admin_changed',
    'admin-control',
    true
  );
end;
$$;

revoke all on function private.send_admin_change(text[], uuid)
  from public, anon, authenticated, service_role;

create or replace function private.broadcast_admin_audit_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_row jsonb := pg_catalog.to_jsonb(new);
  v_entity_id uuid;
begin
  v_entity_id := dastak_v1_api.safe_audit_uuid(
    coalesce(v_row ->> 'resource_id', v_row ->> 'entity_id')
  );
  perform private.send_admin_change(array['auditHistory']::text[], v_entity_id);
  return new;
end;
$$;

revoke all on function private.broadcast_admin_audit_change()
  from public, anon, authenticated, service_role;

create trigger audit_history_legacy_changed
after insert on audit.events
for each row execute function private.broadcast_admin_audit_change();

create trigger audit_history_v1_changed
after insert on dastak_v1.audit_events
for each row execute function private.broadcast_admin_audit_change();
