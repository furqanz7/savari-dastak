-- COALESCE and NULLIF are SQL expressions, not ordinary pg_catalog functions.
-- Schema-qualifying them made the Admin invalidation trigger fail whenever a
-- watched row changed, which also blocked otherwise unrelated writes.

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
      'operationalSafety', 'royaltyPayouts', 'network', 'catalogue'
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

create or replace function private.broadcast_admin_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_entity_id uuid;
begin
  if tg_op = 'DELETE' then
    v_row := pg_catalog.to_jsonb(old);
  else
    v_row := pg_catalog.to_jsonb(new);
  end if;

  v_entity_id := coalesce(
    nullif(v_row ->> 'id', '')::uuid,
    nullif(v_row ->> 'account_id', '')::uuid,
    nullif(v_row ->> 'order_id', '')::uuid
  );

  perform private.send_admin_change(tg_argv, v_entity_id);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.send_admin_change(text[], uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.broadcast_admin_change()
  from public, anon, authenticated, service_role;
