-- Merchant catalogue picking is an editing session, not one network request per
-- tap. Commit the staged selection set in one transaction while preserving the
-- existing per-SKU version checks, audit events and outbox records.

create function dastak_v1_api.update_merchant_sku_selections(
  p_actor_id uuid,
  p_branch_id uuid,
  p_selections jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'updateMerchantSkuSelections';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_item jsonb;
  v_sku_id uuid;
  v_selected boolean;
  v_expected_version bigint;
  v_results jsonb := '[]'::jsonb;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_branch_id is null
    or p_selections is null
    or pg_catalog.jsonb_typeof(p_selections) <> 'array'
    or pg_catalog.jsonb_array_length(p_selections) not between 1 and 1000
    or p_idempotency_key is null
    or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 120 then
    raise exception using errcode = '22023', message = 'valid batch selection command required';
  end if;

  if (select pg_catalog.count(*) from pg_catalog.jsonb_array_elements(p_selections)) <>
     (select pg_catalog.count(distinct item ->> 'skuId') from pg_catalog.jsonb_array_elements(p_selections) item) then
    raise exception using errcode = '22023', message = 'batch selection contains duplicate SKUs';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'branchId', p_branch_id,
    'selections', p_selections
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

  -- Sorting gives concurrent batches a stable SKU lock order. The existing
  -- single-selection command remains the source of version, permission, audit
  -- and outbox semantics; a failure rolls back the entire batch.
  for v_item in
    select item
    from pg_catalog.jsonb_array_elements(p_selections) item
    order by item ->> 'skuId'
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object'
      or pg_catalog.jsonb_typeof(v_item -> 'selected') <> 'boolean'
      or coalesce(v_item ->> 'skuId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or coalesce(v_item ->> 'expectedVersion', '') !~ '^[0-9]+$' then
      raise exception using errcode = '22023', message = 'invalid batch selection item';
    end if;

    v_sku_id := (v_item ->> 'skuId')::uuid;
    v_selected := (v_item ->> 'selected')::boolean;
    v_expected_version := (v_item ->> 'expectedVersion')::bigint;

    v_results := v_results || pg_catalog.jsonb_build_array(
      dastak_v1_api.update_merchant_sku_selection(
        p_actor_id,
        p_branch_id,
        v_sku_id,
        v_selected,
        v_expected_version,
        pg_catalog.btrim(p_idempotency_key) || ':' || v_sku_id::text
      )
    );
  end loop;

  v_response := pg_catalog.jsonb_build_object(
    'branchId', p_branch_id,
    'updatedCount', pg_catalog.jsonb_array_length(v_results),
    'selections', v_results
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

create function public.dastak_v1_update_merchant_sku_selections(
  p_branch_id uuid,
  p_selections jsonb,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.update_merchant_sku_selections(
    auth.uid(), p_branch_id, p_selections, p_idempotency_key
  );
$$;

revoke execute on function dastak_v1_api.update_merchant_sku_selections(uuid, uuid, jsonb, text)
  from public, anon;
revoke execute on function public.dastak_v1_update_merchant_sku_selections(uuid, jsonb, text)
  from public, anon;
grant execute on function dastak_v1_api.update_merchant_sku_selections(uuid, uuid, jsonb, text)
  to authenticated;
grant execute on function public.dastak_v1_update_merchant_sku_selections(uuid, jsonb, text)
  to authenticated;

comment on function public.dastak_v1_update_merchant_sku_selections(uuid, jsonb, text) is
  'Atomically saves up to 1000 staged merchant SKU selections with per-SKU optimistic concurrency, audit and outbox records.';
