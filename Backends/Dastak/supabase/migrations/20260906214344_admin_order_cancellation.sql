-- Admin cancellation is a terminal, unpaid, pre-custody operation.
alter table dastak_v1.packages drop constraint packages_check;
alter table dastak_v1.packages add constraint packages_check check (
  (status = 'DECLARED' and ready_at is null and picked_up_at is null and delivered_at is null)
  or (status = 'READY' and ready_at is not null and picked_up_at is null and delivered_at is null)
  or (status in ('PICKED_UP', 'IN_TRANSIT') and ready_at is not null and picked_up_at is not null and delivered_at is null)
  or (status = 'DELIVERED' and ready_at is not null and picked_up_at is not null and delivered_at is not null)
  or status in ('RECOVERY', 'RETURN_PENDING', 'RETURNED')
  or (status = 'CANCELLED' and picked_up_at is null and delivered_at is null
    and current_custody_owner_type = 'MERCHANT_BRANCH')
);

insert into dastak_v1.permission_definitions(permission_key, description, sensitivity)
values ('platform.orders.cancel', 'Cancel confirmed unpaid orders before package pickup.', 'HIGHLY_SENSITIVE');
insert into dastak_v1.permission_bundle_permissions(bundle_id, permission_key)
select id, 'platform.orders.cancel' from dastak_v1.permission_bundles
where bundle_key in ('platform_super_admin', 'executive_admin', 'recovery_operations');

create table dastak_v1.order_cancellations (
  order_id uuid primary key references dastak_v1.orders(id),
  actor_id uuid not null references public.accounts(id),
  reason text not null check (char_length(btrim(reason)) between 10 and 500),
  from_status dastak_v1.order_status not null,
  order_version bigint not null,
  cancelled_at timestamptz not null default clock_timestamp()
);
create index order_cancellations_actor_idx on dastak_v1.order_cancellations(actor_id);
alter table dastak_v1.order_cancellations enable row level security;
revoke all on dastak_v1.order_cancellations from public, anon, authenticated;
grant select on dastak_v1.order_cancellations to service_role;

create function dastak_v1.guard_order_cancellation_record()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'order cancellation records are immutable';
end;
$$;
create trigger order_cancellations_immutable before update or delete
on dastak_v1.order_cancellations for each row
execute function dastak_v1.guard_order_cancellation_record();

create function dastak_v1_api.order_cancellation_active(p_order_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(current_setting('dastak_v1.admin_cancellation_order_id', true), '') = p_order_id::text
    and exists (select 1 from dastak_v1.order_cancellations where order_id = p_order_id);
$$;

create function dastak_v1_api.admin_order_cancellation_blocker(p_order_id uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_order dastak_v1.orders%rowtype;
begin
  select * into v_order from dastak_v1.orders where id = p_order_id;
  if not found then return 'Order not found.'; end if;
  if v_order.status not in ('PAID', 'PREPARING', 'PICKUP_IN_PROGRESS') then
    return 'Only confirmed orders before pickup can be cancelled here.';
  end if;
  if v_order.paid_at is not null
    or exists (select 1 from dastak_v1.payments where order_id = p_order_id
      and (status = 'SUCCEEDED' or succeeded_at is not null))
    or exists (select 1 from dastak_v1.launch_payment_collection_attempts
      where order_id = p_order_id and outcome = 'COLLECTED') then
    return 'Payment has been collected. Use the refund and recovery workflow.';
  end if;
  if not exists (select 1 from dastak_v1.launch_payment_commitments where order_id = p_order_id) then
    return 'A confirmed pay-on-delivery commitment is required.';
  end if;
  if exists (select 1 from dastak_v1.packages where order_id = p_order_id
      and (picked_up_at is not null or status not in ('DECLARED', 'READY')
        or current_custody_owner_type <> 'MERCHANT_BRANCH'))
    or exists (select 1 from dastak_v1.package_custody_events where order_id = p_order_id
      and to_owner_type in ('RIDER', 'CUSTOMER'))
    or exists (select 1 from dastak_v1.fulfilments where order_id = p_order_id
      and status in ('PICKED_UP', 'COMPLETED'))
    or exists (select 1 from dastak_v1.delivery_missions where order_id = p_order_id
      and (first_package_picked_up_at is not null
        or status not in ('SEARCHING_RIDER', 'ASSIGNED', 'EN_ROUTE_TO_PICKUPS',
          'PICKUP_IN_PROGRESS', 'REASSIGNING', 'CANCELLED'))) then
    return 'Pickup or delivery has started. Use the recovery workflow.';
  end if;
  if exists (select 1 from dastak_v1.recovery_cases where order_id = p_order_id) then
    return 'This order has a recovery case. Resolve it through the recovery workflow.';
  end if;
  return null;
end;
$$;

-- Every active child write takes the parent lock, preventing stale workers from
-- creating new work after cancellation (including when no mission existed yet).
create function dastak_v1.guard_cancelled_order_work()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_status dastak_v1.order_status;
begin
  select status into v_status from dastak_v1.orders where id = new.order_id for update;
  if v_status = 'CANCELLED' and not (
    dastak_v1_api.order_cancellation_active(new.order_id)
    and tg_op = 'UPDATE'
    and new.status::text in ('CANCELLED', 'RELEASED', 'INVALIDATED', 'REJECTED', 'EXPIRED')
  ) then
    raise exception using errcode = '55000', message = 'ORDER_CANCELLED';
  end if;
  return new;
end;
$$;
do $$
declare v_table text;
begin
  foreach v_table in array array['fulfilments', 'packages', 'delivery_missions', 'order_lines',
    'matching_attempts', 'merchant_opportunities', 'wave2_provisional_holds',
    'fulfilment_plans', 'restaurant_order_requests'] loop
    execute format('create trigger aa_cancelled_order_work before insert or update on dastak_v1.%I for each row execute function dastak_v1.guard_cancelled_order_work()', v_table);
  end loop;
end;
$$;

create function dastak_v1.guard_admin_order_cancellation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'CANCELLED' and old.status is distinct from new.status
    and not dastak_v1_api.order_cancellation_active(new.id) then
    raise exception using errcode = '42501', message = 'audited admin cancellation command required';
  end if;
  return new;
end;
$$;
create trigger orders_admin_cancellation_guard before update on dastak_v1.orders
for each row execute function dastak_v1.guard_admin_order_cancellation();

CREATE OR REPLACE FUNCTION dastak_v1.is_valid_order_transition(p_from dastak_v1.order_status, p_to dastak_v1.order_status)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p_to = 'CANCELLED' then p_from in ('PAID', 'PREPARING', 'PICKUP_IN_PROGRESS') else case p_from
    when 'CREATED' then p_to in ('MATCHING', 'CANCELLED_PREPAYMENT')
    when 'MATCHING' then p_to in ('FULLY_SECURED', 'UNAVAILABLE', 'CANCELLED_PREPAYMENT')
    when 'FULLY_SECURED' then p_to in ('AWAITING_PAYMENT', 'CANCELLED_PREPAYMENT')
    when 'AWAITING_PAYMENT' then p_to in (
      'PAID', 'PREPARING', 'PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT'
    )
    when 'PAID' then p_to in ('PREPARING', 'DASTAK_FULFILMENT_FAILURE')
    when 'PREPARING' then p_to in ('PICKUP_IN_PROGRESS', 'DASTAK_FULFILMENT_FAILURE')
    when 'PICKUP_IN_PROGRESS' then p_to in ('OUT_FOR_DELIVERY', 'DASTAK_FULFILMENT_FAILURE')
    when 'OUT_FOR_DELIVERY' then p_to in ('DELIVERED', 'DASTAK_FULFILMENT_FAILURE')
    else false
  end end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1.is_valid_order_line_transition(p_from dastak_v1.order_line_status, p_to dastak_v1.order_line_status)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p_to = 'CANCELLED' then p_from in ('ORDERED', 'RESERVED', 'FULFILLING') else case p_from
    when 'ORDERED' then p_to = 'RESERVED'
    when 'RESERVED' then p_to = 'FULFILLING'
    when 'FULFILLING' then p_to in ('FULFILLED', 'RECOVERY', 'REFUNDED')
    when 'RECOVERY' then p_to in ('FULFILLING', 'FULFILLED', 'REFUNDED')
    else false
  end end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1.guard_fulfilment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_handoff_id uuid;
  v_exact_recovery_release boolean := coalesce(
    pg_catalog.current_setting('dastak_v1.exact_recovery_release', true), ''
  ) = 'true';
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.source_opportunity_id is distinct from old.source_opportunity_id
    or new.source_recovery_opportunity_id is distinct from old.source_recovery_opportunity_id
    or new.source_restaurant_request_id is distinct from old.source_restaurant_request_id
    or new.fulfilment_type is distinct from old.fulfilment_type
    or new.promised_prep_minutes is distinct from old.promised_prep_minutes
    or new.committed_at is distinct from old.committed_at
    or new.created_at is distinct from old.created_at then
    raise exception 'fulfilment commitment identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'fulfilment version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'RESERVED_PREPAYMENT' and new.status in ('PREPARING', 'RELEASED'))
    or (old.status = 'PREPARING' and new.status = 'READY')
    or (old.status = 'PREPARING' and new.status = 'RELEASED'
      and v_exact_recovery_release)
    or (old.status in ('PREPARING', 'READY') and new.status = 'RELEASED'
      and new.release_reason = 'ADMIN_CANCELLED'
      and dastak_v1_api.order_cancellation_active(new.order_id))
    or (old.status = 'READY' and new.status = 'PICKED_UP')
    or (old.status = 'PICKED_UP' and new.status = 'COMPLETED')
  ) then
    raise exception 'invalid fulfilment transition: % -> %', old.status, new.status;
  end if;
  if old.prep_started_at is not null
    and new.prep_started_at is distinct from old.prep_started_at then
    raise exception 'preparation start cannot be reset';
  end if;
  if old.estimated_ready_at is not null
    and new.estimated_ready_at is distinct from old.estimated_ready_at then
    raise exception 'promised preparation time cannot be extended after payment';
  end if;
  if old.actual_ready_at is not null
    and new.actual_ready_at is distinct from old.actual_ready_at then
    raise exception 'actual Ready timestamp cannot change';
  end if;
  if old.ready_at is not null and new.ready_at is distinct from old.ready_at then
    raise exception 'Ready timestamp cannot change';
  end if;
  if old.package_count is not null
    and new.package_count is distinct from old.package_count then
    raise exception 'declared package count cannot change';
  end if;
  if new.status = 'PREPARING' and (
    new.prep_started_at is null
    or new.estimated_ready_at is null
    or new.estimated_ready_at <> new.prep_started_at
      + pg_catalog.make_interval(mins => new.promised_prep_minutes)
  ) then
    raise exception 'PREPARING fulfilment requires an authoritative preparation clock';
  end if;
  if new.package_count is not null and new.status <> 'PREPARING'
    and old.package_count is null then
    raise exception 'packages can only be declared while Preparing';
  end if;
  if new.status = 'READY' and old.status <> 'READY' and (
    old.status <> 'PREPARING'
    or new.ready_at is null
    or new.actual_ready_at is null
    or new.ready_at is distinct from new.actual_ready_at
    or new.package_count is null
  ) then
    raise exception 'READY requires immutable time, packages and a PREPARING predecessor';
  end if;
  if old.status = 'PREPARING' and new.status = 'RELEASED'
    and not (new.release_reason = 'ADMIN_CANCELLED'
      and new.released_at is not null
      and dastak_v1_api.order_cancellation_active(new.order_id)) and (
    not v_exact_recovery_release
    or new.released_at is null
    or new.release_reason <> 'EXACT_SKU_RECOVERY'
  ) then
    raise exception 'paid fulfilment release requires exact-SKU recovery context';
  end if;
  if old.status = 'READY' and new.status = 'PICKED_UP' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.pickup_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then
      v_handoff_id := null;
    end;
    if v_handoff_id is null
      or not exists (
        select 1 from dastak_v1.verification_handoffs handoff
        where handoff.id = v_handoff_id
          and handoff.fulfilment_id = new.id
          and handoff.status = 'CONSUMED'
      )
      or (
        select count(*) from dastak_v1.packages package
        where package.fulfilment_id = new.id
          and package.status = 'PICKED_UP'
          and package.current_custody_owner_type = 'RIDER'
      ) <> new.package_count then
      raise exception 'fulfilment pickup requires verified custody of every package';
    end if;
  elsif old.status = 'PICKED_UP' and new.status = 'COMPLETED' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.final_delivery_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then
      v_handoff_id := null;
    end;
    if v_handoff_id is null
      or not exists (
        select 1 from dastak_v1.verification_handoffs handoff
        where handoff.id = v_handoff_id
          and handoff.order_id = new.order_id
          and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
          and handoff.status in ('CONSUMED', 'OVERRIDDEN')
      )
      or (
        select count(*)
        from dastak_v1.packages package
        join dastak_v1.orders customer_order on customer_order.id = package.order_id
        where package.fulfilment_id = new.id
          and package.status = 'DELIVERED'
          and package.current_custody_owner_type = 'CUSTOMER'
          and package.current_custody_owner_id = customer_order.customer_id
      ) <> new.package_count then
      raise exception 'fulfilment completion requires verified Customer custody of every package';
    end if;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1.guard_package()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_handoff_id uuid;
  v_return_verification_id uuid;
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.fulfilment_id is distinct from old.fulfilment_id
    or new.package_number is distinct from old.package_number
    or new.declared_by is distinct from old.declared_by
    or new.declared_at is distinct from old.declared_at
    or new.created_at is distinct from old.created_at then
    raise exception 'package declaration identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'package version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status in ('DECLARED', 'READY') and new.status = 'CANCELLED'
      and old.picked_up_at is null
      and dastak_v1_api.order_cancellation_active(new.order_id))
    or (old.status = 'DECLARED' and new.status = 'READY')
    or (old.status = 'READY' and new.status = 'PICKED_UP')
    or (old.status = 'PICKED_UP' and new.status in ('IN_TRANSIT', 'RECOVERY'))
    or (old.status = 'IN_TRANSIT' and new.status in ('DELIVERED', 'RECOVERY'))
    or (old.status = 'DELIVERED' and new.status = 'RETURN_PENDING')
    or (old.status = 'RETURN_PENDING' and new.status in ('RETURNED', 'RECOVERY'))
    or (old.status = 'RECOVERY' and new.status in ('IN_TRANSIT', 'DELIVERED', 'RETURNED'))
  ) then
    raise exception 'invalid package transition: % -> %', old.status, new.status;
  end if;
  if old.status = 'DECLARED' and new.status = 'READY' and (
    new.ready_at is null
    or new.current_custody_owner_type <> 'MERCHANT_BRANCH'
    or new.current_custody_owner_id is distinct from old.current_custody_owner_id
  ) then
    raise exception 'Ready packages remain in declared merchant custody';
  end if;
  if old.status = 'READY' and new.status = 'PICKED_UP' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.pickup_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'MERCHANT_BRANCH'
      or new.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_id is null or new.picked_up_at is null
      or not exists (
        select 1
        from dastak_v1.verification_handoffs handoff
        join dastak_v1.delivery_missions mission on mission.id = handoff.mission_id
        where handoff.id = v_handoff_id
          and handoff.fulfilment_id = new.fulfilment_id
          and handoff.handoff_type = 'MERCHANT_TO_RIDER'
          and handoff.status = 'CONSUMED'
          and handoff.consumed_by = new.current_custody_owner_id
          and mission.assigned_rider_id = new.current_custody_owner_id
      ) then
      raise exception 'package pickup requires consumed verification by the assigned rider';
    end if;
  elsif old.status = 'PICKED_UP' and new.status = 'IN_TRANSIT' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.final_delivery_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_type is distinct from old.current_custody_owner_type
      or new.current_custody_owner_id is distinct from old.current_custody_owner_id
      or not exists (
        select 1
        from dastak_v1.verification_handoffs handoff
        join dastak_v1.delivery_missions mission on mission.id = handoff.mission_id
        where handoff.id = v_handoff_id and handoff.order_id = new.order_id
          and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
          and handoff.status = 'ACTIVE'
          and mission.status = 'ALL_PACKAGES_PICKED_UP'
          and mission.assigned_rider_id = old.current_custody_owner_id
      ) then
      raise exception 'final delivery requires an active parent-order handoff and Rider custody';
    end if;
  elsif old.status = 'IN_TRANSIT' and new.status = 'DELIVERED' then
    begin
      v_handoff_id := nullif(
        pg_catalog.current_setting('dastak_v1.final_delivery_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_type <> 'CUSTOMER'
      or new.delivered_at is null
      or not exists (
        select 1
        from dastak_v1.verification_handoffs handoff
        join dastak_v1.delivery_missions mission on mission.id = handoff.mission_id
        join dastak_v1.orders customer_order on customer_order.id = handoff.order_id
        where handoff.id = v_handoff_id and handoff.order_id = new.order_id
          and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
          and handoff.status in ('CONSUMED', 'OVERRIDDEN')
          and mission.assigned_rider_id = old.current_custody_owner_id
          and customer_order.customer_id = new.current_custody_owner_id
      ) then
      raise exception 'package delivery requires verified Customer custody transfer';
    end if;
  elsif old.status = 'RECOVERY' and new.status = 'RETURNED' then
    begin
      v_return_verification_id := nullif(
        pg_catalog.current_setting('dastak_v1.return_verification_id', true), ''
      )::uuid;
    exception when invalid_text_representation then v_return_verification_id := null;
    end;
    if v_return_verification_id is null
      or old.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_type <> 'MERCHANT_RETURN'
      or not exists (
        select 1
        from dastak_v1.return_verifications verification
        join dastak_v1.return_stops stop on stop.id = verification.return_stop_id
        join dastak_v1.return_packages return_package
          on return_package.return_id = verification.return_id
         and return_package.source_delivery_package_id = new.id
         and return_package.destination_branch_id = stop.branch_id
        join dastak_v1.return_missions return_mission
          on return_mission.id = verification.return_mission_id
        where verification.id = v_return_verification_id
          and verification.handoff_type = 'RETURN_RIDER_TO_MERCHANT'
          and verification.status = 'CONSUMED'
          and return_mission.assigned_rider_id = old.current_custody_owner_id
          and new.current_custody_owner_id = stop.branch_id
      ) then
      raise exception 'recovery return requires consumed merchant receipt verification';
    end if;
  elsif new.current_custody_owner_type is distinct from old.current_custody_owner_type
    or new.current_custody_owner_id is distinct from old.current_custody_owner_id then
    raise exception 'package custody may change only through a verified handoff';
  end if;
  if old.ready_at is not null and new.ready_at is distinct from old.ready_at then
    raise exception 'package Ready timestamp cannot change';
  end if;
  if old.picked_up_at is not null
    and new.picked_up_at is distinct from old.picked_up_at then
    raise exception 'package pickup timestamp cannot change';
  end if;
  if old.delivered_at is not null
    and new.delivered_at is distinct from old.delivered_at then
    raise exception 'package delivery timestamp cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1.guard_delivery_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_recovery_reroute boolean := coalesce(
    pg_catalog.current_setting('dastak_v1.recovery_reroute', true), ''
  ) = 'true';
  v_transport_revalidation boolean := coalesce(
    pg_catalog.current_setting('dastak_v1.transport_revalidation', true), ''
  ) = 'true';
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or (
      new.transport_snapshot is distinct from old.transport_snapshot
      and not v_transport_revalidation
    )
    or new.pickup_count is distinct from old.pickup_count
    or new.search_started_at is distinct from old.search_started_at
    or new.created_at is distinct from old.created_at then
    raise exception 'delivery mission identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'delivery mission version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status in ('SEARCHING_RIDER', 'ASSIGNED', 'EN_ROUTE_TO_PICKUPS',
      'PICKUP_IN_PROGRESS', 'REASSIGNING') and new.status = 'CANCELLED'
      and old.first_package_picked_up_at is null
      and dastak_v1_api.order_cancellation_active(new.order_id))
    or (old.status = 'SEARCHING_RIDER' and new.status in ('ASSIGNED', 'CANCELLED'))
    or (old.status = 'ASSIGNED' and new.status in (
      'EN_ROUTE_TO_PICKUPS', 'REASSIGNING', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'EN_ROUTE_TO_PICKUPS' and new.status in (
      'PICKUP_IN_PROGRESS', 'REASSIGNING', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'PICKUP_IN_PROGRESS' and new.status in (
      'ALL_PACKAGES_PICKED_UP', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'PICKUP_IN_PROGRESS' and new.status = 'REASSIGNING'
      and v_recovery_reroute and old.first_package_picked_up_at is null)
    or (old.status = 'ALL_PACKAGES_PICKED_UP' and new.status in (
      'OUT_FOR_DELIVERY', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'OUT_FOR_DELIVERY' and new.status in ('ARRIVED', 'DELIVERY_RECOVERY'))
    or (old.status = 'ARRIVED' and new.status in ('DELIVERED', 'DELIVERY_RECOVERY'))
    or (old.status = 'REASSIGNING' and new.status = 'SEARCHING_RIDER')
    or (old.status = 'DELIVERY_RECOVERY' and new.status in (
      'PICKUP_IN_PROGRESS', 'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY',
      'ARRIVED', 'DELIVERED', 'RECOVERED_RETURNED'
    ))
  ) then
    raise exception 'invalid delivery mission transition: % -> %', old.status, new.status;
  end if;
  if old.first_package_picked_up_at is not null
    and new.first_package_picked_up_at is distinct from old.first_package_picked_up_at then
    raise exception 'first pickup timestamp cannot change';
  end if;
  if old.all_packages_picked_up_at is not null
    and new.all_packages_picked_up_at is distinct from old.all_packages_picked_up_at then
    raise exception 'all-packages pickup timestamp cannot change';
  end if;
  if old.out_for_delivery_at is not null
    and new.out_for_delivery_at is distinct from old.out_for_delivery_at then
    raise exception 'out-for-delivery timestamp cannot change';
  end if;
  if old.arrived_customer_at is not null
    and new.arrived_customer_at is distinct from old.arrived_customer_at then
    raise exception 'customer-arrival timestamp cannot change';
  end if;
  if old.delivered_at is not null
    and new.delivered_at is distinct from old.delivered_at then
    raise exception 'mission delivery timestamp cannot change';
  end if;
  if new.status = 'OUT_FOR_DELIVERY' and (
    old.status not in ('ALL_PACKAGES_PICKED_UP', 'DELIVERY_RECOVERY')
    or new.all_packages_picked_up_at is null or new.out_for_delivery_at is null
  ) then
    raise exception 'OUT_FOR_DELIVERY requires every pickup and an authoritative timestamp';
  end if;
  if new.status = 'ARRIVED' and (
    old.status not in ('OUT_FOR_DELIVERY', 'DELIVERY_RECOVERY')
    or new.arrived_customer_at is null
  ) then
    raise exception 'ARRIVED requires the final-delivery stage';
  end if;
  if new.status = 'DELIVERED' and (
    old.status not in ('ARRIVED', 'DELIVERY_RECOVERY') or new.delivered_at is null
  ) then
    raise exception 'DELIVERED requires verified or authorized final handoff';
  end if;

  if old.assigned_rider_id is null and new.assigned_rider_id is not null then
    new.rider_last_contact_at := v_now;
    new.rider_last_progress_at := v_now;
    new.stall_detected_at := null;
    new.unresponsive_detected_at := null;
    new.escalation_state := 'NONE';
    new.escalated_at := null;
    new.escalation_reason := null;
    new.escalated_by := null;
  elsif new.assigned_rider_id is not null and new.status is distinct from old.status
    and new.status <> 'DELIVERY_RECOVERY' then
    new.rider_last_progress_at := v_now;
  end if;

  if new.escalation_state is distinct from old.escalation_state and not (
    (old.escalation_state = 'NONE' and new.escalation_state in ('STALLED', 'UNRESPONSIVE'))
    or (old.escalation_state = 'STALLED' and new.escalation_state in ('NONE', 'UNRESPONSIVE'))
    or (old.escalation_state in ('NONE', 'STALLED', 'UNRESPONSIVE')
      and new.escalation_state in ('RELEASED_PRE_CUSTODY', 'DELIVERY_RECOVERY'))
    or (old.assigned_rider_id is null and new.assigned_rider_id is not null
      and new.escalation_state = 'NONE')
  ) then
    raise exception 'invalid rider escalation transition: % -> %',
      old.escalation_state, new.escalation_state;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.release_admin_cancelled_order_resources(p_order_id uuid, p_actor_id uuid, p_target_order_version bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_attempts integer := 0;
  v_opportunities integer := 0;
  v_holds integer := 0;
  v_slots integer := 0;
  v_allocations integer := 0;
  v_fulfilments integer := 0;
  v_response jsonb;
begin
  -- The caller already owns this lock; taking it again documents and enforces
  -- the same global order used by accept and expiry.
  perform customer_order.id
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'order not found';
  end if;

  perform attempt.id
  from dastak_v1.matching_attempts attempt
  where attempt.order_id = p_order_id
  order by attempt.id
  for update;

  perform opportunity.id
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.order_id = p_order_id
  order by opportunity.id
  for update;

  perform branch.id
  from dastak_v1.merchant_branches branch
  where exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    where fulfilment.order_id = p_order_id
      and fulfilment.branch_id = branch.id
  )
  order by branch.id
  for update;

  update dastak_v1.matching_attempts
  set status = 'CANCELLED',
      closed_at = v_now,
      version = version + 1
  where order_id = p_order_id
    and status = 'OPEN';
  get diagnostics v_attempts = row_count;

  update dastak_v1.merchant_opportunities
  set status = 'INVALIDATED',
      version = version + 1
  where order_id = p_order_id
    and status = 'OFFERED';
  get diagnostics v_opportunities = row_count;

  update dastak_v1.inventory_holds hold
  set status = 'RELEASED',
      released_at = v_now,
      release_reason = p_reason,
      version = hold.version + 1
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = hold.fulfilment_id
    and fulfilment.order_id = p_order_id
    and hold.status = 'HELD';
  get diagnostics v_holds = row_count;

  update dastak_v1.retail_capacity_slots slot
  set status = 'RELEASED',
      released_at = v_now,
      release_reason = p_reason,
      version = slot.version + 1
  from dastak_v1.fulfilments fulfilment
  where fulfilment.id = slot.fulfilment_id
    and fulfilment.order_id = p_order_id
    and slot.status = 'HELD';
  get diagnostics v_slots = row_count;

  update dastak_v1.retail_line_allocations allocation
  set status = 'RELEASED',
      version = allocation.version + 1
  from dastak_v1.order_lines order_line
  where order_line.id = allocation.order_line_id
    and order_line.order_id = p_order_id
    and allocation.status in ('PROVISIONAL', 'SELECTED');
  get diagnostics v_allocations = row_count;

  update dastak_v1.fulfilments fulfilment
  set status = 'RELEASED',
      released_at = v_now,
      release_reason = p_reason,
      version = fulfilment.version + 1
  where fulfilment.order_id = p_order_id
    and fulfilment.status in ('RESERVED_PREPAYMENT', 'PREPARING', 'READY');
  get diagnostics v_fulfilments = row_count;

  v_response := pg_catalog.jsonb_build_object(
    'attemptsCancelled', v_attempts,
    'opportunitiesInvalidated', v_opportunities,
    'inventoryHoldsReleased', v_holds,
    'capacitySlotsReleased', v_slots,
    'allocationsReleased', v_allocations,
    'fulfilmentsReleased', v_fulfilments,
    'releasedAt', v_now,
    'reason', p_reason
  );

  if v_attempts + v_opportunities + v_holds + v_slots
    + v_allocations + v_fulfilments > 0 then
    insert into dastak_v1.domain_events_outbox (
      event_key,
      aggregate_type,
      aggregate_id,
      aggregate_version,
      event_type,
      actor_id,
      payload
    ) values (
      p_order_id::text || ':ORDER_CANCELLATION_RESOURCES_RELEASED:'
        || p_target_order_version::text,
      'ORDER',
      p_order_id,
      p_target_order_version,
      'ORDER_CANCELLATION_RESOURCES_RELEASED',
      p_actor_id,
      pg_catalog.jsonb_build_object('orderId', p_order_id) || v_response
    );

    insert into dastak_v1.audit_events (
      actor_id, action, resource_type, resource_id, metadata
    ) values (
      p_actor_id,
      'ORDER_CANCELLATION_RESOURCES_RELEASED',
      'order',
      p_order_id,
      v_response
    );
  end if;

  return v_response;
end;
$function$;


create function dastak_v1_api.admin_cancel_order(
  p_actor_id uuid, p_order_id uuid, p_reason text,
  p_expected_version bigint, p_idempotency_key text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_order dastak_v1.orders%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_blocker text;
  v_now timestamptz := clock_timestamp();
  v_release jsonb;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.orders.cancel');
  if p_reason is null or char_length(btrim(p_reason)) not between 10 and 500
    or p_expected_version is null or p_expected_version < 1
    or p_idempotency_key is null or char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'Valid reason, version and idempotency key required.';
  end if;
  v_hash := dastak_v1_api.request_hash(jsonb_build_object(
    'orderId', p_order_id, 'reason', btrim(p_reason), 'expectedVersion', p_expected_version));
  perform pg_advisory_xact_lock(hashtextextended(
    p_actor_id::text || ':adminCancelOrder:' || p_idempotency_key, 0));
  select * into v_existing from dastak_v1.idempotency_records
  where actor_id = p_actor_id and command_name = 'adminCancelOrder'
    and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;
  -- Parent first matches merchant/stock commands. Conflicting legacy mission-first
  -- commands can deadlock and roll back, but can never partially cancel an order.
  select * into v_order from dastak_v1.orders where id = p_order_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'order not found'; end if;
  if v_order.version is distinct from p_expected_version then
    raise exception using errcode = '40001', message = 'stale order version';
  end if;
  perform id from dastak_v1.delivery_missions where order_id = p_order_id order by id for update;
  perform id from dastak_v1.fulfilments where order_id = p_order_id order by id for update;
  perform id from dastak_v1.packages where order_id = p_order_id order by id for update;
  perform id from dastak_v1.payments where order_id = p_order_id order by id for update;
  perform id from dastak_v1.launch_payment_commitments where order_id = p_order_id for update;
  v_blocker := dastak_v1_api.admin_order_cancellation_blocker(p_order_id);
  if v_blocker is not null then raise exception using errcode = '55000', message = v_blocker; end if;
  insert into dastak_v1.order_cancellations(order_id, actor_id, reason, from_status, order_version, cancelled_at)
  values (p_order_id, p_actor_id, btrim(p_reason), v_order.status, v_order.version + 1, v_now);
  perform set_config('dastak_v1.admin_cancellation_order_id', p_order_id::text, true);
  update dastak_v1.orders set status = 'CANCELLED', version = version + 1 where id = p_order_id;
  v_release := dastak_v1_api.release_admin_cancelled_order_resources(
    p_order_id, p_actor_id, v_order.version + 1, 'ADMIN_CANCELLED');
  update dastak_v1.wave2_provisional_holds
  set status = 'RELEASED', released_at = v_now, release_reason = 'ADMIN_CANCELLED', version = version + 1
  where order_id = p_order_id and status = 'HELD';
  update dastak_v1.merchant_opportunities
  set status = 'RELEASED', version = version + 1
  where order_id = p_order_id and wave = 'WAVE_2' and status = 'PROVISIONALLY_ACCEPTED';
  update dastak_v1.fulfilment_plans
  set status = 'REJECTED', rejected_at = v_now, rejection_reason = 'ADMIN_CANCELLED', version = version + 1
  where order_id = p_order_id and status = 'CANDIDATE';
  update dastak_v1.restaurant_capacity_commitments
  set status = 'RELEASED', released_at = v_now, release_reason = 'ADMIN_CANCELLED', version = version + 1
  where order_id = p_order_id and status = 'COMMITTED';
  update dastak_v1.restaurant_order_requests
  set status = 'RELEASED', version = version + 1
  where order_id = p_order_id and status in ('OFFERED', 'CONFIRMED');
  update dastak_v1.payment_attempts
  set status = 'EXPIRED', expired_at = v_now, version = version + 1
  where order_id = p_order_id and status in ('CREATED', 'PROVIDER_READY');
  update dastak_v1.payments
  set status = 'CANCELLED', cancelled_at = v_now, version = version + 1
  where order_id = p_order_id and status = 'RESERVED';
  update dastak_v1.packages set status = 'CANCELLED', version = version + 1
  where order_id = p_order_id and status in ('DECLARED', 'READY');
  update dastak_v1.order_lines set status = 'CANCELLED', version = version + 1
  where order_id = p_order_id and status in ('ORDERED', 'RESERVED', 'FULFILLING');
  update dastak_v1.delivery_offers
  set status = 'CLOSED', responded_at = coalesce(responded_at, v_now),
    closed_reason = 'ADMIN_CANCELLED', version = version + 1
  where mission_id in (select id from dastak_v1.delivery_missions where order_id = p_order_id)
    and status = 'OFFERED';
  -- Preserve the assigned rider as historical identity and notification recipient.
  update dastak_v1.delivery_missions
  set status = 'CANCELLED', cancelled_at = v_now, cancellation_reason = 'ADMIN_CANCELLED', version = version + 1
  where order_id = p_order_id and status <> 'CANCELLED';
  insert into dastak_v1.order_state_journal(
    order_id, from_status, to_status, order_version, command_name, actor_id, reason, metadata
  ) values (p_order_id, v_order.status, 'CANCELLED', v_order.version + 1,
    'adminCancelOrder', p_actor_id, btrim(p_reason), jsonb_build_object('resourceRelease', v_release));
  insert into dastak_v1.domain_events_outbox(
    event_key, aggregate_type, aggregate_id, aggregate_version, event_type, actor_id, payload
  ) values (p_order_id::text || ':ORDER_CANCELLED:' || (v_order.version + 1)::text,
    'ORDER', p_order_id, v_order.version + 1, 'ORDER_CANCELLED', p_actor_id,
    jsonb_build_object('orderId', p_order_id, 'customerId', v_order.customer_id,
      'status', 'CANCELLED', 'version', v_order.version + 1, 'resourceRelease', v_release));
  insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
  values (p_actor_id, 'ORDER_CANCELLED', 'order', p_order_id,
    jsonb_build_object('reason', btrim(p_reason), 'fromStatus', v_order.status,
      'idempotencyKey', p_idempotency_key, 'resourceRelease', v_release));
  v_response := jsonb_build_object('orderId', p_order_id, 'status', 'CANCELLED',
    'version', v_order.version + 1, 'cancelledAt', v_now, 'resourceRelease', v_release);
  insert into dastak_v1.idempotency_records(actor_id, command_name, idempotency_key,
    request_hash, response_body, response_status, resource_id)
  values(p_actor_id, 'adminCancelOrder', p_idempotency_key, v_hash, v_response, 200, p_order_id);
  perform set_config('dastak_v1.admin_cancellation_order_id', '', true);
  return v_response;
end;
$$;

create function public.dastak_v1_admin_cancel_order(
  p_order_id uuid, p_reason text, p_expected_version bigint, p_idempotency_key text
)
returns jsonb language sql security invoker set search_path = '' as $$
  select dastak_v1_api.admin_cancel_order(auth.uid(), p_order_id, p_reason, p_expected_version, p_idempotency_key);
$$;

CREATE OR REPLACE FUNCTION dastak_v1_api.launch_payment_customer_json(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order dastak_v1.orders%rowtype;
  v_payment dastak_v1.payments%rowtype;
  v_commitment dastak_v1.launch_payment_commitments%rowtype;
  v_latest dastak_v1.launch_payment_collection_attempts%rowtype;
  v_state text;
begin
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id;
  if v_order.id is null then return null; end if;

  select payment.* into v_payment
  from dastak_v1.payments payment
  where payment.order_id = p_order_id;
  select commitment.* into v_commitment
  from dastak_v1.launch_payment_commitments commitment
  where commitment.order_id = p_order_id;
  if v_commitment.id is not null then
    select attempt.* into v_latest
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.commitment_id = v_commitment.id
    order by attempt.attempted_at desc, attempt.id desc
    limit 1;
  end if;

  v_state := case
    when v_order.status = 'CANCELLED' then 'NOT_APPLICABLE'
    when v_commitment.id is null and v_order.status = 'AWAITING_PAYMENT'
      and v_payment.status = 'RESERVED'
      and v_payment.expires_at > pg_catalog.statement_timestamp()
      then 'READY_TO_CONFIRM'
    when v_commitment.id is null and v_order.status in ('PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT')
      then 'RESERVATION_EXPIRED'
    when v_latest.outcome = 'COLLECTED' then 'PAYMENT_COLLECTED'
    when v_latest.outcome = 'FAILED' then 'COLLECTION_RETRY_NEEDED'
    when v_commitment.id is not null then 'PAYMENT_DUE_AT_DELIVERY'
    else 'NOT_APPLICABLE'
  end;

  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'optionLabel', 'Pay via UPI/Cash on Delivery',
    'state', v_state,
    'amountPaise', coalesce(v_commitment.amount_paise, v_payment.amount_paise),
    'currencyCode', coalesce(v_commitment.currency_code, v_payment.currency_code),
    'securedAt', coalesce(v_commitment.secured_at, v_order.fully_secured_at),
    'reservationExpiresAt', coalesce(v_commitment.reservation_expires_at, v_payment.expires_at),
    'reservationSecondsRemaining', case when v_commitment.id is null then
      greatest(0::numeric, pg_catalog.floor(extract(
        epoch from (v_payment.expires_at - pg_catalog.statement_timestamp())
      )))::bigint else 0 end,
    'reservationState', case
      when v_commitment.id is not null then 'COMMITTED'
      when v_payment.status = 'RESERVED' and v_payment.expires_at > pg_catalog.statement_timestamp()
        then 'ACTIVE'
      else 'EXPIRED'
    end,
    'committedAt', v_commitment.committed_at,
    'collectedAt', v_latest.collected_at,
    'collectionMethod', case when v_latest.outcome = 'COLLECTED' then v_latest.method end,
    'canCommit', v_commitment.id is null
      and v_order.status = 'AWAITING_PAYMENT'
      and v_payment.status = 'RESERVED'
      and v_payment.expires_at > pg_catalog.statement_timestamp(),
    'noChargeNow', v_commitment.id is null,
    'payAtDoorstep', v_order.status <> 'CANCELLED'
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.launch_payment_admin_json(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select pg_catalog.jsonb_build_object(
    'commitment', case when commitment.id is null then null else
      pg_catalog.jsonb_build_object(
        'id', commitment.id,
        'optionCode', commitment.option_code,
        'customerId', commitment.customer_id,
        'retiredPaymentId', commitment.retired_payment_id,
        'amountPaise', commitment.amount_paise,
        'currencyCode', commitment.currency_code,
        'securedAt', commitment.secured_at,
        'reservationExpiresAt', commitment.reservation_expires_at,
        'committedAt', commitment.committed_at,
        'version', commitment.version
      ) end,
    'collectionStatus', case
      when exists (select 1 from dastak_v1.orders where id = p_order_id and status = 'CANCELLED') then 'NOT_APPLICABLE'
      when collected.id is not null then 'COLLECTED'
      when commitment.id is not null and failed.id is not null then 'RETRY_NEEDED'
      when commitment.id is not null then 'DUE'
      else 'NOT_APPLICABLE'
    end,
    'attempts', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_strip_nulls(
        pg_catalog.jsonb_build_object(
          'id', attempt.id,
          'outcome', attempt.outcome,
          'method', attempt.method,
          'riderId', attempt.rider_id,
          'missionId', attempt.mission_id,
          'reference', attempt.collection_reference,
          'reason', attempt.failure_reason,
          'attemptedAt', attempt.attempted_at,
          'collectedAt', attempt.collected_at
        )
      ) order by attempt.attempted_at, attempt.id)
      from dastak_v1.launch_payment_collection_attempts attempt
      where attempt.order_id = p_order_id
    ), '[]'::jsonb),
    'platformFee', (
      select pg_catalog.jsonb_build_object(
        'transactionId', transaction.id,
        'amountPaise', transaction.amount_paise,
        'currencyCode', transaction.currency_code,
        'postedAt', transaction.created_at,
        'balanced', (
          select pg_catalog.count(*) = 2
            and coalesce(pg_catalog.sum(case when line.direction = 'DEBIT'
              then line.amount_paise else -line.amount_paise end), 0) = 0
          from dastak_v1.financial_journal_lines line
          where line.transaction_id = transaction.id
        )
      )
      from dastak_v1.financial_journal_transactions transaction
      where transaction.transaction_key = p_order_id::text || ':PLATFORM_FEE'
    )
  )
  from (select 1) seed
  left join dastak_v1.launch_payment_commitments commitment
    on commitment.order_id = p_order_id
  left join lateral (
    select attempt.id
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.order_id = p_order_id and attempt.outcome = 'COLLECTED'
    limit 1
  ) collected on true
  left join lateral (
    select attempt.id
    from dastak_v1.launch_payment_collection_attempts attempt
    where attempt.order_id = p_order_id and attempt.outcome = 'FAILED'
    order by attempt.attempted_at desc, attempt.id desc
    limit 1
  ) failed on true;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.admin_execution_trace(p_actor_id uuid, p_order_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select dastak_v1_api.admin_execution_trace_pre_launch_payment(
    p_actor_id, p_order_id
  ) || pg_catalog.jsonb_build_object(
    'launchPayment', dastak_v1_api.launch_payment_admin_json(p_order_id),
    'cancellation', jsonb_build_object(
      'canCancel', dastak_v1_api.actor_has_platform_permission(p_actor_id, 'platform.orders.cancel')
        and dastak_v1_api.admin_order_cancellation_blocker(p_order_id) is null,
      'blocker', dastak_v1_api.admin_order_cancellation_blocker(p_order_id),
      'record', (select jsonb_build_object('reason', reason, 'cancelledAt', cancelled_at,
        'actorId', actor_id) from dastak_v1.order_cancellations where order_id = p_order_id)
    )
  );
$function$;


revoke all on function dastak_v1.guard_order_cancellation_record(),
  dastak_v1.guard_cancelled_order_work(), dastak_v1.guard_admin_order_cancellation(),
  dastak_v1_api.order_cancellation_active(uuid),
  dastak_v1_api.admin_order_cancellation_blocker(uuid),
  dastak_v1_api.release_admin_cancelled_order_resources(uuid,uuid,bigint,text)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.admin_cancel_order(uuid,uuid,text,bigint,text),
  public.dastak_v1_admin_cancel_order(uuid,text,bigint,text) from public, anon;
grant execute on function dastak_v1_api.admin_cancel_order(uuid,uuid,text,bigint,text),
  public.dastak_v1_admin_cancel_order(uuid,text,bigint,text) to authenticated, service_role;

insert into dastak_v1.notification_routes(event_type, audience, notification_type, title, body) values
('ORDER_CANCELLED', 'CUSTOMER', 'customer.order_cancelled', 'Order cancelled', 'Your order was cancelled. No payment is due.'),
('ORDER_CANCELLED', 'MERCHANT', 'merchant.order_cancelled', 'Order cancelled', 'Stop preparation for this order. Reserved stock and capacity have been released.'),
('ORDER_CANCELLED', 'RIDER', 'rider.order_cancelled', 'Order cancelled', 'This order was cancelled. Do not collect its packages.');

-- Terminal cancellation must disappear from active counters and merchant promises.
CREATE OR REPLACE FUNCTION dastak_v1_api.admin_command_center(p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.orders.trace'
  );

  return pg_catalog.jsonb_build_object(
    'observedAt', pg_catalog.statement_timestamp(),
    'actionQueue', pg_catalog.jsonb_build_object(
      'merchantApplications', (
        select pg_catalog.count(*)
        from private.merchant_applications application
        where application.status = 'pending'
      ),
      'deliveryApplications', (
        select pg_catalog.count(*)
        from private.delivery_partner_applications application
        where application.status = 'pending'
      ),
      'openIncidents', (
        select pg_catalog.count(*)
        from dastak_v1.invariant_incidents incident
        where incident.status = 'OPEN'
      ),
      'riderEscalations', (
        select pg_catalog.count(*)
        from dastak_v1.delivery_missions mission
        where mission.escalation_state <> 'NONE'
          and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
      ),
      'activePauses', (
        select pg_catalog.count(*)
        from dastak_v1.operational_pause_controls control
        where control.active
      )
    ),
    'identities', pg_catalog.jsonb_build_object(
      'activeAccounts', (
        select pg_catalog.count(*) from public.accounts account
        where account.account_state = 'ACTIVE'
      ),
      'customers', (
        select pg_catalog.count(*) from private.account_personas persona
        where persona.persona = 'CUSTOMER' and persona.state = 'ACTIVE'
      ),
      'merchants', (
        select pg_catalog.count(*) from private.account_personas persona
        where persona.persona = 'MERCHANT' and persona.state = 'ACTIVE'
      ),
      'deliveryPartners', (
        select pg_catalog.count(*) from private.account_personas persona
        where persona.persona = 'DELIVERY' and persona.state = 'ACTIVE'
      ),
      'deletedPersonas', (
        select pg_catalog.count(*) from private.account_personas persona
        where persona.state = 'DELETED'
      ),
      'recoveryEligiblePhones', (
        select pg_catalog.count(*) from private.account_phone_claims claim
        where claim.claim_state = 'RECOVERY_ELIGIBLE'
      )
    ),
    'commerce', pg_catalog.jsonb_build_object(
      'activeOrders', (
        select pg_catalog.count(*) from dastak_v1.orders customer_order
        where customer_order.status not in (
          'DELIVERED', 'UNAVAILABLE', 'PAYMENT_EXPIRED',
          'CANCELLED_PREPAYMENT', 'CANCELLED', 'DASTAK_FULFILMENT_FAILURE'
        )
      ),
      'awaitingPayment', (
        select pg_catalog.count(*) from dastak_v1.orders customer_order
        where customer_order.status = 'AWAITING_PAYMENT'
      ),
      'preparingFulfilments', (
        select pg_catalog.count(*) from dastak_v1.fulfilments fulfilment
        where fulfilment.status = 'PREPARING'
      ),
      'readyFulfilments', (
        select pg_catalog.count(*) from dastak_v1.fulfilments fulfilment
        where fulfilment.status = 'READY'
      ),
      'activeMissions', (
        select pg_catalog.count(*) from dastak_v1.delivery_missions mission
        where mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
      ),
      'deliveredToday', (
        select pg_catalog.count(*) from dastak_v1.orders customer_order
        where customer_order.status = 'DELIVERED'
          and customer_order.delivered_at >= pg_catalog.date_trunc(
            'day', pg_catalog.statement_timestamp()
          )
      )
    ),
    'network', pg_catalog.jsonb_build_object(
      'activeOrganizations', (
        select pg_catalog.count(*) from dastak_v1.merchant_organizations organization
        where organization.status = 'ACTIVE'
      ),
      'activeBranches', (
        select pg_catalog.count(*) from dastak_v1.merchant_branches branch
        where branch.status = 'ACTIVE'
      ),
      'onlineRiders', (
        select pg_catalog.count(*) from private.delivery_partner_availability availability
        where availability.status = 'online'
          and (
            availability.available_until is null
            or availability.available_until > pg_catalog.statement_timestamp()
          )
      ),
      'assignedRiders', (
        select pg_catalog.count(distinct mission.assigned_rider_id)
        from dastak_v1.delivery_missions mission
        where mission.assigned_rider_id is not null
          and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
      )
    ),
    'catalogue', pg_catalog.jsonb_build_object(
      'total', (select pg_catalog.count(*) from dastak_v1.skus),
      'active', (
        select pg_catalog.count(*) from dastak_v1.skus sku
        where sku.status = 'ACTIVE'
      ),
      'draft', (
        select pg_catalog.count(*) from dastak_v1.skus sku
        where sku.status = 'DRAFT'
      ),
      'needsReview', (
        select pg_catalog.count(*) from dastak_v1.skus sku
        where sku.qa_status in ('PENDING', 'NEEDS_REVIEW')
      ),
      'missingPrimaryImage', (
        select pg_catalog.count(*)
        from dastak_v1.skus sku
        where not exists (
          select 1 from dastak_v1.sku_images image
          where image.sku_id = sku.id and image.role = 'PRIMARY'
            and image.status <> 'REJECTED'
        )
      )
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.admin_network_page(p_actor_id uuid, p_query text DEFAULT NULL::text, p_persona text DEFAULT NULL::text, p_state text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_after_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_after_account_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_query text := nullif(pg_catalog.btrim(coalesce(p_query, '')), '');
  v_persona text := nullif(pg_catalog.upper(pg_catalog.btrim(coalesce(p_persona, ''))), '');
  v_state text := nullif(pg_catalog.upper(pg_catalog.btrim(coalesce(p_state, ''))), '');
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_people jsonb;
  v_has_more boolean;
  v_next_cursor jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.orders.trace'
  );

  if v_query is not null and pg_catalog.char_length(v_query) > 80 then
    raise exception using errcode = '22023', message = 'network search is too long';
  end if;
  if v_persona is not null
    and v_persona not in ('CUSTOMER', 'MERCHANT', 'DELIVERY', 'ADMIN') then
    raise exception using errcode = '22023', message = 'invalid persona filter';
  end if;
  if v_state is not null and v_state not in ('ACTIVE', 'DELETED') then
    raise exception using errcode = '22023', message = 'invalid persona state filter';
  end if;
  if (p_after_updated_at is null) <> (p_after_account_id is null) then
    raise exception using errcode = '22023', message = 'complete network cursor required';
  end if;

  with matched as materialized (
    select
      account.id,
      account.display_name,
      account.phone_number,
      account.phone_verification_state,
      account.account_state,
      account.created_at,
      account.updated_at,
      auth_user.email,
      auth_user.last_sign_in_at,
      assignment.role as admin_role
    from public.accounts account
    left join auth.users auth_user on auth_user.id = account.id
    left join dastak_v1.admin_role_assignments assignment
      on assignment.account_id = account.id
    where (
      v_query is null
      or account.display_name ilike '%' || v_query || '%'
      or account.phone_number ilike '%' || v_query || '%'
      or auth_user.email ilike '%' || v_query || '%'
    )
      and (
        v_persona is null
        or (v_persona = 'ADMIN' and assignment.account_id is not null)
        or (v_persona <> 'ADMIN' and exists (
          select 1 from private.account_personas persona
          where persona.account_id = account.id
            and persona.persona::text = v_persona
        ))
      )
      and (
        v_state is null
        or (
          v_persona is null
          and account.account_state::text = v_state
        )
        or (
          v_persona = 'ADMIN'
          and v_state = 'ACTIVE'
          and assignment.account_id is not null
        )
        or (
          v_persona not in ('ADMIN')
          and exists (
            select 1 from private.account_personas persona
            where persona.account_id = account.id
              and persona.persona::text = v_persona
              and persona.state::text = v_state
          )
        )
      )
      and (
        p_after_updated_at is null
        or (account.updated_at, account.id) < (p_after_updated_at, p_after_account_id)
      )
    order by account.updated_at desc, account.id desc
    limit v_limit + 1
  ), selected as (
    select * from matched
    order by updated_at desc, id desc
    limit v_limit
  )
  select
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', person.id,
          'displayName', person.display_name,
          'email', person.email,
          'phoneNumber', person.phone_number,
          'phoneVerified', person.phone_verification_state = 'verified',
          'accountState', person.account_state,
          'adminRole', person.admin_role,
          'createdAt', person.created_at,
          'updatedAt', person.updated_at,
          'lastSignInAt', person.last_sign_in_at,
          'personas', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
              'persona', persona.persona,
              'state', persona.state,
              'activatedAt', persona.activated_at,
              'deletedAt', persona.deleted_at,
              'version', persona.version
            ) order by persona.persona)
            from private.account_personas persona
            where persona.account_id = person.id
          ), '[]'::jsonb),
          'customer', pg_catalog.jsonb_build_object(
            'orderCount', (
              select pg_catalog.count(*) from dastak_v1.orders customer_order
              where customer_order.customer_id = person.id
            ),
            'activeOrderCount', (
              select pg_catalog.count(*) from dastak_v1.orders customer_order
              where customer_order.customer_id = person.id
                and customer_order.status not in (
                  'DELIVERED', 'UNAVAILABLE', 'PAYMENT_EXPIRED',
                  'CANCELLED_PREPAYMENT', 'CANCELLED', 'DASTAK_FULFILMENT_FAILURE'
                )
            )
          ),
          'merchant', (
            select pg_catalog.jsonb_build_object(
              'applicationStatus', application.status,
              'businessName', application.business_name,
              'submittedAt', application.submitted_at,
              'reviewedAt', application.reviewed_at,
              'organizationName', organization.display_name,
              'organizationStatus', organization.status,
              'branchCount', (
                select pg_catalog.count(*) from dastak_v1.merchant_branches branch
                where branch.organization_id = organization.id
              )
            )
            from private.merchant_applications application
            left join dastak_v1.merchant_users merchant_user
              on merchant_user.account_id = application.account_id
            left join dastak_v1.merchant_organizations organization
              on organization.id = merchant_user.organization_id
            where application.account_id = person.id
            order by application.updated_at desc, application.id desc
            limit 1
          ),
          'delivery', (
            select pg_catalog.jsonb_build_object(
              'applicationStatus', application.status,
              'deliveryMethod', application.delivery_method,
              'submittedAt', application.submitted_at,
              'reviewedAt', application.reviewed_at,
              'availability', availability.status,
              'lastSeenAt', availability.last_seen_at,
              'activeMissionCount', (
                select pg_catalog.count(*) from dastak_v1.delivery_missions mission
                where mission.assigned_rider_id = application.account_id
                  and mission.status not in ('DELIVERED', 'CANCELLED', 'RECOVERED_RETURNED')
              )
            )
            from private.delivery_partner_applications application
            left join private.delivery_partner_availability availability
              on availability.account_id = application.account_id
            where application.account_id = person.id
            order by application.updated_at desc, application.id desc
            limit 1
          )
        ) order by person.updated_at desc, person.id desc
      ) from selected person
    ), '[]'::jsonb),
    (select pg_catalog.count(*) > v_limit from matched),
    case when (select pg_catalog.count(*) > v_limit from matched) then (
      select pg_catalog.jsonb_build_object(
        'updatedAt', person.updated_at, 'accountId', person.id
      )
      from selected person
      order by person.updated_at, person.id
      limit 1
    ) else null end
  into v_people, v_has_more, v_next_cursor;

  return pg_catalog.jsonb_build_object(
    'people', v_people,
    'hasMore', v_has_more,
    'nextCursor', v_next_cursor
  );
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.merchant_opportunity_json_step2(p_actor_id uuid, p_opportunity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_opportunity dastak_v1.merchant_opportunities%rowtype;
  v_branch dastak_v1.merchant_branches%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_hold_expires_at timestamptz;
  v_capacity_consumed boolean;
begin
  select opportunity.* into v_opportunity
  from dastak_v1.merchant_opportunities opportunity
  where opportunity.id = p_opportunity_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'opportunity not found';
  end if;

  if not dastak_v1_api.actor_has_wave1_merchant_permission(
    p_actor_id,
    v_opportunity.organization_id,
    'merchant.opportunities.respond',
    v_opportunity.branch_id
  ) then
    raise exception using errcode = 'P0002', message = 'opportunity not found';
  end if;

  select branch.* into v_branch
  from dastak_v1.merchant_branches branch
  where branch.id = v_opportunity.branch_id;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_opportunity.order_id;

  select max(hold.expires_at) into v_hold_expires_at
  from dastak_v1.wave2_provisional_holds hold
  where hold.opportunity_id = v_opportunity.id
    and hold.status = 'HELD';

  select exists (
    select 1
    from dastak_v1.fulfilments fulfilment
    join dastak_v1.retail_capacity_slots slot
      on slot.fulfilment_id = fulfilment.id
      and slot.status = 'HELD'
    where fulfilment.source_opportunity_id = v_opportunity.id
      and fulfilment.status = 'RESERVED_PREPAYMENT'
  ) into v_capacity_consumed;

  return pg_catalog.jsonb_build_object(
    'id', v_opportunity.id,
    'displayOrderNumber', v_order.display_order_number,
    'requestScope', case v_opportunity.wave
      when 'WAVE_1' then 'FULL_BASKET'
      else 'REQUESTED_SUBSET'
    end,
    'status', v_opportunity.status,
    'reservationState', case
      when v_opportunity.status = 'PROVISIONALLY_ACCEPTED' then 'ITEMS_HELD_WHILE_ORDER_COMPLETES'
      when v_opportunity.status = 'SELECTED' and v_order.status = 'AWAITING_PAYMENT'
        then 'WAITING_FOR_CUSTOMER_PAYMENT'
      when v_opportunity.status = 'SELECTED' and v_order.status = 'PAID'
        then 'PAYMENT_CONFIRMED'
      when v_opportunity.status in ('RELEASED', 'EXPIRED', 'LOST', 'INVALIDATED')
        or v_order.status in ('PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT', 'CANCELLED', 'UNAVAILABLE')
        then 'RESERVATION_RELEASED'
      else 'AWAITING_RESPONSE'
    end,
    'version', v_opportunity.version,
    'branch', pg_catalog.jsonb_build_object(
      'id', v_branch.id,
      'displayName', v_branch.display_name
    ),
    'startedAt', v_opportunity.started_at,
    'expiresAt', v_opportunity.expires_at,
    'secondsRemaining', greatest(
      0,
      pg_catalog.floor(
        extract(epoch from (v_opportunity.expires_at - pg_catalog.statement_timestamp()))
      )::integer
    ),
    'provisionalHoldExpiresAt', v_hold_expires_at,
    'promisedPrepMinutes', v_opportunity.promised_prep_minutes,
    'prepTimeOptionsMinutes', dastak_v1_api.retail_prep_options(
      v_branch.id, v_branch.organization_id, v_branch.service_zone_id
    ),
    'physicalConfirmationRequired', v_opportunity.status = 'OFFERED',
    'capacityConsumed', v_capacity_consumed,
    'orderPaymentState', case v_order.status
      when 'AWAITING_PAYMENT' then 'WAITING_FOR_CUSTOMER_PAYMENT'
      when 'PAID' then 'PAID'
      when 'PAYMENT_EXPIRED' then 'PAYMENT_EXPIRED'
      when 'CANCELLED_PREPAYMENT' then 'CANCELLED'
      when 'CANCELLED' then 'CANCELLED'
      else null
    end,
    'lines', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
            'orderLineId', opportunity_line.order_line_id,
            'skuId', opportunity_line.sku_id,
            'name', opportunity_line.product_name_snapshot,
            'variant', opportunity_line.variant_snapshot,
            'packSize', opportunity_line.pack_size_snapshot,
            'quantity', opportunity_line.requested_quantity
          ))
          order by opportunity_line.created_at, opportunity_line.order_line_id
        )
        from dastak_v1.merchant_opportunity_lines opportunity_line
        where opportunity_line.opportunity_id = v_opportunity.id
      ),
      '[]'::jsonb
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION dastak_v1_api.run_invariant_monitors(p_worker_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_run_id uuid;
  v_started_at timestamptz := pg_catalog.clock_timestamp();
  v_now timestamptz;
  v_finding record;
  v_finding_rows jsonb;
  v_findings integer := 0;
  v_open integer;
begin
  if nullif(pg_catalog.btrim(p_worker_id), '') is null then
    raise exception using errcode = '22023', message = 'worker id required';
  end if;
  with finding_rows (invariant_key, entity_type, entity_id, details) as (
  select 'ORDER_MULTIPLE_ACTIVE_MISSIONS', 'ORDER', mission.order_id,
    pg_catalog.jsonb_build_object('activeMissionCount', pg_catalog.count(*))
  from dastak_v1.delivery_missions mission
  where mission.status not in ('DELIVERED', 'CANCELLED')
  group by mission.order_id having pg_catalog.count(*) > 1

  union all
  select 'RIDER_MULTIPLE_ACTIVE_MISSIONS', 'RIDER', mission.assigned_rider_id,
    pg_catalog.jsonb_build_object('activeMissionCount', pg_catalog.count(*))
  from dastak_v1.delivery_missions mission
  where mission.assigned_rider_id is not null
    and mission.status in (
      'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
      'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY', 'ARRIVED',
      'DELIVERY_RECOVERY'
    )
  group by mission.assigned_rider_id having pg_catalog.count(*) > 1

  union all
  select 'RETAIL_LINE_MULTIPLE_FINAL_MERCHANTS', 'ORDER_LINE', line.id,
    pg_catalog.jsonb_build_object(
      'activeMerchantCount', pg_catalog.count(distinct fulfilment.branch_id)
    )
  from dastak_v1.order_lines line
  join dastak_v1.fulfilment_lines fulfilment_line
    on fulfilment_line.order_line_id = line.id
  join dastak_v1.fulfilments fulfilment
    on fulfilment.id = fulfilment_line.fulfilment_id
  where line.line_type = 'RETAIL_SKU'
    and fulfilment.status <> 'RELEASED'
  group by line.id
  having pg_catalog.count(distinct fulfilment.branch_id) > 1

  union all
  select 'RETAIL_HARD_CAPACITY_EXCEEDED', 'MERCHANT_BRANCH', branch.id,
    pg_catalog.jsonb_build_object(
      'activeSlots', pg_catalog.count(slot.id),
      'capacityLimit', branch.capacity_limit
    )
  from dastak_v1.merchant_branches branch
  join dastak_v1.retail_capacity_slots slot
    on slot.branch_id = branch.id and slot.status = 'HELD'
  group by branch.id, branch.capacity_limit
  having pg_catalog.count(slot.id) > branch.capacity_limit

  union all
  select 'PICKED_UP_FULFILMENT_PACKAGE_MISMATCH', 'FULFILMENT', fulfilment.id,
    pg_catalog.jsonb_build_object(
      'declaredPackageCount', fulfilment.package_count,
      'actualPackageCount', pg_catalog.count(package.id),
      'pickedPackageCount', pg_catalog.count(package.id) filter (
        where package.status in ('PICKED_UP', 'IN_TRANSIT', 'DELIVERED', 'RECOVERY', 'RETURN_PENDING', 'RETURNED')
      )
    )
  from dastak_v1.fulfilments fulfilment
  left join dastak_v1.packages package on package.fulfilment_id = fulfilment.id
  where fulfilment.status in ('PICKED_UP', 'COMPLETED')
  group by fulfilment.id, fulfilment.package_count
  having fulfilment.package_count is null
    or pg_catalog.count(package.id) <> fulfilment.package_count
    or pg_catalog.count(package.id) filter (
      where package.status in ('PICKED_UP', 'IN_TRANSIT', 'DELIVERED', 'RECOVERY', 'RETURN_PENDING', 'RETURNED')
    ) <> fulfilment.package_count

  union all
  select 'DELIVERED_WITHOUT_FINAL_VERIFICATION', 'ORDER', customer_order.id,
    pg_catalog.jsonb_build_object('orderStatus', customer_order.status)
  from dastak_v1.orders customer_order
  where customer_order.status = 'DELIVERED'
    and not exists (
      select 1 from dastak_v1.verification_handoffs handoff
      where handoff.order_id = customer_order.id
        and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
        and handoff.status in ('CONSUMED', 'OVERRIDDEN')
    )

  union all
  select 'PAID_WITHOUT_SUCCESSFUL_PAYMENT', 'ORDER', customer_order.id,
    pg_catalog.jsonb_build_object('orderStatus', customer_order.status)
  from dastak_v1.orders customer_order
  where customer_order.paid_at is not null
    and customer_order.status not in ('PAYMENT_EXPIRED', 'CANCELLED_PREPAYMENT', 'CANCELLED')
    and not exists (
      select 1 from dastak_v1.payments payment
      where payment.order_id = customer_order.id and payment.status = 'SUCCEEDED'
    )

  union all
  select 'PAYMENT_EXPIRED_AFTER_PREPARATION', 'ORDER', customer_order.id,
    pg_catalog.jsonb_build_object(
      'prepStartedCount', pg_catalog.count(fulfilment.id) filter (
        where fulfilment.prep_started_at is not null
      )
    )
  from dastak_v1.orders customer_order
  join dastak_v1.fulfilments fulfilment on fulfilment.order_id = customer_order.id
  where customer_order.status = 'PAYMENT_EXPIRED'
  group by customer_order.id
  having pg_catalog.count(fulfilment.id) filter (
    where fulfilment.prep_started_at is not null
  ) > 0

  union all
  select 'CONTRADICTORY_PACKAGE_CUSTODY', 'PACKAGE', package.id,
    pg_catalog.jsonb_build_object(
      'packageStatus', package.status,
      'custodyOwnerType', package.current_custody_owner_type
    )
  from dastak_v1.packages package
  where (package.status in ('DECLARED', 'READY')
      and package.current_custody_owner_type <> 'MERCHANT_BRANCH')
    or (package.status in ('PICKED_UP', 'IN_TRANSIT')
      and package.current_custody_owner_type <> 'RIDER')
    or (package.status = 'DELIVERED'
      and package.current_custody_owner_type <> 'CUSTOMER')
  )
  select coalesce(
    pg_catalog.jsonb_agg(pg_catalog.to_jsonb(finding)), '[]'::jsonb
  ) into v_finding_rows
  from finding_rows finding;

  v_now := greatest(pg_catalog.clock_timestamp(), v_started_at);
  for v_finding in
    select finding.*
    from pg_catalog.jsonb_to_recordset(v_finding_rows) as finding(
      invariant_key text, entity_type text, entity_id uuid, details jsonb
    )
  loop
    update dastak_v1.invariant_incidents incident
    set details = v_finding.details,
        occurrence_count = incident.occurrence_count + 1,
        last_detected_at = v_now,
        updated_at = v_now,
        version = incident.version + 1
    where incident.invariant_key = v_finding.invariant_key
      and incident.entity_id = v_finding.entity_id
      and incident.status = 'OPEN';
    if not found then
      insert into dastak_v1.invariant_incidents (
        invariant_key, entity_type, entity_id, details,
        first_detected_at, last_detected_at
      ) values (
        v_finding.invariant_key, v_finding.entity_type,
        v_finding.entity_id, v_finding.details, v_now, v_now
      );
    end if;
    v_findings := v_findings + 1;
  end loop;
  update dastak_v1.invariant_incidents incident
  set status = 'RESOLVED', resolved_at = v_now,
      updated_at = v_now, version = incident.version + 1
  where incident.status = 'OPEN'
    and not exists (
      select 1
      from pg_catalog.jsonb_to_recordset(v_finding_rows) as finding(
        invariant_key text, entity_type text, entity_id uuid, details jsonb
      )
      where finding.invariant_key = incident.invariant_key
        and finding.entity_id = incident.entity_id
    );
  insert into dastak_v1.invariant_monitor_runs (
    worker_id, finding_count, started_at, completed_at
  ) values (
    pg_catalog.btrim(p_worker_id), v_findings, v_started_at, v_now
  ) returning id into v_run_id;
  select pg_catalog.count(*) into v_open
  from dastak_v1.invariant_incidents incident where incident.status = 'OPEN';
  return pg_catalog.jsonb_build_object(
    'runId', v_run_id, 'findingCount', v_findings,
    'openCriticalIncidentCount', v_open,
    'healthy', v_open = 0, 'completedAt', v_now
  );
end;
$function$;

-- Cancellation notifications must still reach the merchant after work is released.
CREATE OR REPLACE FUNCTION dastak_v1_api.notification_recipients(p_event_id uuid, p_audience text)
 RETURNS TABLE(account_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_event dastak_v1.domain_events_outbox%rowtype;
  v_order_id uuid;
  v_branch_id uuid;
  v_text text;
begin
  select event.* into v_event
  from dastak_v1.domain_events_outbox event
  where event.id = p_event_id;
  if not found then return; end if;
  v_order_id := dastak_v1_api.event_order_id(p_event_id);
  if p_audience = 'CUSTOMER' then
    return query
      select customer_order.customer_id
      from dastak_v1.orders customer_order
      where customer_order.id = v_order_id;
    return;
  end if;
  if p_audience = 'RIDER' then
    v_text := v_event.payload ->> 'riderId';
    if v_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      account_id := v_text::uuid;
      return next;
      return;
    end if;
    if v_event.event_type = 'RIDER_POOL_OPENED' then
      return query
        select distinct offer.rider_id
        from dastak_v1.delivery_offers offer
        where offer.mission_id = v_event.aggregate_id
          and offer.status = 'OFFERED'
          and offer.respond_by > pg_catalog.now();
      return;
    end if;
    return query
      select distinct mission.assigned_rider_id
      from dastak_v1.delivery_missions mission
      where mission.order_id = v_order_id
        and mission.assigned_rider_id is not null
      union
      select distinct return_mission.assigned_rider_id
      from dastak_v1.return_missions return_mission
      where return_mission.order_id = v_order_id
        and return_mission.assigned_rider_id is not null;
    return;
  end if;
  if p_audience <> 'MERCHANT' then return; end if;
  v_text := v_event.payload ->> 'branchId';
  if v_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_branch_id := v_text::uuid;
  elsif v_event.aggregate_type = 'FULFILMENT' then
    select fulfilment.branch_id into v_branch_id
    from dastak_v1.fulfilments fulfilment where fulfilment.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'MERCHANT_OPPORTUNITY' then
    select opportunity.branch_id into v_branch_id
    from dastak_v1.merchant_opportunities opportunity
    where opportunity.id = v_event.aggregate_id;
  elsif v_event.aggregate_type = 'RECOVERY_OPPORTUNITY' then
    select opportunity.branch_id into v_branch_id
    from dastak_v1.recovery_opportunities opportunity
    where opportunity.id = v_event.aggregate_id;
  end if;
  return query
    with branches as (
      select v_branch_id as branch_id where v_branch_id is not null
      union
      select fulfilment.branch_id
      from dastak_v1.fulfilments fulfilment
      where v_branch_id is null
        and fulfilment.order_id = v_order_id
        and (fulfilment.status <> 'RELEASED'
          or (v_event.event_type = 'ORDER_CANCELLED' and fulfilment.release_reason = 'ADMIN_CANCELLED'))
    )
    select distinct merchant_user.account_id
    from branches
    join dastak_v1.merchant_branches branch on branch.id = branches.branch_id
    join dastak_v1.merchant_users merchant_user
      on merchant_user.organization_id = branch.organization_id
      and merchant_user.status = 'ACTIVE'
    where dastak_v1_api.actor_has_merchant_permission(
      merchant_user.account_id,
      branch.organization_id,
      case when v_event.event_type in (
        'MERCHANT_OPPORTUNITY_OFFERED', 'RECOVERY_OPPORTUNITY_OFFERED'
      ) then 'merchant.opportunities.respond' else 'merchant.fulfilment.manage' end,
      branch.id
    );
end;
$function$;

notify pgrst, 'reload schema';
