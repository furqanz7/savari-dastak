-- Production rehearsal hotfix: a branch may select many canonical SKUs whose
-- independent selection streams each begin at version 1. The outbox aggregate
-- must therefore be the branch/SKU selection, not the branch alone.

create or replace function dastak_v1_api.update_merchant_sku_selection(
  p_actor_id uuid,
  p_branch_id uuid,
  p_sku_id uuid,
  p_selected boolean,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'updateMerchantSkuSelection';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_sku dastak_v1.skus%rowtype;
  v_selection dastak_v1.merchant_sku_selections%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_branch_id is null or p_sku_id is null or p_selected is null
    or p_expected_version is null or p_expected_version < 0
    or p_idempotency_key is null
    or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid selection command required';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'branchId', p_branch_id,
    'skuId', p_sku_id,
    'selected', p_selected,
    'expectedVersion', p_expected_version
  ));

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key),
      0
    )
  );

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_request_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  -- Stable lock order: branch, SKU, then selection.
  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'branch not found'; end if;

  select organization.* into strict v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;
  if v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    raise exception using errcode = '22023', message = 'canonical SKU selection is retail-only';
  end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_branch.organization_id,
    'merchant.catalogue.selection.manage', v_branch.id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  select sku.* into v_sku
  from dastak_v1.skus sku where sku.id = p_sku_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'canonical SKU not found'; end if;
  if p_selected and v_sku.status <> 'ACTIVE' then
    raise exception using errcode = '22023', message = 'inactive canonical SKU cannot be selected';
  end if;

  select selection.* into v_selection
  from dastak_v1.merchant_sku_selections selection
  where selection.branch_id = p_branch_id and selection.sku_id = p_sku_id
  for update;

  if found then
    if v_selection.version is distinct from p_expected_version then
      raise exception using errcode = '40001', message = 'stale merchant SKU selection version';
    end if;
    update dastak_v1.merchant_sku_selections
    set state = (
          case when p_selected then 'SELECTED' else 'UNAVAILABLE' end
        )::dastak_v1.merchant_sku_state,
        selected_by = p_actor_id,
        updated_at = pg_catalog.now(),
        version = version + 1
    where branch_id = p_branch_id and sku_id = p_sku_id
    returning * into v_selection;
  else
    if p_expected_version <> 0 then
      raise exception using errcode = '40001', message = 'new merchant SKU selection expectedVersion must be 0';
    end if;
    insert into dastak_v1.merchant_sku_selections (
      branch_id, sku_id, state, selected_by
    ) values (
      p_branch_id, p_sku_id,
      (
        case when p_selected then 'SELECTED' else 'UNAVAILABLE' end
      )::dastak_v1.merchant_sku_state,
      p_actor_id
    ) returning * into v_selection;
  end if;

  v_response := pg_catalog.jsonb_build_object(
    'branchId', v_selection.branch_id,
    'skuId', v_selection.sku_id,
    'selected', v_selection.state = 'SELECTED',
    'state', v_selection.state,
    'version', v_selection.version,
    'updatedAt', v_selection.updated_at
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'MERCHANT_CANONICAL_SKU_SELECTION_CHANGED',
    'merchant_branch', p_branch_id,
    v_response || pg_catalog.jsonb_build_object('idempotencyKey', p_idempotency_key)
  );

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    p_branch_id::text || ':MERCHANT_CANONICAL_SKU_SELECTION_CHANGED:' ||
      p_sku_id::text || ':' || v_selection.version::text,
    'MERCHANT_SKU_SELECTION', p_sku_id, v_selection.version,
    'MERCHANT_CANONICAL_SKU_SELECTION_CHANGED', p_actor_id, v_response
  );

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_request_hash,
    v_response, 200, p_branch_id
  );

  return v_response;
end;
$$;

comment on function dastak_v1_api.update_merchant_sku_selection(
  uuid, uuid, uuid, boolean, bigint, text
) is
  'Changes one branch/SKU selection with a per-SKU outbox aggregate identity.';
