-- Merchant-maintained stock counts. Physical order confirmation remains authoritative.
alter table dastak_v1.merchant_sku_selections
  add column stock_quantity integer check (stock_quantity between 0 and 1000000);

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
    if p_selected and v_selection.stock_quantity = 0 then
      raise exception using errcode = '22023', message = 'update stock count before selecting this product';
    end if;
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

create or replace function dastak_v1_api.update_merchant_stock_selection(
  p_actor_id uuid,
  p_branch_id uuid,
  p_sku_id uuid,
  p_selected boolean,
  p_expected_version bigint,
  p_idempotency_key text,
  p_stock_quantity integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'updateMerchantStockSelection';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_sku dastak_v1.skus%rowtype;
  v_selection dastak_v1.merchant_sku_selections%rowtype;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_stock_quantity is null or p_stock_quantity not between 0 and 1000000 or (p_selected and p_stock_quantity = 0)
    or p_branch_id is null or p_sku_id is null or p_selected is null
    or p_expected_version is null or p_expected_version < 0
    or p_idempotency_key is null
    or pg_catalog.char_length(pg_catalog.btrim(p_idempotency_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid selection command required';
  end if;

  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'branchId', p_branch_id,
    'skuId', p_sku_id,
    'selected', p_selected,
    'stockQuantity', p_stock_quantity,
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
        stock_quantity = p_stock_quantity,
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
      branch_id, sku_id, state, selected_by, stock_quantity
    ) values (
      p_branch_id, p_sku_id,
      (
        case when p_selected then 'SELECTED' else 'UNAVAILABLE' end
      )::dastak_v1.merchant_sku_state,
      p_actor_id, p_stock_quantity
    ) returning * into v_selection;
  end if;

  v_response := pg_catalog.jsonb_build_object(
    'branchId', v_selection.branch_id,
    'skuId', v_selection.sku_id,
    'selected', v_selection.state = 'SELECTED',
    'state', v_selection.state,
    'stockQuantity', v_selection.stock_quantity,
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
revoke all on function dastak_v1_api.update_merchant_stock_selection(uuid,uuid,uuid,boolean,bigint,text,integer) from public, anon;
grant execute on function dastak_v1_api.update_merchant_stock_selection(uuid,uuid,uuid,boolean,bigint,text,integer) to authenticated;

create or replace function dastak_v1_api.update_merchant_sku_selections(
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

    if v_item ? 'stockQuantity' then
      if pg_catalog.jsonb_typeof(v_item -> 'stockQuantity') is distinct from 'number'
        or (v_item ->> 'stockQuantity') !~ '^[0-9]+$'
        or (v_item ->> 'stockQuantity')::numeric > 1000000
        or (v_selected and (v_item ->> 'stockQuantity')::integer = 0) then
        raise exception using errcode = '22023', message = 'stock quantity must be a whole number from 0 to 1000000; zero stock must be unavailable';
      end if;
    end if;

    v_results := v_results || pg_catalog.jsonb_build_array(
      case when v_item ? 'stockQuantity' then
        dastak_v1_api.update_merchant_stock_selection(
          p_actor_id, p_branch_id, v_sku_id, v_selected, v_expected_version,
          pg_catalog.btrim(p_idempotency_key) || ':' || v_sku_id::text,
          (v_item ->> 'stockQuantity')::integer
        )
      else dastak_v1_api.update_merchant_sku_selection(
        p_actor_id, p_branch_id, v_sku_id, v_selected, v_expected_version,
        pg_catalog.btrim(p_idempotency_key) || ':' || v_sku_id::text
      ) end
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

create or replace function dastak_v1_api.merchant_canonical_catalogue_snapshot(
  p_actor_id uuid,
  p_branch_id uuid default null,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_state dastak_v1.branch_operational_states%rowtype;
  v_limit integer := least(greatest(coalesce(p_limit, 5000), 1), 5000);
  v_capacity_held integer;
  v_taxonomy jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  if p_branch_id is null then
    select branch.* into v_branch
    from dastak_v1.merchant_branches branch
    where branch.status not in ('CLOSED', 'SUSPENDED')
      and dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id, branch.organization_id, 'merchant.catalogue.selection.manage', branch.id
      )
    order by branch.created_at, branch.id
    limit 1;
  else
    select branch.* into v_branch
    from dastak_v1.merchant_branches branch
    where branch.id = p_branch_id;
  end if;
  if not found then
    raise exception using errcode = 'P0002', message = 'merchant branch not found';
  end if;
  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id, v_branch.organization_id, 'merchant.catalogue.selection.manage', v_branch.id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  select organization.* into strict v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;
  if v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    raise exception using errcode = '22023', message = 'canonical SKU selection is retail-only';
  end if;

  select state.* into v_state
  from dastak_v1.branch_operational_states state
  where state.branch_id = v_branch.id;
  select pg_catalog.count(*) into v_capacity_held
  from dastak_v1.retail_capacity_slots slot
  where slot.branch_id = v_branch.id and slot.status = 'HELD';
  v_taxonomy := dastak_v1_api.browse_catalogue_taxonomy(p_actor_id);

  return pg_catalog.jsonb_build_object(
    'branch', pg_catalog.jsonb_build_object(
      'branchId', v_branch.id,
      'branchName', v_branch.display_name,
      'branchStatus', v_branch.status,
      'branchVersion', v_branch.version,
      'organizationId', v_organization.id,
      'organizationName', v_organization.display_name,
      'merchantType', v_organization.merchant_type,
      'operationalState', pg_catalog.jsonb_build_object(
        'isOpen', coalesce(v_state.is_open, false),
        'acceptingOrders', coalesce(v_state.accepting_orders, false),
        'version', coalesce(v_state.version, 0),
        'updatedAt', v_state.updated_at
      ),
      'capacity', pg_catalog.jsonb_build_object(
        'limit', v_branch.capacity_limit,
        'held', v_capacity_held,
        'available', greatest(v_branch.capacity_limit - v_capacity_held, 0)
      )
    ),
    'skus', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'skuId', sku.id,
        'categoryTypeId', category.category_type_id,
        'categoryId', subcategory.category_id,
        'subcategoryId', sku.subcategory_id,
        'brandName', brand.name,
        'name', sku.canonical_name,
        'variant', sku.variant_name,
        'packSize', sku.pack_size,
        'description', sku.description,
        'imageKey', primary_image.image_key,
        'galleryImageKeys', coalesce((
          select pg_catalog.jsonb_agg(gallery.image_key order by gallery.sort_order, gallery.id)
          from dastak_v1.sku_images gallery
          where gallery.sku_id = sku.id
            and gallery.role = 'GALLERY'
            and gallery.status = 'VERIFIED'
            and gallery.rights_status = 'CLEARED'
        ), '[]'::jsonb),
        'quantityValue', sku.quantity_value,
        'quantityUnit', sku.quantity_unit,
        'packCount', sku.pack_count,
        'dietType', sku.diet_type,
        'searchTerms', coalesce((
          select pg_catalog.jsonb_agg(alias.alias order by alias.alias)
          from dastak_v1.sku_search_aliases alias
          where alias.sku_id = sku.id
        ), '[]'::jsonb),
        'listPricePaise', sku.list_price_paise,
        'sellingPricePaise', sku.selling_price_paise,
        'currencyCode', sku.currency_code,
        'catalogueStatus', sku.status,
        'selected', coalesce(selection.state = 'SELECTED', false),
        'selectionState', selection.state,
        'selectionVersion', coalesce(selection.version, 0),
        'stockQuantity', selection.stock_quantity,
        'selectionUpdatedAt', selection.updated_at
      ) order by category_type.sort_order, category.sort_order, subcategory.sort_order,
        pg_catalog.lower(sku.canonical_name), sku.id)
      from (
        select source.*
        from dastak_v1.skus source
        where source.status = 'ACTIVE'
          or exists (
            select 1
            from dastak_v1.merchant_sku_selections existing
            where existing.branch_id = v_branch.id and existing.sku_id = source.id
          )
        order by pg_catalog.lower(source.canonical_name), source.id
        limit v_limit
      ) sku
      join dastak_v1.subcategories subcategory on subcategory.id = sku.subcategory_id
      join dastak_v1.categories category on category.id = subcategory.category_id
      left join dastak_v1.category_types category_type on category_type.id = category.category_type_id
      left join dastak_v1.brands brand on brand.id = sku.brand_id
      left join dastak_v1.merchant_sku_selections selection
        on selection.branch_id = v_branch.id and selection.sku_id = sku.id
      left join lateral (
        select image.image_key
        from dastak_v1.sku_images image
        where image.sku_id = sku.id
          and image.role = 'PRIMARY'
          and image.status = 'VERIFIED'
          and image.rights_status = 'CLEARED'
        order by image.sort_order, image.id
        limit 1
      ) primary_image on true
    ), '[]'::jsonb),
    'truncated', (
      select pg_catalog.count(*) > v_limit
      from dastak_v1.skus sku
      where sku.status = 'ACTIVE'
        or exists (
          select 1
          from dastak_v1.merchant_sku_selections existing
          where existing.branch_id = v_branch.id and existing.sku_id = sku.id
        )
    )
  ) || v_taxonomy;
end;
$$;
