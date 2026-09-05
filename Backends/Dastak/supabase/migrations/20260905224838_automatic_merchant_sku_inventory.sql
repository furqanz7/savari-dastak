-- stock_quantity is AVAILABLE stock, excluding units committed to open orders.
-- NULL retains the legacy physical-confirmation flow until an opening count is entered.
-- Existing orders are not retroactively deducted.
alter table dastak_v1.merchant_sku_selections
  add column stock_reserved_quantity integer not null default 0 check (stock_reserved_quantity >= 0),
  add column stock_auto_unavailable boolean not null default false,
  add constraint merchant_stock_total_limit check (
    stock_quantity is null or stock_quantity::bigint + stock_reserved_quantity <= 1000000
  );

create table dastak_v1.merchant_stock_reservations (
  inventory_hold_id uuid primary key references dastak_v1.inventory_holds(id),
  fulfilment_id uuid not null references dastak_v1.fulfilments(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  sku_id uuid not null references dastak_v1.skus(id),
  quantity integer not null check (quantity > 0),
  state text not null check (state in ('RESERVED', 'CONSUMED', 'RELEASED')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check ((state = 'RESERVED') = (resolved_at is null))
);
create index merchant_stock_reservations_fulfilment_idx
  on dastak_v1.merchant_stock_reservations(fulfilment_id, state);
create index merchant_stock_reservations_branch_sku_idx
  on dastak_v1.merchant_stock_reservations(branch_id, sku_id);
create index merchant_stock_reservations_sku_idx
  on dastak_v1.merchant_stock_reservations(sku_id);
alter table dastak_v1.merchant_stock_reservations enable row level security;
revoke all on dastak_v1.merchant_stock_reservations from public, anon, authenticated, service_role;
create trigger merchant_stock_reservations_no_delete
  before delete on dastak_v1.merchant_stock_reservations
  for each row execute function dastak_v1.reject_delete();

create function dastak_v1.guard_stock_reservation()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.inventory_hold_id is distinct from old.inventory_hold_id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.branch_id is distinct from old.branch_id
    or new.sku_id is distinct from old.sku_id
    or new.quantity is distinct from old.quantity
    or new.created_at is distinct from old.created_at
    or old.state <> 'RESERVED'
    or new.state not in ('CONSUMED', 'RELEASED') then
    raise exception 'stock reservation identity and final outcome are immutable';
  end if;
  return new;
end;
$$;
create trigger merchant_stock_reservations_guard
  before update on dastak_v1.merchant_stock_reservations
  for each row execute function dastak_v1.guard_stock_reservation();

create function dastak_v1_api.apply_order_stock(p_hold_id uuid, p_action text)
returns void language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_hold dastak_v1.inventory_holds%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_fulfilment dastak_v1.fulfilments%rowtype;
  v_selection dastak_v1.merchant_sku_selections%rowtype;
  v_reservation dastak_v1.merchant_stock_reservations%rowtype;
  v_payload jsonb;
  v_delta integer;
begin
  if p_action not in ('RESERVE', 'RELEASE', 'CONSUME') or p_action is null then
    raise exception 'invalid inventory action';
  end if;
  select * into strict v_hold from dastak_v1.inventory_holds where id = p_hold_id;
  select * into strict v_line from dastak_v1.order_lines where id = v_hold.order_line_id;
  select * into strict v_fulfilment from dastak_v1.fulfilments where id = v_hold.fulfilment_id;
  if v_line.line_type <> 'RETAIL_SKU' then return; end if;
  if v_fulfilment.branch_id <> v_hold.branch_id or v_fulfilment.order_id <> v_line.order_id
    or not exists (select 1 from dastak_v1.fulfilment_lines fl
      where fl.fulfilment_id = v_hold.fulfilment_id and fl.order_line_id = v_line.id
        and fl.confirmed_quantity = v_hold.held_quantity) then
    raise exception 'stock hold does not match the confirmed fulfilment';
  end if;

  -- Same branch-first locking order as Merchant stock edits and order acceptance.
  -- All SKUs for a branch serialize here, so simultaneous orders cannot oversell.
  perform 1 from dastak_v1.merchant_branches where id = v_hold.branch_id for update;
  select * into v_selection from dastak_v1.merchant_sku_selections
    where branch_id = v_hold.branch_id and sku_id = v_line.sku_id for update;
  select * into v_reservation from dastak_v1.merchant_stock_reservations
    where inventory_hold_id = p_hold_id for update;

  if p_action = 'RESERVE' then
    if v_reservation.inventory_hold_id is not null then return; end if;
    if v_selection.stock_quantity is null then return; end if;
    if v_hold.status <> 'HELD' or v_fulfilment.status not in ('RESERVED_PREPAYMENT', 'PREPARING') then
      raise exception 'stock can only be reserved for an active fulfilment';
    end if;
    if v_selection.state <> 'SELECTED' or v_selection.stock_quantity < v_hold.held_quantity then
      raise exception using errcode = '55000',
        message = 'Insufficient stock. Refresh the product stock count before accepting this order.';
    end if;
    insert into dastak_v1.merchant_stock_reservations
      (inventory_hold_id, fulfilment_id, branch_id, sku_id, quantity, state)
    values (p_hold_id, v_hold.fulfilment_id, v_hold.branch_id, v_line.sku_id, v_hold.held_quantity, 'RESERVED');
    v_delta := -v_hold.held_quantity;
    update dastak_v1.merchant_sku_selections
    set stock_quantity = stock_quantity - v_hold.held_quantity,
        stock_reserved_quantity = stock_reserved_quantity + v_hold.held_quantity,
        stock_auto_unavailable = stock_quantity = v_hold.held_quantity,
        state = case when stock_quantity = v_hold.held_quantity then 'UNAVAILABLE'::dastak_v1.merchant_sku_state else state end,
        version = version + 1, updated_at = now()
    where branch_id = v_hold.branch_id and sku_id = v_line.sku_id returning * into v_selection;
  else
    -- Replays, historical untracked holds and already-final outcomes are no-ops.
    if v_reservation.inventory_hold_id is null or v_reservation.state <> 'RESERVED' then return; end if;
    if p_action = 'RELEASE' and (
      v_hold.status <> 'RELEASED' or v_fulfilment.status in ('PICKED_UP', 'COMPLETED')
      or exists (select 1 from dastak_v1.packages p where p.fulfilment_id = v_fulfilment.id and p.picked_up_at is not null)
    ) then
      raise exception 'stock cannot be restored after physical pickup';
    end if;
    if p_action = 'CONSUME' and v_fulfilment.status not in ('PICKED_UP', 'COMPLETED') then
      raise exception 'stock consumption requires confirmed pickup';
    end if;
    v_delta := case when p_action = 'RELEASE' then v_reservation.quantity else 0 end;
    update dastak_v1.merchant_stock_reservations
    set state = case when p_action = 'RELEASE' then 'RELEASED' else 'CONSUMED' end, resolved_at = now()
    where inventory_hold_id = p_hold_id;
    update dastak_v1.merchant_sku_selections
    set stock_quantity = stock_quantity + v_delta,
        stock_reserved_quantity = stock_reserved_quantity - v_reservation.quantity,
        state = case when p_action = 'RELEASE' and stock_auto_unavailable
          then 'SELECTED'::dastak_v1.merchant_sku_state else state end,
        stock_auto_unavailable = case when p_action = 'RELEASE' then false else stock_auto_unavailable end,
        version = version + 1, updated_at = now()
    where branch_id = v_hold.branch_id and sku_id = v_line.sku_id returning * into v_selection;
  end if;
  v_payload := jsonb_build_object('branchId', v_hold.branch_id, 'skuId', v_line.sku_id,
    'orderId', v_line.order_id, 'fulfilmentId', v_fulfilment.id, 'inventoryHoldId', p_hold_id,
    'inventoryAction', p_action, 'quantityDelta', v_delta,
    'stockQuantity', v_selection.stock_quantity, 'stockReservedQuantity', v_selection.stock_reserved_quantity,
    'selected', v_selection.state = 'SELECTED', 'state', v_selection.state, 'version', v_selection.version);
  insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
  values (auth.uid(), 'MERCHANT_STOCK_' || p_action, 'merchant_branch', v_hold.branch_id, v_payload);
  insert into dastak_v1.domain_events_outbox
    (event_key, aggregate_type, aggregate_id, aggregate_version, event_type, actor_id, payload)
  values (v_hold.branch_id::text || ':MERCHANT_CANONICAL_SKU_SELECTION_CHANGED:' ||
    v_line.sku_id::text || ':' || v_selection.version::text,
    'MERCHANT_SKU_SELECTION', md5(v_hold.branch_id::text || ':' || v_line.sku_id::text)::uuid, v_selection.version,
    'MERCHANT_CANONICAL_SKU_SELECTION_CHANGED', auth.uid(), v_payload);
end;
$$;

create function dastak_v1.sync_order_stock_hold()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'HELD' then perform dastak_v1_api.apply_order_stock(new.id, 'RESERVE'); end if;
  elsif old.status = 'HELD' and new.status = 'RELEASED' then
    perform dastak_v1_api.apply_order_stock(new.id, 'RELEASE');
  end if;
  return new;
end;
$$;
create trigger inventory_holds_stock
  after insert or update of status on dastak_v1.inventory_holds
  for each row execute function dastak_v1.sync_order_stock_hold();

create function dastak_v1.consume_stock_after_pickup()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_hold_id uuid;
begin
  if new.status in ('PICKED_UP', 'COMPLETED') and new.status is distinct from old.status then
    for v_hold_id in select inventory_hold_id from dastak_v1.merchant_stock_reservations
      where fulfilment_id = new.id and state = 'RESERVED' order by sku_id, inventory_hold_id
    loop
      perform dastak_v1_api.apply_order_stock(v_hold_id, 'CONSUME');
    end loop;
  end if;
  return new;
end;
$$;
create trigger fulfilments_consume_stock
  after update of status on dastak_v1.fulfilments
  for each row execute function dastak_v1.consume_stock_after_pickup();

revoke all on function dastak_v1_api.apply_order_stock(uuid,text) from public,anon,authenticated,service_role;
revoke all on function dastak_v1.guard_stock_reservation() from public,anon,authenticated,service_role;
revoke all on function dastak_v1.sync_order_stock_hold() from public,anon,authenticated,service_role;
revoke all on function dastak_v1.consume_stock_after_pickup() from public,anon,authenticated,service_role;
comment on column dastak_v1.merchant_sku_selections.stock_quantity is
  'Available units excluding order reservations. NULL means opening count not entered. Never deduct fulfilled orders manually.';

-- Manual edits clear automatic unavailability; reservations remain server-owned.
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
        stock_auto_unavailable = false,
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
    'MERCHANT_SKU_SELECTION', md5(p_branch_id::text || ':' || p_sku_id::text)::uuid, v_selection.version,
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
        stock_auto_unavailable = false,
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
    'MERCHANT_SKU_SELECTION', md5(p_branch_id::text || ':' || p_sku_id::text)::uuid, v_selection.version,
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

-- Matching checks the requested quantity, and final reservation rechecks under locks.
CREATE OR REPLACE FUNCTION dastak_v1_api.evaluate_wave1_candidate(p_order_id uuid, p_branch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order dastak_v1.orders%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_operating dastak_v1.branch_operational_states%rowtype;
  v_zone public.service_zones%rowtype;
  v_address jsonb;
  v_customer_location extensions.geometry(Point, 4326);
  v_radius_meters integer;
  v_prep_options jsonb;
  v_configuration jsonb;
  v_distance_meters numeric;
  v_retail_line_count integer;
  v_selected_line_count integer;
  v_held_capacity integer;
  v_reasons text[] := '{}'::text[];
begin
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id;

  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id;

  if not found or v_order.id is null then
    raise exception using errcode = 'P0002', message = 'order or branch not found';
  end if;

  select organization.* into v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;

  select state.* into v_operating
  from dastak_v1.branch_operational_states state
  where state.branch_id = v_branch.id;

  if v_branch.service_zone_id is not null then
    select zone.* into v_zone
    from public.service_zones zone
    where zone.id = v_branch.service_zone_id;
  end if;

  select context_snapshot.delivery_address into v_address
  from dastak_v1.order_context_snapshots context_snapshot
  where context_snapshot.order_id = v_order.id;

  if pg_catalog.jsonb_typeof(v_address -> 'latitude') = 'number'
    and pg_catalog.jsonb_typeof(v_address -> 'longitude') = 'number' then
    v_customer_location := extensions.st_setsrid(
      extensions.st_makepoint(
        (v_address ->> 'longitude')::double precision,
        (v_address ->> 'latitude')::double precision
      ),
      4326
    );
  end if;

  select count(*) into v_retail_line_count
  from dastak_v1.order_lines order_line
  where order_line.order_id = v_order.id
    and order_line.line_type = 'RETAIL_SKU';

  select count(*) into v_selected_line_count
  from dastak_v1.order_lines order_line
  where order_line.order_id = v_order.id
    and order_line.line_type = 'RETAIL_SKU'
    and exists (
      select 1
      from dastak_v1.merchant_sku_selections selection
      where selection.branch_id = v_branch.id
        and selection.sku_id = order_line.sku_id
        and selection.state = 'SELECTED' and (selection.stock_quantity is null or selection.stock_quantity >= order_line.quantity)
    );

  select count(*) into v_held_capacity
  from dastak_v1.retail_capacity_slots slot
  where slot.branch_id = v_branch.id
    and slot.status = 'HELD';

  if v_organization.status is distinct from 'ACTIVE' then
    v_reasons := pg_catalog.array_append(v_reasons, 'ORGANIZATION_NOT_ACTIVE');
  end if;
  if v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    v_reasons := pg_catalog.array_append(v_reasons, 'NOT_RETAIL');
  end if;
  if v_branch.status is distinct from 'ACTIVE' then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_NOT_ACTIVE');
  end if;
  if v_operating.branch_id is null or not v_operating.is_open then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_CLOSED');
  end if;
  if v_operating.branch_id is null or not v_operating.accepting_orders then
    v_reasons := pg_catalog.array_append(v_reasons, 'NOT_ACCEPTING_ORDERS');
  end if;
  if v_branch.service_zone_id is null or v_zone.id is null or not v_zone.active then
    v_reasons := pg_catalog.array_append(v_reasons, 'SERVICE_ZONE_UNAVAILABLE');
  end if;
  if v_customer_location is null then
    v_reasons := pg_catalog.array_append(v_reasons, 'CUSTOMER_LOCATION_MISSING');
  end if;
  if v_branch.location is null then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_LOCATION_MISSING');
  end if;
  if v_organization.status = 'ACTIVE'
    and v_organization.merchant_type in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
    and v_branch.status = 'ACTIVE'
    and v_operating.branch_id is not null
    and v_operating.is_open
    and v_operating.accepting_orders
    and v_zone.id is not null
    and v_zone.active then
    v_configuration := dastak_v1_api.wave1_branch_configuration(
      v_branch.id,
      v_branch.organization_id,
      v_branch.service_zone_id
    );
    v_radius_meters := (v_configuration ->> 'retailRadiusMeters')::integer;
    v_prep_options := v_configuration -> 'prepTimeOptionsMinutes';
  end if;

  if v_zone.id is not null and v_zone.active and v_customer_location is not null
    and not extensions.st_covers(v_zone.boundary, v_customer_location) then
    v_reasons := pg_catalog.array_append(v_reasons, 'CUSTOMER_OUTSIDE_SERVICE_ZONE');
  end if;
  if v_zone.id is not null and v_zone.active and v_branch.location is not null
    and not extensions.st_covers(v_zone.boundary, v_branch.location) then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_OUTSIDE_SERVICE_ZONE');
  end if;

  if v_customer_location is not null and v_branch.location is not null then
    v_distance_meters := extensions.st_distance(
      v_branch.location::extensions.geography,
      v_customer_location::extensions.geography
    );
    if v_radius_meters is not null and v_distance_meters > v_radius_meters then
      v_reasons := pg_catalog.array_append(v_reasons, 'OUTSIDE_RETAIL_RADIUS');
    end if;
  end if;

  if v_held_capacity >= v_branch.capacity_limit then
    v_reasons := pg_catalog.array_append(v_reasons, 'AT_CAPACITY');
  end if;
  if v_retail_line_count = 0 then
    v_reasons := pg_catalog.array_append(v_reasons, 'EMPTY_RETAIL_BASKET');
  elsif v_selected_line_count <> v_retail_line_count then
    v_reasons := pg_catalog.array_append(v_reasons, 'INCOMPLETE_CATALOGUE_COVERAGE');
  end if;

  return pg_catalog.jsonb_build_object(
    'eligible', pg_catalog.cardinality(v_reasons) = 0,
    'exclusionReasons', pg_catalog.to_jsonb(v_reasons),
    'retailLineCount', v_retail_line_count,
    'selectedLineCount', v_selected_line_count,
    'heldCapacity', v_held_capacity,
    'capacityLimit', v_branch.capacity_limit,
    'retailRadiusMeters', v_radius_meters,
    'prepTimeOptionsMinutes', v_prep_options,
    'distanceMeters', case
      when v_distance_meters is null then null
      else pg_catalog.round(v_distance_meters)
    end,
    'serviceZoneId', v_branch.service_zone_id,
    'evaluatedAt', pg_catalog.clock_timestamp()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.start_wave2(p_order_id uuid, p_actor_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order dastak_v1.orders%rowtype;
  v_wave1 dastak_v1.matching_attempts%rowtype;
  v_attempt_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_configuration jsonb;
  v_expires_at timestamptz;
  v_candidate_count integer := 0;
  v_opportunity_count integer := 0;
  v_transport jsonb;
begin
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  select attempt.id into v_attempt_id
  from dastak_v1.matching_attempts attempt
  where attempt.order_id = v_order.id
    and attempt.wave = 'WAVE_2';

  if v_attempt_id is not null then
    return v_attempt_id;
  end if;

  select attempt.* into v_wave1
  from dastak_v1.matching_attempts attempt
  where attempt.order_id = v_order.id
    and attempt.wave = 'WAVE_1'
  for update;

  if v_order.status <> 'MATCHING'
    or v_order.order_type not in ('RETAIL_ONLY', 'MIXED')
    or v_wave1.status <> 'EXPIRED' then
    raise exception using
      errcode = '55000',
      message = 'order is not eligible to start Wave 2';
  end if;

  -- Required operational settings are resolved before availability is
  -- evaluated. A missing value aborts instead of masquerading as no stock.
  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_transport := dastak_v1_api.order_transport_snapshot(v_order.id);
  v_expires_at := v_now + pg_catalog.make_interval(
    secs => (v_configuration ->> 'wave2TimeoutSeconds')::integer
  );

  insert into dastak_v1.matching_attempts (
    order_id, wave, status, started_at, expires_at
  ) values (
    v_order.id, 'WAVE_2', 'OPEN', v_now, v_expires_at
  )
  returning id into v_attempt_id;

  insert into dastak_v1.matching_candidate_evaluations (
    matching_attempt_id, order_id, organization_id, branch_id,
    eligible, exclusion_reasons, eligibility_snapshot, evaluated_at
  )
  select
    v_attempt_id,
    v_order.id,
    branch.organization_id,
    branch.id,
    (evaluation.snapshot ->> 'eligible')::boolean,
    array(
      select pg_catalog.jsonb_array_elements_text(
        evaluation.snapshot -> 'exclusionReasons'
      )
    ),
    evaluation.snapshot,
    v_now
  from dastak_v1.merchant_branches branch
  join dastak_v1.merchant_organizations organization
    on organization.id = branch.organization_id
  cross join lateral (
    select dastak_v1_api.evaluate_wave2_candidate(v_order.id, branch.id) snapshot
  ) evaluation
  where organization.merchant_type in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
  order by branch.id;

  get diagnostics v_candidate_count = row_count;

  -- A valid configuration but an over-limit basket is genuine transport
  -- infeasibility. It opens no merchant opportunities and expires normally.
  if (v_transport ->> 'feasible')::boolean then
    insert into dastak_v1.merchant_opportunities (
      matching_attempt_id, order_id, organization_id, branch_id,
      status, started_at, expires_at
    )
    select
      evaluation.matching_attempt_id,
      evaluation.order_id,
      evaluation.organization_id,
      evaluation.branch_id,
      'OFFERED',
      v_now,
      v_expires_at
    from dastak_v1.matching_candidate_evaluations evaluation
    where evaluation.matching_attempt_id = v_attempt_id
      and evaluation.eligible
    order by evaluation.branch_id;
  end if;

  get diagnostics v_opportunity_count = row_count;

  insert into dastak_v1.merchant_opportunity_lines (
    opportunity_id, order_line_id, sku_id, product_name_snapshot,
    variant_snapshot, pack_size_snapshot, requested_quantity
  )
  select
    opportunity.id,
    order_line.id,
    order_line.sku_id,
    order_line.product_name_snapshot,
    order_line.variant_snapshot,
    order_line.pack_size_snapshot,
    order_line.quantity
  from dastak_v1.merchant_opportunities opportunity
  join dastak_v1.order_lines order_line
    on order_line.order_id = opportunity.order_id
    and order_line.line_type = 'RETAIL_SKU'
  join dastak_v1.merchant_sku_selections selection
    on selection.branch_id = opportunity.branch_id
    and selection.sku_id = order_line.sku_id
    and selection.state = 'SELECTED' and (selection.stock_quantity is null or selection.stock_quantity >= order_line.quantity)
  where opportunity.matching_attempt_id = v_attempt_id
  order by opportunity.id, order_line.created_at, order_line.id;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_attempt_id::text || ':WAVE_2_STARTED:1',
    'MATCHING_ATTEMPT',
    v_attempt_id,
    1,
    'WAVE_2_STARTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'attemptId', v_attempt_id,
      'orderId', v_order.id,
      'startedAt', v_now,
      'expiresAt', v_expires_at,
      'eligibleOpportunityCount', v_opportunity_count,
      'transportSnapshot', v_transport
    )
  );

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  )
  select
    opportunity.id::text || ':MERCHANT_OPPORTUNITY_OFFERED:1',
    'MERCHANT_OPPORTUNITY',
    opportunity.id,
    1,
    'MERCHANT_OPPORTUNITY_OFFERED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'opportunityId', opportunity.id,
      'orderId', opportunity.order_id,
      'organizationId', opportunity.organization_id,
      'branchId', opportunity.branch_id,
      'expiresAt', opportunity.expires_at,
      'subsetLineCount', (
        select count(*)
        from dastak_v1.merchant_opportunity_lines line
        where line.opportunity_id = opportunity.id
      )
    )
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.matching_attempt_id = v_attempt_id;

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'WAVE_2_STARTED',
    'matching_attempt',
    v_attempt_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'candidateCount', v_candidate_count,
      'opportunityCount', v_opportunity_count,
      'startedAt', v_now,
      'expiresAt', v_expires_at,
      'transportFeasible', v_transport -> 'feasible'
    )
  );

  return v_attempt_id;
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.lock_best_wave2_plan(p_attempt_id uuid, p_actor_id uuid DEFAULT NULL::uuid, p_force boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_plan dastak_v1.fulfilment_plans%rowtype;
  v_merchant record;
  v_fulfilment_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_configuration jsonb;
  v_transport jsonb;
  v_route_distance bigint;
  v_invalid_reason text;
  v_held_capacity integer;
  v_coordination jsonb;
begin
  select attempt.order_id into v_order_id
  from dastak_v1.matching_attempts attempt
  where attempt.id = p_attempt_id;

  if not found then
    return false;
  end if;

  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;

  select attempt.* into v_attempt
  from dastak_v1.matching_attempts attempt
  where attempt.id = p_attempt_id
  for update;

  if v_attempt.wave <> 'WAVE_2' then
    raise exception using errcode = '22023', message = 'attempt is not Wave 2';
  end if;
  if v_attempt.status = 'WON' then
    return true;
  end if;
  if v_attempt.status <> 'OPEN' or v_order.status <> 'MATCHING' then
    return false;
  end if;
  if not p_force and v_now >= v_attempt.expires_at then
    return false;
  end if;
  if not p_force and exists (
    select 1
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status = 'OFFERED'
  ) then
    return false;
  end if;

  perform dastak_v1_api.record_wave2_candidate_plans(v_attempt.id);
  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_transport := dastak_v1_api.order_transport_snapshot(v_order.id);

  for v_plan in
    select plan.*
    from dastak_v1.fulfilment_plans plan
    where plan.matching_attempt_id = v_attempt.id
      and plan.status = 'CANDIDATE'
    order by
      plan.merchant_count,
      plan.route_distance_meters,
      plan.reliability_score_bps desc,
      plan.fingerprint,
      plan.id
    for update
  loop
    v_invalid_reason := null;

    perform branch.id
    from dastak_v1.merchant_branches branch
    join dastak_v1.fulfilment_plan_merchants plan_merchant
      on plan_merchant.branch_id = branch.id
    where plan_merchant.plan_id = v_plan.id
    order by branch.id
    for update;

    perform hold.id
    from dastak_v1.wave2_provisional_holds hold
    join dastak_v1.fulfilment_plan_lines plan_line
      on plan_line.provisional_hold_id = hold.id
    where plan_line.plan_id = v_plan.id
    order by hold.id
    for update;

    if (
      select count(*)
      from dastak_v1.fulfilment_plan_merchants plan_merchant
      where plan_merchant.plan_id = v_plan.id
    ) <> v_plan.merchant_count
      or (
        select count(*)
        from dastak_v1.fulfilment_plan_lines plan_line
        where plan_line.plan_id = v_plan.id
      ) <> v_plan.retail_line_count then
      v_invalid_reason := 'PLAN_COVERAGE_INVALID';
    elsif exists (
      select 1
      from dastak_v1.fulfilment_plan_lines plan_line
      join dastak_v1.order_lines order_line
        on order_line.id = plan_line.order_line_id
      join dastak_v1.wave2_provisional_holds hold
        on hold.id = plan_line.provisional_hold_id
      join dastak_v1.merchant_opportunities opportunity
        on opportunity.id = hold.opportunity_id
      where plan_line.plan_id = v_plan.id
        and (
          order_line.order_id <> v_order.id
          or order_line.line_type <> 'RETAIL_SKU'
          or plan_line.allocated_quantity <> order_line.quantity
          or hold.order_line_id <> order_line.id
          or hold.branch_id <> plan_line.branch_id
          or hold.held_quantity <> order_line.quantity
          or hold.status <> 'HELD'
          or hold.expires_at <= v_now
          or opportunity.status <> 'PROVISIONALLY_ACCEPTED'
        )
    ) then
      v_invalid_reason := 'PROVISIONAL_HOLD_INVALID';
    elsif exists (
      select 1
      from dastak_v1.fulfilment_plan_merchants plan_merchant
      join dastak_v1.merchant_branches branch
        on branch.id = plan_merchant.branch_id
      join dastak_v1.merchant_organizations organization
        on organization.id = branch.organization_id
      left join dastak_v1.branch_operational_states operating
        on operating.branch_id = branch.id
      where plan_merchant.plan_id = v_plan.id
        and (
          organization.status <> 'ACTIVE'
          or organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE')
          or branch.status <> 'ACTIVE'
          or operating.branch_id is null
          or not operating.is_open
          or not operating.accepting_orders
        )
    ) then
      v_invalid_reason := 'BRANCH_ELIGIBILITY_LOST';
    elsif exists (
      select 1
      from dastak_v1.fulfilment_plan_lines plan_line
      join dastak_v1.order_lines order_line
        on order_line.id = plan_line.order_line_id
      where plan_line.plan_id = v_plan.id
        and not exists (
          select 1
          from dastak_v1.merchant_sku_selections selection
          where selection.branch_id = plan_line.branch_id
            and selection.sku_id = order_line.sku_id
            and selection.state = 'SELECTED' and (selection.stock_quantity is null or selection.stock_quantity >= order_line.quantity)
        )
    ) then
      v_invalid_reason := 'MERCHANT_SKU_SELECTION_LOST';
    end if;

    if v_invalid_reason is null then
      for v_merchant in
        select plan_merchant.branch_id
        from dastak_v1.fulfilment_plan_merchants plan_merchant
        where plan_merchant.plan_id = v_plan.id
        order by plan_merchant.branch_id
      loop
        select count(*) into v_held_capacity
        from dastak_v1.retail_capacity_slots slot
        where slot.branch_id = v_merchant.branch_id
          and slot.status = 'HELD';

        if v_held_capacity >= (
          select branch.capacity_limit
          from dastak_v1.merchant_branches branch
          where branch.id = v_merchant.branch_id
        ) then
          v_invalid_reason := 'BRANCH_CAPACITY_LOST';
          exit;
        end if;
      end loop;
    end if;

    if v_invalid_reason is null and not (v_transport ->> 'feasible')::boolean then
      v_invalid_reason := 'TRANSPORT_LOAD_INFEASIBLE';
    end if;

    -- Recompute the route from locked branch rows; the persisted evaluation is
    -- evidence, not authority at final lock.
    if v_invalid_reason is null then
      v_route_distance := dastak_v1_api.pickup_route_distance_meters(
        v_order.id,
        array(
          select plan_merchant.branch_id
          from dastak_v1.fulfilment_plan_merchants plan_merchant
          where plan_merchant.plan_id = v_plan.id
          order by plan_merchant.branch_id
        )
      );
      if v_route_distance is null
        or v_route_distance > (v_configuration ->> 'maxPickupRouteMeters')::bigint then
        v_invalid_reason := 'PICKUP_ROUTE_INFEASIBLE';
      end if;
    end if;

    if v_invalid_reason is not null then
      update dastak_v1.fulfilment_plans
      set status = 'REJECTED',
          rejected_at = v_now,
          rejection_reason = v_invalid_reason,
          version = version + 1
      where id = v_plan.id;
      continue;
    end if;

    for v_merchant in
      select
        plan_merchant.branch_id,
        plan_merchant.opportunity_id,
        opportunity.organization_id,
        opportunity.promised_prep_minutes
      from dastak_v1.fulfilment_plan_merchants plan_merchant
      join dastak_v1.merchant_opportunities opportunity
        on opportunity.id = plan_merchant.opportunity_id
      where plan_merchant.plan_id = v_plan.id
      order by plan_merchant.branch_id
    loop
      v_fulfilment_id := gen_random_uuid();

      insert into dastak_v1.fulfilments (
        id, order_id, organization_id, branch_id, source_opportunity_id,
        fulfilment_type, status, promised_prep_minutes, committed_at
      ) values (
        v_fulfilment_id,
        v_order.id,
        v_merchant.organization_id,
        v_merchant.branch_id,
        v_merchant.opportunity_id,
        'RETAIL',
        'RESERVED_PREPAYMENT',
        v_merchant.promised_prep_minutes,
        v_now
      );

      insert into dastak_v1.fulfilment_lines (
        fulfilment_id, order_line_id, confirmed_quantity
      )
      select
        v_fulfilment_id,
        plan_line.order_line_id,
        plan_line.allocated_quantity
      from dastak_v1.fulfilment_plan_lines plan_line
      where plan_line.plan_id = v_plan.id
        and plan_line.branch_id = v_merchant.branch_id
      order by plan_line.order_line_id;

      insert into dastak_v1.inventory_holds (
        fulfilment_id, order_line_id, branch_id, held_quantity,
        status, held_at
      )
      select
        v_fulfilment_id,
        plan_line.order_line_id,
        v_merchant.branch_id,
        plan_line.allocated_quantity,
        'HELD',
        v_now
      from dastak_v1.fulfilment_plan_lines plan_line
      where plan_line.plan_id = v_plan.id
        and plan_line.branch_id = v_merchant.branch_id
      order by plan_line.order_line_id;

      insert into dastak_v1.retail_capacity_slots (
        branch_id, fulfilment_id, status, held_at
      ) values (
        v_merchant.branch_id, v_fulfilment_id, 'HELD', v_now
      );

      insert into dastak_v1.retail_line_allocations (
        order_line_id, merchant_branch_id, allocated_quantity, status
      )
      select
        plan_line.order_line_id,
        v_merchant.branch_id,
        plan_line.allocated_quantity,
        'SELECTED'
      from dastak_v1.fulfilment_plan_lines plan_line
      where plan_line.plan_id = v_plan.id
        and plan_line.branch_id = v_merchant.branch_id
      order by plan_line.order_line_id;

      update dastak_v1.wave2_provisional_holds hold
      set status = 'SELECTED',
          selected_at = v_now,
          final_inventory_hold_id = final_hold.id,
          version = hold.version + 1
      from dastak_v1.fulfilment_plan_lines plan_line
      join dastak_v1.inventory_holds final_hold
        on final_hold.fulfilment_id = v_fulfilment_id
        and final_hold.order_line_id = plan_line.order_line_id
      where plan_line.plan_id = v_plan.id
        and plan_line.branch_id = v_merchant.branch_id
        and hold.id = plan_line.provisional_hold_id
        and hold.status = 'HELD';
    end loop;

    update dastak_v1.wave2_provisional_holds hold
    set status = 'RELEASED',
        released_at = v_now,
        release_reason = 'NOT_SELECTED_IN_FINAL_PLAN',
        version = hold.version + 1
    where hold.matching_attempt_id = v_attempt.id
      and hold.status = 'HELD';

    update dastak_v1.merchant_opportunities opportunity
    set status = 'SELECTED', version = opportunity.version + 1
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status = 'PROVISIONALLY_ACCEPTED'
      and exists (
        select 1
        from dastak_v1.fulfilment_plan_merchants plan_merchant
        where plan_merchant.plan_id = v_plan.id
          and plan_merchant.opportunity_id = opportunity.id
      );

    update dastak_v1.merchant_opportunities opportunity
    set status = case
          when opportunity.status = 'PROVISIONALLY_ACCEPTED' then 'RELEASED'::dastak_v1.merchant_opportunity_status
          else 'INVALIDATED'::dastak_v1.merchant_opportunity_status
        end,
        version = opportunity.version + 1
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status in ('PROVISIONALLY_ACCEPTED', 'OFFERED');

    update dastak_v1.fulfilment_plans plan
    set status = 'REJECTED',
        rejected_at = v_now,
        rejection_reason = 'BETTER_PLAN_SELECTED',
        version = plan.version + 1
    where plan.matching_attempt_id = v_attempt.id
      and plan.id <> v_plan.id
      and plan.status = 'CANDIDATE';

    update dastak_v1.fulfilment_plans
    set status = 'LOCKED', locked_at = v_now, version = version + 1
    where id = v_plan.id;

    update dastak_v1.matching_attempts
    set status = 'WON', closed_at = v_now, version = version + 1
    where id = v_attempt.id;

    update dastak_v1.order_lines
    set status = 'RESERVED', version = version + 1
    where order_id = v_order.id
      and line_type = 'RETAIL_SKU'
      and status = 'ORDERED';

    insert into dastak_v1.domain_events_outbox (
      event_key, aggregate_type, aggregate_id, aggregate_version,
      event_type, actor_id, payload
    ) values (
      v_plan.id::text || ':WAVE_2_PLAN_LOCKED:2',
      'FULFILMENT_PLAN',
      v_plan.id,
      2,
      'WAVE_2_PLAN_LOCKED',
      p_actor_id,
      pg_catalog.jsonb_build_object(
        'planId', v_plan.id,
        'attemptId', v_attempt.id,
        'orderId', v_order.id,
        'merchantCount', v_plan.merchant_count,
        'routeDistanceMeters', v_route_distance,
        'reliabilityScoreBps', v_plan.reliability_score_bps,
        'advertisingInfluence', false
      )
    );

    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_actor_id,
      'WAVE_2_PLAN_LOCKED',
      'fulfilment_plan',
      v_plan.id,
      pg_catalog.jsonb_build_object(
        'attemptId', v_attempt.id,
        'orderId', v_order.id,
        'merchantCount', v_plan.merchant_count,
        'routeDistanceMeters', v_route_distance,
        'reliabilityScoreBps', v_plan.reliability_score_bps,
        'physicalHoldsConverted', true,
        'capacityRevalidated', true
      )
    );

    v_coordination := dastak_v1_api.coordinate_fully_secured(v_order.id, p_actor_id);
    if v_order.order_type = 'RETAIL_ONLY'
      and not coalesce((v_coordination ->> 'coordinated')::boolean, false) then
      raise exception using
        errcode = '55000',
        message = 'FULLY_SECURED_COORDINATION_FAILED',
        detail = v_coordination::text;
    end if;

    return true;
  end loop;

  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.accept_wave2_opportunity(p_actor_id uuid, p_opportunity_id uuid, p_idempotency_key text, p_expected_version bigint, p_promised_prep_minutes integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_command constant text := 'acceptWave2Opportunity';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_order_id uuid;
  v_attempt_id uuid;
  v_order dastak_v1.orders%rowtype;
  v_attempt dastak_v1.matching_attempts%rowtype;
  v_opportunity dastak_v1.merchant_opportunities%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_prep_options jsonb;
  v_evaluation jsonb;
  v_configuration jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
  v_locked boolean := false;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);

  if p_idempotency_key is null
    or pg_catalog.char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid idempotency key';
  end if;
  if p_promised_prep_minutes is null or p_promised_prep_minutes <= 0 then
    raise exception using errcode = '22023', message = 'promised preparation time is required';
  end if;

  v_request_hash := dastak_v1_api.request_hash(
    pg_catalog.jsonb_build_object(
      'opportunityId', p_opportunity_id,
      'expectedVersion', p_expected_version,
      'promisedPrepMinutes', p_promised_prep_minutes
    )
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
    )
  );

  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;

  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using
      errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  select opportunity.order_id, opportunity.matching_attempt_id
  into v_order_id, v_attempt_id
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'opportunity not found';
  end if;

  -- Global lock order: order, attempt, opportunity, branch, then holds.
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_order_id
  for update;

  select attempt.* into v_attempt
  from dastak_v1.matching_attempts attempt
  where attempt.id = v_attempt_id
  for update;

  select opportunity.* into v_opportunity
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id
  for update;

  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = v_opportunity.branch_id
  for update;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_opportunity.organization_id,
    'merchant.opportunities.respond',
    v_opportunity.branch_id
  ) then
    raise exception using errcode = '42501', message = 'permission denied';
  end if;

  if v_opportunity.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale opportunity version';
  end if;
  if v_order.status <> 'MATCHING' or v_order.paid_at is not null
    or v_attempt.wave <> 'WAVE_2' or v_attempt.status <> 'OPEN'
    or v_opportunity.wave <> 'WAVE_2' or v_opportunity.status <> 'OFFERED' then
    raise exception using errcode = '55000', message = 'matching opportunity is no longer open';
  end if;
  if v_now >= v_attempt.expires_at or v_now >= v_opportunity.expires_at then
    raise exception using errcode = '55000', message = 'matching opportunity has expired';
  end if;

  v_configuration := dastak_v1_api.wave2_global_configuration();
  v_prep_options := dastak_v1_api.retail_prep_options(
    v_branch.id, v_branch.organization_id, v_branch.service_zone_id
  );
  if not v_prep_options @> pg_catalog.jsonb_build_array(p_promised_prep_minutes) then
    raise exception using errcode = '22023', message = 'promised preparation time is not allowed';
  end if;

  v_evaluation := dastak_v1_api.evaluate_wave2_candidate(v_order.id, v_branch.id);
  if not (v_evaluation ->> 'eligible')::boolean then
    raise exception using errcode = '55000', message = 'branch is no longer eligible for this order';
  end if;

  if not exists (
    select 1
    from dastak_v1.merchant_opportunity_lines opportunity_line
    where opportunity_line.opportunity_id = v_opportunity.id
  ) or exists (
    select 1
    from dastak_v1.merchant_opportunity_lines opportunity_line
    where opportunity_line.opportunity_id = v_opportunity.id
      and not exists (
        select 1
        from dastak_v1.order_lines order_line
        join dastak_v1.merchant_sku_selections selection
          on selection.branch_id = v_branch.id
          and selection.sku_id = order_line.sku_id
          and selection.state = 'SELECTED' and (selection.stock_quantity is null or selection.stock_quantity >= order_line.quantity)
        where order_line.id = opportunity_line.order_line_id
          and order_line.order_id = v_order.id
          and order_line.line_type = 'RETAIL_SKU'
          and order_line.sku_id = opportunity_line.sku_id
          and order_line.quantity = opportunity_line.requested_quantity
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'opportunity subset no longer matches the exact canonical order';
  end if;

  update dastak_v1.merchant_opportunities
  set status = 'PROVISIONALLY_ACCEPTED',
      promised_prep_minutes = p_promised_prep_minutes,
      responded_by = p_actor_id,
      responded_at = v_now,
      version = version + 1
  where id = v_opportunity.id;

  insert into dastak_v1.wave2_provisional_holds (
    opportunity_id, matching_attempt_id, order_id, order_line_id,
    branch_id, held_quantity, status, held_at, expires_at
  )
  select
    v_opportunity.id,
    v_attempt.id,
    v_order.id,
    opportunity_line.order_line_id,
    v_branch.id,
    opportunity_line.requested_quantity,
    'HELD',
    v_now,
    v_now + pg_catalog.make_interval(
      secs => (v_configuration ->> 'wave2HoldSeconds')::integer
    )
  from dastak_v1.merchant_opportunity_lines opportunity_line
  where opportunity_line.opportunity_id = v_opportunity.id
  order by opportunity_line.order_line_id;

  perform dastak_v1_api.record_wave2_candidate_plans(v_attempt.id);

  if not exists (
    select 1
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.matching_attempt_id = v_attempt.id
      and opportunity.status = 'OFFERED'
  ) then
    v_locked := dastak_v1_api.lock_best_wave2_plan(v_attempt.id, p_actor_id, true);
    if not v_locked then
      perform dastak_v1_api.fail_wave2_attempt(
        v_attempt.id, 'NO_VALID_COMPLETE_WAVE_2_PLAN', p_actor_id
      );
    end if;
  end if;

  select opportunity.* into v_opportunity
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id;

  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_opportunity.id::text || ':WAVE_2_PROVISIONAL_ACCEPTED:'
      || v_opportunity.version::text,
    'MERCHANT_OPPORTUNITY',
    v_opportunity.id,
    v_opportunity.version,
    'WAVE_2_PROVISIONAL_ACCEPTED',
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'opportunityId', v_opportunity.id,
      'attemptId', v_attempt.id,
      'orderId', v_order.id,
      'branchId', v_branch.id,
      'promisedPrepMinutes', p_promised_prep_minutes,
      'physicalStockConfirmed', true,
      'capacityConsumed', false,
      'finalPlanLocked', v_locked
    )
  );

  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    'WAVE_2_OPPORTUNITY_PROVISIONALLY_ACCEPTED',
    'merchant_opportunity',
    v_opportunity.id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'attemptId', v_attempt.id,
      'branchId', v_branch.id,
      'idempotencyKey', p_idempotency_key,
      'physicalStockConfirmed', true,
      'capacityConsumed', false,
      'finalPlanLocked', v_locked
    )
  );

  v_response := dastak_v1_api.merchant_opportunity_json(
    p_actor_id, v_opportunity.id
  ) || pg_catalog.jsonb_build_object('finalPlanLocked', v_locked);

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_opportunity.id
  );

  return v_response;
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.recovery_branch_eligibility(p_recovery_case_id uuid, p_branch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_case dastak_v1.recovery_cases%rowtype;
  v_line dastak_v1.order_lines%rowtype;
  v_source dastak_v1.fulfilments%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_organization dastak_v1.merchant_organizations%rowtype;
  v_operating dastak_v1.branch_operational_states%rowtype;
  v_address jsonb;
  v_customer_location extensions.geometry(Point, 4326);
  v_distance numeric;
  v_radius integer;
  v_held integer;
  v_reasons text[] := '{}'::text[];
begin
  select recovery.* into v_case
  from dastak_v1.recovery_cases recovery where recovery.id = p_recovery_case_id;
  select line.* into v_line from dastak_v1.order_lines line
  where line.id = v_case.order_line_id;
  select fulfilment.* into v_source from dastak_v1.fulfilments fulfilment
  where fulfilment.id = v_case.source_fulfilment_id;
  select branch.* into v_branch from dastak_v1.merchant_branches branch
  where branch.id = p_branch_id;
  select organization.* into v_organization
  from dastak_v1.merchant_organizations organization
  where organization.id = v_branch.organization_id;
  select state.* into v_operating
  from dastak_v1.branch_operational_states state where state.branch_id = v_branch.id;
  select snapshot.delivery_address into v_address
  from dastak_v1.order_context_snapshots snapshot where snapshot.order_id = v_case.order_id;
  if pg_catalog.jsonb_typeof(v_address -> 'latitude') = 'number'
    and pg_catalog.jsonb_typeof(v_address -> 'longitude') = 'number' then
    v_customer_location := extensions.st_setsrid(extensions.st_makepoint(
      (v_address ->> 'longitude')::double precision,
      (v_address ->> 'latitude')::double precision
    ), 4326);
  end if;
  if v_case.case_type <> 'EXACT_SKU'
    or v_case.status <> 'SEARCHING_EXACT_SKU' then
    v_reasons := pg_catalog.array_append(v_reasons, 'RECOVERY_NOT_SEARCHING');
  end if;
  if v_branch.id is null then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_NOT_FOUND');
  elsif v_branch.id = v_source.branch_id then
    v_reasons := pg_catalog.array_append(v_reasons, 'ORIGINAL_BRANCH_EXCLUDED');
  end if;
  if v_organization.status is distinct from 'ACTIVE'
    or v_organization.merchant_type not in ('RETAIL', 'DASTAK_CONVENIENCE_STORE') then
    v_reasons := pg_catalog.array_append(v_reasons, 'ORGANIZATION_NOT_ELIGIBLE');
  end if;
  if v_branch.status is distinct from 'ACTIVE'
    or v_operating.branch_id is null or not v_operating.is_open
    or not v_operating.accepting_orders then
    v_reasons := pg_catalog.array_append(v_reasons, 'BRANCH_NOT_OPERATING');
  end if;
  if not exists (
    select 1 from dastak_v1.merchant_sku_selections selection
    where selection.branch_id = v_branch.id
      and selection.sku_id = v_line.sku_id and selection.state = 'SELECTED' and (selection.stock_quantity is null or selection.stock_quantity >= v_line.quantity)
  ) then
    v_reasons := pg_catalog.array_append(v_reasons, 'EXACT_SKU_NOT_SELECTED');
  end if;
  select count(*) into v_held from dastak_v1.retail_capacity_slots slot
  where slot.branch_id = v_branch.id and slot.status = 'HELD';
  if v_held >= coalesce(v_branch.capacity_limit, 0) then
    v_reasons := pg_catalog.array_append(v_reasons, 'AT_CAPACITY');
  end if;
  v_radius := dastak_v1_api.required_setting_integer(
    'recovery.radius_meters', v_branch.id, v_branch.organization_id,
    v_branch.service_zone_id
  );
  if v_customer_location is null or v_branch.location is null then
    v_reasons := pg_catalog.array_append(v_reasons, 'LOCATION_MISSING');
  else
    v_distance := extensions.st_distance(
      v_branch.location::extensions.geography,
      v_customer_location::extensions.geography
    );
    if v_distance > v_radius then
      v_reasons := pg_catalog.array_append(v_reasons, 'OUTSIDE_RECOVERY_RADIUS');
    end if;
  end if;
  return pg_catalog.jsonb_build_object(
    'eligible', pg_catalog.cardinality(v_reasons) = 0,
    'reasons', v_reasons,
    'distanceMeters', v_distance,
    'radiusMeters', v_radius,
    'exactSkuId', v_line.sku_id,
    'requestedQuantity', v_line.quantity
  );
end;
$function$;

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
        'stockReservedQuantity', selection.stock_reserved_quantity,
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
