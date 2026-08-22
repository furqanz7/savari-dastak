-- Dastak V1 Step 4B: final delivery evidence, verification and Customer custody.

alter table dastak_v1.delivery_missions
  add column out_for_delivery_at timestamptz,
  add column arrived_customer_at timestamptz,
  add column delivered_at timestamptz;

alter table dastak_v1.delivery_missions
  add constraint delivery_missions_final_timestamps_check check (
    (out_for_delivery_at is null or all_packages_picked_up_at is not null)
    and (arrived_customer_at is null or out_for_delivery_at is not null)
    and (delivered_at is null or arrived_customer_at is not null)
    and (status <> 'OUT_FOR_DELIVERY' or out_for_delivery_at is not null)
    and (status <> 'ARRIVED' or arrived_customer_at is not null)
    and (status <> 'DELIVERED' or delivered_at is not null)
  );

create table dastak_v1.delivery_evidence (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  verification_handoff_id uuid not null
    references dastak_v1.verification_handoffs(id),
  evidence_type text not null check (evidence_type = 'RIDER_PRE_DELIVERY_PHOTO'),
  object_path text not null unique check (
    pg_catalog.char_length(object_path) between 1 and 500
  ),
  content_type text not null check (
    content_type in ('image/jpeg', 'image/png', 'image/heic')
  ),
  content_length_bytes bigint check (
    content_length_bytes is null
    or content_length_bytes between 1 and 10485760
  ),
  captured_by uuid not null references public.accounts(id),
  captured_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now()
);

create index delivery_evidence_order_idx
  on dastak_v1.delivery_evidence (order_id, captured_at, id);
create index delivery_evidence_mission_idx
  on dastak_v1.delivery_evidence (mission_id, captured_at, id);
create index delivery_evidence_handoff_idx
  on dastak_v1.delivery_evidence (verification_handoff_id, captured_at, id);
create index delivery_evidence_actor_idx
  on dastak_v1.delivery_evidence (captured_by, captured_at, id);

create table dastak_v1.delivery_evidence_packages (
  evidence_id uuid not null references dastak_v1.delivery_evidence(id),
  package_id uuid not null references dastak_v1.packages(id),
  order_id uuid not null references dastak_v1.orders(id),
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  linked_at timestamptz not null default pg_catalog.now(),
  primary key (evidence_id, package_id)
);

create index delivery_evidence_packages_package_idx
  on dastak_v1.delivery_evidence_packages (package_id, linked_at);
create index delivery_evidence_packages_order_idx
  on dastak_v1.delivery_evidence_packages (order_id, mission_id, package_id);

create table dastak_v1.exceptional_handoff_authorizations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  mission_id uuid not null references dastak_v1.delivery_missions(id),
  verification_handoff_id uuid not null unique
    references dastak_v1.verification_handoffs(id),
  delivery_evidence_id uuid not null references dastak_v1.delivery_evidence(id),
  authorized_by uuid not null references public.accounts(id),
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 10 and 500
  ),
  authorized_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now()
);

create index exceptional_handoff_authorizations_order_idx
  on dastak_v1.exceptional_handoff_authorizations (order_id, authorized_at, id);
create index exceptional_handoff_authorizations_mission_idx
  on dastak_v1.exceptional_handoff_authorizations (mission_id, authorized_at, id);
create index exceptional_handoff_authorizations_evidence_idx
  on dastak_v1.exceptional_handoff_authorizations (delivery_evidence_id);
create index exceptional_handoff_authorizations_actor_idx
  on dastak_v1.exceptional_handoff_authorizations (authorized_by, authorized_at);

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values (
  'delivery.rider_pre_delivery_photo_required',
  'BOOLEAN',
  'Locked V1 requirement for rider package evidence before final handoff.',
  'true'::jsonb,
  '{"allowedValues":[true]}'::jsonb,
  true,
  false
);

insert into dastak_v1.permission_definitions (
  permission_key, description, sensitivity
) values (
  'platform.delivery.handoff_override',
  'Authorize an exceptional final-delivery handoff after evidence review.',
  'HIGHLY_SENSITIVE'
);

insert into dastak_v1.permission_bundles (
  id, bundle_key, display_name, scope, description
) values (
  '10000000-0000-4000-8000-000000000007',
  'delivery_operations',
  'Delivery operations',
  'PLATFORM',
  'Inspect live delivery truth and authorize rare evidence-backed handoff exceptions.'
);

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
values
  ('10000000-0000-4000-8000-000000000007', 'platform.orders.trace'),
  ('10000000-0000-4000-8000-000000000007', 'platform.delivery.handoff_override');

create trigger delivery_evidence_immutable
before update or delete on dastak_v1.delivery_evidence
for each row execute function dastak_v1.reject_mutation();
create trigger delivery_evidence_packages_immutable
before update or delete on dastak_v1.delivery_evidence_packages
for each row execute function dastak_v1.reject_mutation();
create trigger exceptional_handoff_authorizations_immutable
before update or delete on dastak_v1.exceptional_handoff_authorizations
for each row execute function dastak_v1.reject_mutation();

alter table dastak_v1.delivery_evidence enable row level security;
alter table dastak_v1.delivery_evidence_packages enable row level security;
alter table dastak_v1.exceptional_handoff_authorizations enable row level security;

revoke all on table dastak_v1.delivery_evidence
  from public, anon, authenticated;
revoke all on table dastak_v1.delivery_evidence_packages
  from public, anon, authenticated;
revoke all on table dastak_v1.exceptional_handoff_authorizations
  from public, anon, authenticated;
grant select, insert on table dastak_v1.delivery_evidence to service_role;
grant select, insert on table dastak_v1.delivery_evidence_packages to service_role;
grant select, insert on table dastak_v1.exceptional_handoff_authorizations
  to service_role;

create policy dastak_v1_rider_delivery_evidence_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'rider-delivery'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and pg_catalog.split_part(name, '/', 3)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$'
);

create policy dastak_v1_rider_delivery_evidence_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'rider-delivery'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and pg_catalog.split_part(name, '/', 3)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$'
);

create function dastak_v1_api.delivery_verification_attempt_limit()
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_value jsonb;
  v_limit integer;
begin
  v_value := dastak_v1_api.effective_setting_json(
    'delivery.verification_invalid_attempt_limit'
  );
  if v_value is null or pg_catalog.jsonb_typeof(v_value) <> 'number' then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Final-delivery verification attempt configuration is missing or invalid.';
  end if;
  begin
    v_limit := (v_value #>> '{}')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Final-delivery verification attempt configuration is invalid.';
  end;
  if v_limit < 1 then
    raise exception using
      errcode = '55000',
      message = 'SYSTEM_CONFIGURATION_ERROR',
      detail = 'Final-delivery verification attempt limit must be positive.';
  end if;
  return v_limit;
end;
$$;

create function dastak_v1_api.delivery_evidence_covers_packages(
  p_evidence_id uuid,
  p_mission_id uuid,
  p_rider_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from dastak_v1.delivery_evidence evidence
    join dastak_v1.verification_handoffs handoff
      on handoff.id = evidence.verification_handoff_id
    where evidence.id = p_evidence_id
      and evidence.mission_id = p_mission_id
      and evidence.captured_by = p_rider_id
      and evidence.evidence_type = 'RIDER_PRE_DELIVERY_PHOTO'
      and handoff.mission_id = p_mission_id
      and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
  )
  and exists (
    select 1 from dastak_v1.packages package
    join dastak_v1.delivery_missions mission on mission.order_id = package.order_id
    where mission.id = p_mission_id
  )
  and not exists (
    select 1
    from dastak_v1.packages package
    join dastak_v1.delivery_missions mission on mission.order_id = package.order_id
    where mission.id = p_mission_id
      and not exists (
        select 1
        from dastak_v1.delivery_evidence_packages link
        where link.evidence_id = p_evidence_id
          and link.package_id = package.id
          and link.order_id = mission.order_id
          and link.mission_id = mission.id
      )
  );
$$;

create or replace function dastak_v1.guard_delivery_mission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.transport_snapshot is distinct from old.transport_snapshot
    or new.pickup_count is distinct from old.pickup_count
    or new.search_started_at is distinct from old.search_started_at
    or new.created_at is distinct from old.created_at then
    raise exception 'delivery mission identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'delivery mission version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'SEARCHING_RIDER' and new.status in ('ASSIGNED', 'CANCELLED'))
    or (old.status = 'ASSIGNED' and new.status in (
      'EN_ROUTE_TO_PICKUPS', 'REASSIGNING', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'EN_ROUTE_TO_PICKUPS' and new.status in (
      'PICKUP_IN_PROGRESS', 'REASSIGNING', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'PICKUP_IN_PROGRESS' and new.status in (
      'ALL_PACKAGES_PICKED_UP', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'ALL_PACKAGES_PICKED_UP' and new.status in (
      'OUT_FOR_DELIVERY', 'DELIVERY_RECOVERY'
    ))
    or (old.status = 'OUT_FOR_DELIVERY' and new.status in ('ARRIVED', 'DELIVERY_RECOVERY'))
    or (old.status = 'ARRIVED' and new.status in ('DELIVERED', 'DELIVERY_RECOVERY'))
    or (old.status = 'REASSIGNING' and new.status = 'SEARCHING_RIDER')
    or (old.status = 'DELIVERY_RECOVERY' and new.status in (
      'PICKUP_IN_PROGRESS', 'ALL_PACKAGES_PICKED_UP', 'OUT_FOR_DELIVERY',
      'ARRIVED', 'DELIVERED'
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
    old.status <> 'ALL_PACKAGES_PICKED_UP'
    or new.all_packages_picked_up_at is null
    or new.out_for_delivery_at is null
  ) then
    raise exception 'OUT_FOR_DELIVERY requires every pickup and an authoritative timestamp';
  end if;
  if new.status = 'ARRIVED' and (
    old.status <> 'OUT_FOR_DELIVERY' or new.arrived_customer_at is null
  ) then
    raise exception 'ARRIVED requires the final-delivery stage';
  end if;
  if new.status = 'DELIVERED' and (
    old.status not in ('ARRIVED', 'DELIVERY_RECOVERY')
    or new.delivered_at is null
  ) then
    raise exception 'DELIVERED requires verified or authorized final handoff';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create or replace function dastak_v1.guard_package()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_handoff_id uuid;
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
    (old.status = 'DECLARED' and new.status = 'READY')
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
    exception when invalid_text_representation then
      v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'MERCHANT_BRANCH'
      or new.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_id is null
      or new.picked_up_at is null
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
    exception when invalid_text_representation then
      v_handoff_id := null;
    end;
    if v_handoff_id is null
      or old.current_custody_owner_type <> 'RIDER'
      or new.current_custody_owner_type is distinct from old.current_custody_owner_type
      or new.current_custody_owner_id is distinct from old.current_custody_owner_id
      or not exists (
        select 1
        from dastak_v1.verification_handoffs handoff
        join dastak_v1.delivery_missions mission on mission.id = handoff.mission_id
        where handoff.id = v_handoff_id
          and handoff.order_id = new.order_id
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
    exception when invalid_text_representation then
      v_handoff_id := null;
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
        where handoff.id = v_handoff_id
          and handoff.order_id = new.order_id
          and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
          and handoff.status in ('CONSUMED', 'OVERRIDDEN')
          and mission.assigned_rider_id = old.current_custody_owner_id
          and customer_order.customer_id = new.current_custody_owner_id
      ) then
      raise exception 'package delivery requires verified Customer custody transfer';
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
$$;

create or replace function dastak_v1.guard_fulfilment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_handoff_id uuid;
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.source_opportunity_id is distinct from old.source_opportunity_id
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
        select 1
        from dastak_v1.verification_handoffs handoff
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
$$;

create function dastak_v1_api.complete_final_delivery_locked(
  p_actor_id uuid,
  p_mission_id uuid,
  p_handoff_id uuid,
  p_verification_status dastak_v1.verification_handoff_status,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_handoff dastak_v1.verification_handoffs%rowtype;
  v_package_count integer;
  v_updated_count integer;
begin
  if p_verification_status not in ('CONSUMED', 'OVERRIDDEN') then
    raise exception 'invalid final delivery verification truth';
  end if;
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
  for update;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_mission.order_id
  for update;
  select handoff.* into v_handoff
  from dastak_v1.verification_handoffs handoff
  where handoff.id = p_handoff_id
    and handoff.mission_id = v_mission.id
    and handoff.order_id = v_order.id
    and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
  for update;
  perform 1
  from dastak_v1.packages package
  where package.order_id = v_order.id
  order by package.id
  for update;

  if v_mission.status not in ('ARRIVED', 'DELIVERY_RECOVERY')
    or v_order.status <> 'OUT_FOR_DELIVERY'
    or v_handoff.status is distinct from p_verification_status then
    raise exception 'final delivery completion state changed concurrently';
  end if;
  select count(*) into v_package_count
  from dastak_v1.packages package
  where package.order_id = v_order.id;
  if v_package_count < 1 or exists (
    select 1
    from dastak_v1.packages package
    where package.order_id = v_order.id
      and (
        package.status <> 'IN_TRANSIT'
        or package.current_custody_owner_type <> 'RIDER'
        or package.current_custody_owner_id is distinct from v_mission.assigned_rider_id
      )
  ) then
    raise exception 'final delivery requires complete assigned Rider custody';
  end if;
  if not exists (
    select 1
    from dastak_v1.delivery_evidence evidence
    where evidence.mission_id = v_mission.id
      and evidence.verification_handoff_id = v_handoff.id
      and evidence.captured_by = v_mission.assigned_rider_id
      and dastak_v1_api.delivery_evidence_covers_packages(
        evidence.id, v_mission.id, v_mission.assigned_rider_id
      )
  ) then
    raise exception 'rider pre-delivery evidence is required';
  end if;

  perform pg_catalog.set_config(
    'dastak_v1.final_delivery_verification_id', v_handoff.id::text, true
  );
  update dastak_v1.packages package
  set status = 'DELIVERED',
      delivered_at = p_now,
      current_custody_owner_type = 'CUSTOMER',
      current_custody_owner_id = v_order.customer_id,
      version = package.version + 1
  where package.order_id = v_order.id
    and package.status = 'IN_TRANSIT'
    and package.current_custody_owner_type = 'RIDER'
    and package.current_custody_owner_id = v_mission.assigned_rider_id;
  get diagnostics v_updated_count = row_count;
  if v_updated_count <> v_package_count then
    raise exception 'final Customer custody transfer was not complete';
  end if;

  insert into dastak_v1.package_custody_events (
    order_id, mission_id, fulfilment_id, package_id,
    verification_handoff_id, from_owner_type, from_owner_id,
    to_owner_type, to_owner_id, transferred_by, transferred_at
  )
  select
    v_order.id, v_mission.id, package.fulfilment_id, package.id,
    v_handoff.id, 'RIDER', v_mission.assigned_rider_id,
    'CUSTOMER', v_order.customer_id, p_actor_id, p_now
  from dastak_v1.packages package
  where package.order_id = v_order.id
  order by package.id;

  update dastak_v1.fulfilments fulfilment
  set status = 'COMPLETED', version = fulfilment.version + 1
  where fulfilment.order_id = v_order.id
    and fulfilment.status = 'PICKED_UP';
  update dastak_v1.order_lines order_line
  set status = 'FULFILLED', version = order_line.version + 1
  where order_line.order_id = v_order.id
    and order_line.status = 'FULFILLING';
  update dastak_v1.delivery_missions mission
  set status = 'DELIVERED', delivered_at = p_now,
      version = mission.version + 1
  where mission.id = v_mission.id
  returning * into v_mission;
  update dastak_v1.orders customer_order
  set status = 'DELIVERED', delivered_at = p_now,
      version = customer_order.version + 1
  where customer_order.id = v_order.id
  returning * into v_order;

  insert into dastak_v1.order_state_journal (
    order_id, from_status, to_status, order_version,
    command_name, reason, metadata
  ) values (
    v_order.id, 'OUT_FOR_DELIVERY', 'DELIVERED', v_order.version,
    case when p_verification_status = 'CONSUMED'
      then 'verifyFinalDelivery' else 'authorizeExceptionalDeliveryHandoff' end,
    case when p_verification_status = 'CONSUMED'
      then 'The one-time parent-order delivery code verified complete Customer custody.'
      else 'Authorized Operations completed an evidence-backed exceptional handoff.' end,
    pg_catalog.jsonb_build_object(
      'missionId', v_mission.id,
      'handoffId', v_handoff.id,
      'verificationStatus', p_verification_status,
      'packageCount', v_package_count,
      'recipientAccountRequired', false
    )
  );
  insert into dastak_v1.domain_events_outbox (
    event_key, aggregate_type, aggregate_id, aggregate_version,
    event_type, actor_id, payload
  ) values (
    v_mission.id::text || ':' || case when p_verification_status = 'CONSUMED'
      then 'DELIVERY_VERIFIED:' else 'DELIVERY_HANDOFF_OVERRIDDEN:' end
      || v_mission.version::text,
    'DELIVERY_MISSION', v_mission.id, v_mission.version,
    case when p_verification_status = 'CONSUMED'
      then 'DELIVERY_VERIFIED' else 'DELIVERY_HANDOFF_OVERRIDDEN' end,
    p_actor_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'missionId', v_mission.id,
      'handoffId', v_handoff.id,
      'verificationStatus', p_verification_status,
      'packageCount', v_package_count,
      'customerId', v_order.customer_id,
      'deliveredAt', p_now
    )
  ), (
    v_order.id::text || ':ORDER_DELIVERED:' || v_order.version::text,
    'ORDER', v_order.id, v_order.version, 'ORDER_DELIVERED', p_actor_id,
    pg_catalog.jsonb_build_object(
      'missionId', v_mission.id,
      'handoffId', v_handoff.id,
      'verificationStatus', p_verification_status,
      'packageCount', v_package_count,
      'deliveredAt', p_now
    )
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id,
    case when p_verification_status = 'CONSUMED'
      then 'DELIVERY_VERIFIED' else 'DELIVERY_HANDOFF_OVERRIDDEN' end,
    'order', v_order.id,
    pg_catalog.jsonb_build_object(
      'missionId', v_mission.id,
      'handoffId', v_handoff.id,
      'verificationStatus', p_verification_status,
      'packageCount', v_package_count,
      'customerId', v_order.customer_id,
      'deliveredAt', p_now
    )
  );
  return pg_catalog.jsonb_build_object(
    'offer', null,
    'currentMission', null,
    'completedMission', pg_catalog.jsonb_build_object(
      'id', v_mission.id,
      'orderId', v_order.id,
      'status', v_mission.status,
      'verificationStatus', p_verification_status,
      'packageCount', v_package_count,
      'deliveredAt', v_mission.delivered_at
    )
  );
end;
$$;

create function public.dastak_v1_advance_final_delivery(
  p_account_id uuid,
  p_mission_id uuid,
  p_action text,
  p_object_path text,
  p_verification_code text,
  p_idempotency_key text,
  p_request_digest text
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_command text := 'advanceFinalDeliveryV1:' || coalesce(p_action, 'INVALID');
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_handoff dastak_v1.verification_handoffs%rowtype;
  v_evidence dastak_v1.delivery_evidence%rowtype;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_package_count integer;
  v_updated_count integer;
  v_attempt_limit integer;
  v_failed_attempts integer;
  v_storage_metadata jsonb;
  v_content_type text;
  v_content_length bigint;
begin
  if p_account_id is null or p_mission_id is null
    or p_action not in (
      'START_FINAL_DELIVERY', 'ARRIVE_CUSTOMER',
      'ADD_DELIVERY_EVIDENCE', 'VERIFY_DELIVERY'
    )
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or (
      p_action = 'ADD_DELIVERY_EVIDENCE' and (
        p_object_path is null
        or p_object_path !~ (
          '^rider-delivery/' || p_account_id::text
          || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|heic)$'
        )
      )
    )
    or (p_action <> 'ADD_DELIVERY_EVIDENCE' and p_object_path is not null)
    or (
      p_action = 'VERIFY_DELIVERY'
      and (p_verification_code is null or p_verification_code !~ '^[0-9]{6}$')
    )
    or (p_action <> 'VERIFY_DELIVERY' and p_verification_code is not null) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The final-delivery action is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  v_request_hash := extensions.digest(p_request_digest, 'sha256');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_account_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_account_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with another request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-rider:' || p_account_id::text, 0)
  );
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
  for update;
  if not found or v_mission.assigned_rider_id is distinct from p_account_id then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'mission_not_found',
        'message', 'This delivery mission is unavailable.'
      )
    );
    response_status := 404;
  else
    select customer_order.* into v_order
    from dastak_v1.orders customer_order
    where customer_order.id = v_mission.order_id
    for update;
    perform 1
    from dastak_v1.packages package
    where package.order_id = v_order.id
    order by package.id
    for update;
    select handoff.* into v_handoff
    from dastak_v1.verification_handoffs handoff
    where handoff.mission_id = v_mission.id
      and handoff.order_id = v_order.id
      and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
    for update;
    select count(*) into v_package_count
    from dastak_v1.packages package
    where package.order_id = v_order.id;

    if p_action = 'START_FINAL_DELIVERY' then
      perform dastak_v1_api.delivery_verification_attempt_limit();
      if v_mission.status <> 'ALL_PACKAGES_PICKED_UP'
        or v_order.status <> 'PICKUP_IN_PROGRESS' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_final_delivery_state',
            'message', 'Final delivery cannot start from this mission state.'
          )
        );
        response_status := 409;
      elsif v_handoff.id is not null then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'final_delivery_already_started',
            'message', 'The parent-order delivery handoff already exists.'
          )
        );
        response_status := 409;
      elsif v_package_count < 1
        or exists (
          select 1
          from dastak_v1.packages package
          where package.order_id = v_order.id
            and (
              package.status <> 'PICKED_UP'
              or package.current_custody_owner_type <> 'RIDER'
              or package.current_custody_owner_id is distinct from p_account_id
            )
        )
        or exists (
          select 1
          from dastak_v1.fulfilments fulfilment
          where fulfilment.order_id = v_order.id
            and fulfilment.status <> 'PICKED_UP'
        )
        or exists (
          select 1
          from dastak_v1.delivery_stops stop
          where stop.mission_id = v_mission.id
            and stop.status <> 'COMPLETED'
        ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'final_delivery_incomplete_custody',
            'message', 'Every required package must be in the assigned rider custody.'
          )
        );
        response_status := 409;
      else
        v_handoff.id := gen_random_uuid();
        insert into dastak_v1.verification_handoffs (
          id, order_id, mission_id, fulfilment_id, handoff_type, status,
          code_version, code_digest, activated_at
        ) values (
          v_handoff.id, v_order.id, v_mission.id, null,
          'RIDER_TO_CUSTOMER', 'ACTIVE', 1,
          private.dastak_v1_handoff_digest(private.dastak_v1_handoff_code(
            v_handoff.id, 'RIDER_TO_CUSTOMER', 1
          )),
          v_now
        ) returning * into v_handoff;
        perform pg_catalog.set_config(
          'dastak_v1.final_delivery_verification_id', v_handoff.id::text, true
        );
        update dastak_v1.packages package
        set status = 'IN_TRANSIT', version = package.version + 1
        where package.order_id = v_order.id
          and package.status = 'PICKED_UP'
          and package.current_custody_owner_type = 'RIDER'
          and package.current_custody_owner_id = p_account_id;
        get diagnostics v_updated_count = row_count;
        if v_updated_count <> v_package_count then
          raise exception 'final delivery package transition was not complete';
        end if;
        update dastak_v1.delivery_missions mission
        set status = 'OUT_FOR_DELIVERY', out_for_delivery_at = v_now,
            version = mission.version + 1
        where mission.id = v_mission.id
        returning * into v_mission;
        update dastak_v1.orders customer_order
        set status = 'OUT_FOR_DELIVERY', version = customer_order.version + 1
        where customer_order.id = v_order.id
        returning * into v_order;
        insert into dastak_v1.order_state_journal (
          order_id, from_status, to_status, order_version,
          command_name, reason, metadata
        ) values (
          v_order.id, 'PICKUP_IN_PROGRESS', 'OUT_FOR_DELIVERY', v_order.version,
          'startFinalDelivery',
          'Every required package is in the assigned rider custody.',
          pg_catalog.jsonb_build_object(
            'missionId', v_mission.id,
            'handoffId', v_handoff.id,
            'packageCount', v_package_count,
            'allPackagesPickedUpAt', v_mission.all_packages_picked_up_at
          )
        );
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_mission.id::text || ':ALL_PACKAGES_PICKED_UP:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'ALL_PACKAGES_PICKED_UP', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_order.id,
            'missionId', v_mission.id,
            'packageCount', v_package_count,
            'pickedUpAt', v_mission.all_packages_picked_up_at
          )
        ), (
          v_order.id::text || ':ORDER_OUT_FOR_DELIVERY:' || v_order.version::text,
          'ORDER', v_order.id, v_order.version,
          'ORDER_OUT_FOR_DELIVERY', p_account_id,
          pg_catalog.jsonb_build_object(
            'missionId', v_mission.id,
            'handoffId', v_handoff.id,
            'packageCount', v_package_count,
            'outForDeliveryAt', v_mission.out_for_delivery_at
          )
        );
        insert into dastak_v1.audit_events (
          actor_id, action, resource_type, resource_id, metadata
        ) values (
          p_account_id, 'ORDER_OUT_FOR_DELIVERY', 'order', v_order.id,
          pg_catalog.jsonb_build_object(
            'missionId', v_mission.id,
            'handoffId', v_handoff.id,
            'packageCount', v_package_count
          )
        );
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      end if;

    elsif p_action = 'ARRIVE_CUSTOMER' then
      if v_mission.status <> 'OUT_FOR_DELIVERY'
        or v_order.status <> 'OUT_FOR_DELIVERY'
        or v_handoff.id is null
        or v_handoff.status not in ('ACTIVE', 'BLOCKED') then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_final_delivery_state',
            'message', 'Customer arrival is unavailable for this mission.'
          )
        );
        response_status := 409;
      else
        update dastak_v1.delivery_missions mission
        set status = 'ARRIVED', arrived_customer_at = v_now,
            version = mission.version + 1
        where mission.id = v_mission.id
        returning * into v_mission;
        insert into dastak_v1.domain_events_outbox (
          event_key, aggregate_type, aggregate_id, aggregate_version,
          event_type, actor_id, payload
        ) values (
          v_mission.id::text || ':RIDER_ARRIVED_CUSTOMER:' || v_mission.version::text,
          'DELIVERY_MISSION', v_mission.id, v_mission.version,
          'RIDER_ARRIVED_CUSTOMER', p_account_id,
          pg_catalog.jsonb_build_object(
            'orderId', v_order.id,
            'missionId', v_mission.id,
            'arrivedAt', v_mission.arrived_customer_at
          )
        );
        insert into dastak_v1.audit_events (
          actor_id, action, resource_type, resource_id, metadata
        ) values (
          p_account_id, 'RIDER_ARRIVED_CUSTOMER', 'delivery_mission', v_mission.id,
          pg_catalog.jsonb_build_object(
            'orderId', v_order.id,
            'arrivedAt', v_mission.arrived_customer_at
          )
        );
        response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
        response_status := 200;
      end if;

    elsif p_action = 'ADD_DELIVERY_EVIDENCE' then
      if v_mission.status <> 'ARRIVED'
        or v_order.status <> 'OUT_FOR_DELIVERY'
        or v_handoff.id is null
        or v_handoff.status not in ('ACTIVE', 'BLOCKED') then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_final_delivery_state',
            'message', 'Delivery evidence can be captured only after customer arrival.'
          )
        );
        response_status := 409;
      elsif v_package_count < 1 or exists (
        select 1
        from dastak_v1.packages package
        where package.order_id = v_order.id
          and (
            package.status <> 'IN_TRANSIT'
            or package.current_custody_owner_type <> 'RIDER'
            or package.current_custody_owner_id is distinct from p_account_id
          )
      ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'final_delivery_incomplete_custody',
            'message', 'Every required package must remain in assigned Rider custody.'
          )
        );
        response_status := 409;
      elsif exists (
        select 1 from dastak_v1.delivery_evidence evidence
        where evidence.object_path = p_object_path
      ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_evidence_already_recorded',
            'message', 'This immutable evidence object was already recorded.'
          )
        );
        response_status := 409;
      else
        select object.metadata into v_storage_metadata
        from storage.objects object
        where object.bucket_id = 'dastak-evidence'
          and object.name = p_object_path
          and (
            object.owner_id = p_account_id::text
            or object.owner = p_account_id
          );
        if not found then
          response_body := pg_catalog.jsonb_build_object(
            'error', pg_catalog.jsonb_build_object(
              'code', 'delivery_evidence_upload_missing',
              'message', 'The rider package photo upload was not found.'
            )
          );
          response_status := 409;
        else
          v_content_type := coalesce(
            v_storage_metadata ->> 'mimetype',
            case
              when p_object_path ~ '\.(jpg|jpeg)$' then 'image/jpeg'
              when p_object_path ~ '\.png$' then 'image/png'
              when p_object_path ~ '\.heic$' then 'image/heic'
            end
          );
          if v_content_type not in ('image/jpeg', 'image/png', 'image/heic') then
            response_body := pg_catalog.jsonb_build_object(
              'error', pg_catalog.jsonb_build_object(
                'code', 'delivery_evidence_invalid',
                'message', 'Delivery evidence must be an image.'
              )
            );
            response_status := 400;
          else
            if coalesce(v_storage_metadata ->> 'size', '') ~ '^[0-9]+$' then
              v_content_length := (v_storage_metadata ->> 'size')::bigint;
            end if;
            if v_content_length is not null
              and v_content_length not between 1 and 10485760 then
              response_body := pg_catalog.jsonb_build_object(
                'error', pg_catalog.jsonb_build_object(
                  'code', 'delivery_evidence_invalid',
                  'message', 'Delivery evidence must be an image up to 10 MB.'
                )
              );
              response_status := 400;
            else
              insert into dastak_v1.delivery_evidence (
                order_id, mission_id, verification_handoff_id, evidence_type,
                object_path, content_type, content_length_bytes,
                captured_by, captured_at
              ) values (
                v_order.id, v_mission.id, v_handoff.id,
                'RIDER_PRE_DELIVERY_PHOTO', p_object_path, v_content_type,
                v_content_length, p_account_id, v_now
              ) returning * into v_evidence;
              insert into dastak_v1.delivery_evidence_packages (
                evidence_id, package_id, order_id, mission_id, linked_at
              )
              select v_evidence.id, package.id, v_order.id, v_mission.id, v_now
              from dastak_v1.packages package
              where package.order_id = v_order.id
              order by package.id;
              get diagnostics v_updated_count = row_count;
              if v_updated_count <> v_package_count then
                raise exception 'delivery evidence package context was not complete';
              end if;
              insert into dastak_v1.domain_events_outbox (
                event_key, aggregate_type, aggregate_id, aggregate_version,
                event_type, actor_id, payload
              ) values (
                v_evidence.id::text || ':RIDER_PRE_DELIVERY_EVIDENCE_CAPTURED:1',
                'DELIVERY_EVIDENCE', v_evidence.id, 1,
                'RIDER_PRE_DELIVERY_EVIDENCE_CAPTURED', p_account_id,
                pg_catalog.jsonb_build_object(
                  'orderId', v_order.id,
                  'missionId', v_mission.id,
                  'handoffId', v_handoff.id,
                  'evidenceId', v_evidence.id,
                  'packageCount', v_package_count,
                  'capturedAt', v_evidence.captured_at
                )
              );
              insert into dastak_v1.audit_events (
                actor_id, action, resource_type, resource_id, metadata
              ) values (
                p_account_id, 'RIDER_PRE_DELIVERY_EVIDENCE_CAPTURED',
                'delivery_evidence', v_evidence.id,
                pg_catalog.jsonb_build_object(
                  'orderId', v_order.id,
                  'missionId', v_mission.id,
                  'handoffId', v_handoff.id,
                  'packageCount', v_package_count,
                  'objectPath', p_object_path
                )
              );
              response_body := dastak_v1_api.delivery_partner_snapshot(p_account_id);
              response_status := 200;
            end if;
          end if;
        end if;
      end if;

    elsif p_action = 'VERIFY_DELIVERY' then
      if v_handoff.id is null
        or v_mission.status in (
          'ASSIGNED', 'EN_ROUTE_TO_PICKUPS', 'PICKUP_IN_PROGRESS',
          'ALL_PACKAGES_PICKED_UP'
        ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_code_inactive',
            'message', 'The parent-order delivery code is not active.'
          )
        );
        response_status := 409;
      elsif v_handoff.status = 'CONSUMED' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_code_consumed',
            'message', 'This delivery code was already consumed.'
          )
        );
        response_status := 409;
      elsif v_handoff.status = 'OVERRIDDEN' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_handoff_overridden',
            'message', 'Operations already completed this exceptional handoff.'
          )
        );
        response_status := 409;
      elsif v_handoff.status = 'BLOCKED' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_code_blocked',
            'message', 'Normal verification is blocked. Report the problem to Operations.'
          )
        );
        response_status := 409;
      elsif v_mission.status <> 'ARRIVED'
        or v_order.status <> 'OUT_FOR_DELIVERY'
        or v_handoff.status <> 'ACTIVE' then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'invalid_final_delivery_state',
            'message', 'This delivery cannot be verified now.'
          )
        );
        response_status := 409;
      elsif v_package_count < 1 or exists (
        select 1
        from dastak_v1.packages package
        where package.order_id = v_order.id
          and (
            package.status <> 'IN_TRANSIT'
            or package.current_custody_owner_type <> 'RIDER'
            or package.current_custody_owner_id is distinct from p_account_id
          )
      ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'final_delivery_incomplete_custody',
            'message', 'Every required package must remain in assigned Rider custody.'
          )
        );
        response_status := 409;
      elsif not exists (
        select 1
        from dastak_v1.delivery_evidence evidence
        where evidence.mission_id = v_mission.id
          and evidence.verification_handoff_id = v_handoff.id
          and evidence.captured_by = p_account_id
          and dastak_v1_api.delivery_evidence_covers_packages(
            evidence.id, v_mission.id, p_account_id
          )
      ) then
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', 'delivery_evidence_required',
            'message', 'Capture the required package photo before customer handoff.'
          )
        );
        response_status := 409;
      elsif v_handoff.code_digest <> private.dastak_v1_handoff_digest(
        p_verification_code
      ) then
        v_attempt_limit := dastak_v1_api.delivery_verification_attempt_limit();
        v_failed_attempts := v_handoff.failed_attempts + 1;
        update dastak_v1.verification_handoffs handoff
        set failed_attempts = v_failed_attempts,
            status = case when v_failed_attempts >= v_attempt_limit
              then 'BLOCKED' else handoff.status end,
            blocked_at = case when v_failed_attempts >= v_attempt_limit
              then v_now else null end,
            version = handoff.version + 1
        where handoff.id = v_handoff.id
        returning * into v_handoff;
        insert into dastak_v1.audit_events (
          actor_id, action, resource_type, resource_id, metadata
        ) values (
          p_account_id, 'DELIVERY_CODE_REJECTED',
          'verification_handoff', v_handoff.id,
          pg_catalog.jsonb_build_object(
            'orderId', v_order.id,
            'missionId', v_mission.id,
            'failedAttempts', v_failed_attempts,
            'blocked', v_failed_attempts >= v_attempt_limit
          )
        );
        if v_failed_attempts >= v_attempt_limit then
          insert into dastak_v1.domain_events_outbox (
            event_key, aggregate_type, aggregate_id, aggregate_version,
            event_type, actor_id, payload
          ) values (
            v_handoff.id::text || ':FINAL_DELIVERY_VERIFICATION_BLOCKED:'
              || v_handoff.version::text,
            'VERIFICATION_HANDOFF', v_handoff.id, v_handoff.version,
            'FINAL_DELIVERY_VERIFICATION_BLOCKED', p_account_id,
            pg_catalog.jsonb_build_object(
              'orderId', v_order.id,
              'missionId', v_mission.id,
              'failedAttempts', v_failed_attempts
            )
          );
        end if;
        response_body := pg_catalog.jsonb_build_object(
          'error', pg_catalog.jsonb_build_object(
            'code', case when v_failed_attempts >= v_attempt_limit
              then 'delivery_code_blocked' else 'delivery_code_invalid' end,
            'message', case when v_failed_attempts >= v_attempt_limit
              then 'Normal verification is blocked. Report the problem to Operations.'
              else 'The delivery code is incorrect.' end
          )
        );
        response_status := 409;
      else
        update dastak_v1.verification_handoffs handoff
        set status = 'CONSUMED', consumed_at = v_now,
            consumed_by = p_account_id, version = handoff.version + 1
        where handoff.id = v_handoff.id
        returning * into v_handoff;
        response_body := dastak_v1_api.complete_final_delivery_locked(
          p_account_id, v_mission.id, v_handoff.id, 'CONSUMED', v_now
        );
        response_status := 200;
      end if;
    end if;
  end if;

  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_account_id, v_command, p_idempotency_key, v_request_hash,
    response_body, response_status, p_mission_id
  );
  return next;
end;
$$;

create function dastak_v1_api.authorize_exceptional_delivery_handoff(
  p_actor_id uuid,
  p_mission_id uuid,
  p_delivery_evidence_id uuid,
  p_reason text,
  p_expected_mission_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'authorizeExceptionalDeliveryHandoff';
  v_request_hash bytea;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_order dastak_v1.orders%rowtype;
  v_handoff dastak_v1.verification_handoffs%rowtype;
  v_evidence dastak_v1.delivery_evidence%rowtype;
  v_authorization_id uuid;
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_response jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.delivery.handoff_override'
  );
  if p_mission_id is null or p_delivery_evidence_id is null
    or p_expected_mission_version is null or p_expected_mission_version < 1
    or nullif(pg_catalog.btrim(p_reason), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 10 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or pg_catalog.char_length(p_idempotency_key) > 200 then
    raise exception using errcode = '22023', message = 'invalid exceptional handoff';
  end if;
  v_request_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'missionId', p_mission_id,
    'deliveryEvidenceId', p_delivery_evidence_id,
    'reason', pg_catalog.btrim(p_reason),
    'expectedMissionVersion', p_expected_mission_version
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || p_idempotency_key, 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_hash = v_request_hash then
      return v_existing.response_body;
    end if;
    raise exception using errcode = '22023',
      message = 'idempotency key was already used with a different request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('dastak-v1-mission:' || p_mission_id::text, 0)
  );
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'delivery mission not found';
  end if;
  select customer_order.* into v_order
  from dastak_v1.orders customer_order
  where customer_order.id = v_mission.order_id
  for update;
  select handoff.* into v_handoff
  from dastak_v1.verification_handoffs handoff
  where handoff.mission_id = v_mission.id
    and handoff.order_id = v_order.id
    and handoff.handoff_type = 'RIDER_TO_CUSTOMER'
  for update;
  select evidence.* into v_evidence
  from dastak_v1.delivery_evidence evidence
  where evidence.id = p_delivery_evidence_id
  for update;
  perform 1
  from dastak_v1.packages package
  where package.order_id = v_order.id
  order by package.id
  for update;

  if v_mission.version is distinct from p_expected_mission_version then
    raise exception using errcode = '40001', message = 'stale delivery mission version';
  end if;
  if v_mission.status not in ('ARRIVED', 'DELIVERY_RECOVERY')
    or v_order.status <> 'OUT_FOR_DELIVERY'
    or v_handoff.id is null
    or v_handoff.status not in ('ACTIVE', 'BLOCKED') then
    raise exception using errcode = '55000',
      message = 'exceptional final handoff is unavailable';
  end if;
  if v_evidence.id is null
    or v_evidence.order_id <> v_order.id
    or v_evidence.mission_id <> v_mission.id
    or v_evidence.verification_handoff_id <> v_handoff.id
    or v_evidence.captured_by <> v_mission.assigned_rider_id
    or not dastak_v1_api.delivery_evidence_covers_packages(
      v_evidence.id, v_mission.id, v_mission.assigned_rider_id
    ) then
    raise exception using errcode = '55000',
      message = 'reviewed rider evidence must cover every delivery package';
  end if;
  if exists (
    select 1
    from dastak_v1.packages package
    where package.order_id = v_order.id
      and (
        package.status <> 'IN_TRANSIT'
        or package.current_custody_owner_type <> 'RIDER'
        or package.current_custody_owner_id is distinct from v_mission.assigned_rider_id
      )
  ) then
    raise exception using errcode = '55000',
      message = 'exceptional handoff requires complete assigned Rider custody';
  end if;

  insert into dastak_v1.exceptional_handoff_authorizations (
    order_id, mission_id, verification_handoff_id, delivery_evidence_id,
    authorized_by, reason, authorized_at
  ) values (
    v_order.id, v_mission.id, v_handoff.id, v_evidence.id,
    p_actor_id, pg_catalog.btrim(p_reason), v_now
  ) returning id into v_authorization_id;
  update dastak_v1.verification_handoffs handoff
  set status = 'OVERRIDDEN', overridden_at = v_now,
      overridden_by = p_actor_id, override_reason = pg_catalog.btrim(p_reason),
      version = handoff.version + 1
  where handoff.id = v_handoff.id
  returning * into v_handoff;
  v_response := dastak_v1_api.complete_final_delivery_locked(
    p_actor_id, v_mission.id, v_handoff.id, 'OVERRIDDEN', v_now
  ) || pg_catalog.jsonb_build_object(
    'exceptionalHandoffAuthorizationId', v_authorization_id
  );
  insert into dastak_v1.audit_events (
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'EXCEPTIONAL_HANDOFF_AUTHORIZED',
    'exceptional_handoff_authorization', v_authorization_id,
    pg_catalog.jsonb_build_object(
      'orderId', v_order.id,
      'missionId', v_mission.id,
      'handoffId', v_handoff.id,
      'deliveryEvidenceId', v_evidence.id,
      'reason', pg_catalog.btrim(p_reason),
      'normalVerificationOccurred', false
    )
  );
  insert into dastak_v1.idempotency_records (
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, p_idempotency_key, v_request_hash,
    v_response, 200, v_mission.id
  );
  return v_response;
end;
$$;

create function public.dastak_v1_authorize_exceptional_delivery_handoff(
  p_mission_id uuid,
  p_delivery_evidence_id uuid,
  p_reason text,
  p_expected_mission_version bigint,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.authorize_exceptional_delivery_handoff(
    auth.uid(), p_mission_id, p_delivery_evidence_id, p_reason,
    p_expected_mission_version, p_idempotency_key
  );
$$;

alter function dastak_v1_api.rider_mission_json(uuid, uuid)
  rename to rider_mission_json_step4a;

create function dastak_v1_api.rider_mission_json(
  p_rider_id uuid,
  p_mission_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_context dastak_v1.order_context_snapshots%rowtype;
  v_handoff dastak_v1.verification_handoffs%rowtype;
begin
  v_result := dastak_v1_api.rider_mission_json_step4a(p_rider_id, p_mission_id);
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.id = p_mission_id
    and mission.assigned_rider_id = p_rider_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'delivery mission not found';
  end if;
  select context.* into v_context
  from dastak_v1.order_context_snapshots context
  where context.order_id = v_mission.order_id;
  select handoff.* into v_handoff
  from dastak_v1.verification_handoffs handoff
  where handoff.mission_id = v_mission.id
    and handoff.handoff_type = 'RIDER_TO_CUSTOMER';

  return v_result || pg_catalog.jsonb_build_object(
    'customerDestination', case
      when v_mission.all_packages_picked_up_at is not null then
        pg_catalog.jsonb_build_object(
          'address', v_context.delivery_address,
          'recipient', v_context.recipient
        )
      else null
    end,
    'outForDeliveryAt', v_mission.out_for_delivery_at,
    'arrivedCustomerAt', v_mission.arrived_customer_at,
    'deliveredAt', v_mission.delivered_at,
    'finalVerification', case when v_handoff.id is null then null else
      pg_catalog.jsonb_build_object(
        'status', v_handoff.status,
        'failedAttempts', v_handoff.failed_attempts,
        'activatedAt', v_handoff.activated_at,
        'blockedAt', v_handoff.blocked_at,
        'evidenceRequired', true,
        'evidencePresent', exists (
          select 1 from dastak_v1.delivery_evidence evidence
          where evidence.verification_handoff_id = v_handoff.id
            and evidence.captured_by = p_rider_id
            and dastak_v1_api.delivery_evidence_covers_packages(
              evidence.id, v_mission.id, p_rider_id
            )
        )
      ) end,
    'deliveryEvidence', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', evidence.id,
        'objectPath', evidence.object_path,
        'contentType', evidence.content_type,
        'capturedAt', evidence.captured_at,
        'packageCount', (
          select count(*) from dastak_v1.delivery_evidence_packages link
          where link.evidence_id = evidence.id
        )
      ) order by evidence.captured_at, evidence.id)
      from dastak_v1.delivery_evidence evidence
      where evidence.mission_id = v_mission.id
        and evidence.captured_by = p_rider_id
    ), '[]'::jsonb),
    'canStartFinalDelivery', v_mission.status = 'ALL_PACKAGES_PICKED_UP',
    'canArriveCustomer', v_mission.status = 'OUT_FOR_DELIVERY',
    'canCaptureDeliveryEvidence', v_mission.status = 'ARRIVED',
    'canVerifyDelivery', v_mission.status = 'ARRIVED'
      and v_handoff.status = 'ACTIVE'
      and exists (
        select 1 from dastak_v1.delivery_evidence evidence
        where evidence.verification_handoff_id = v_handoff.id
          and evidence.captured_by = p_rider_id
          and dastak_v1_api.delivery_evidence_covers_packages(
            evidence.id, v_mission.id, p_rider_id
          )
      )
  );
end;
$$;

alter function dastak_v1_api.order_json(uuid, uuid)
  rename to order_json_step4a;

create function dastak_v1_api.order_json(
  p_order_id uuid,
  p_customer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order jsonb;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_handoff dastak_v1.verification_handoffs%rowtype;
begin
  v_order := dastak_v1_api.order_json_step4a(p_order_id, p_customer_id);
  if v_order is null then return null; end if;
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.order_id = p_order_id
  order by mission.created_at desc, mission.id desc
  limit 1;
  if found then
    select handoff.* into v_handoff
    from dastak_v1.verification_handoffs handoff
    where handoff.mission_id = v_mission.id
      and handoff.handoff_type = 'RIDER_TO_CUSTOMER';
  end if;
  if v_order ->> 'status' = 'OUT_FOR_DELIVERY' then
    v_order := pg_catalog.jsonb_set(
      v_order, '{customerState}', '"ON_THE_WAY"'::jsonb, true
    );
    v_order := pg_catalog.jsonb_set(
      v_order, '{fulfilmentProgress}',
      '{"state":"ON_THE_WAY","title":"On the way"}'::jsonb, true
    );
  elsif v_order ->> 'status' = 'DELIVERED' then
    v_order := pg_catalog.jsonb_set(
      v_order, '{customerState}', '"DELIVERED"'::jsonb, true
    );
    v_order := pg_catalog.jsonb_set(
      v_order, '{fulfilmentProgress}',
      '{"state":"DELIVERED","title":"Delivered"}'::jsonb, true
    );
  end if;
  if v_order ->> 'status' in ('OUT_FOR_DELIVERY', 'DELIVERED') then
    v_order := v_order || pg_catalog.jsonb_build_object(
      'delivery', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'state', case when v_order ->> 'status' = 'DELIVERED'
          then 'DELIVERED' else 'ON_THE_WAY' end,
        'verificationStatus', v_handoff.status,
        'deliveryCode', case
          when v_order ->> 'status' = 'OUT_FOR_DELIVERY'
            and v_mission.status in ('OUT_FOR_DELIVERY', 'ARRIVED')
            and v_handoff.status = 'ACTIVE'
          then private.dastak_v1_handoff_code(
            v_handoff.id, v_handoff.handoff_type, v_handoff.code_version
          )
          else null
        end,
        'riderArrivedAt', v_mission.arrived_customer_at,
        'deliveredAt', v_mission.delivered_at,
        'recipientAccountRequired', false
      ))
    );
  end if;
  return v_order;
end;
$$;

alter function dastak_v1_api.admin_execution_trace(uuid, uuid)
  rename to admin_execution_trace_step4a;

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
  v_delivery jsonb;
  v_mission dastak_v1.delivery_missions%rowtype;
  v_delivered_at timestamptz;
begin
  v_trace := dastak_v1_api.admin_execution_trace_step4a(p_actor_id, p_order_id);
  v_delivery := coalesce(v_trace -> 'delivery', '{}'::jsonb);
  select mission.* into v_mission
  from dastak_v1.delivery_missions mission
  where mission.order_id = p_order_id
  order by mission.created_at desc, mission.id desc
  limit 1;
  select customer_order.delivered_at into v_delivered_at
  from dastak_v1.orders customer_order
  where customer_order.id = p_order_id;

  if v_mission.id is not null and v_delivery -> 'mission' is not null
    and v_delivery -> 'mission' <> 'null'::jsonb then
    v_delivery := pg_catalog.jsonb_set(
      v_delivery,
      '{mission}',
      (v_delivery -> 'mission') || pg_catalog.jsonb_build_object(
        'outForDeliveryAt', v_mission.out_for_delivery_at,
        'arrivedCustomerAt', v_mission.arrived_customer_at,
        'deliveredAt', v_mission.delivered_at
      ),
      true
    );
  end if;
  v_delivery := v_delivery || pg_catalog.jsonb_build_object(
    'verification', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', handoff.id,
        'missionId', handoff.mission_id,
        'fulfilmentId', handoff.fulfilment_id,
        'type', handoff.handoff_type,
        'status', handoff.status,
        'failedAttempts', handoff.failed_attempts,
        'activatedAt', handoff.activated_at,
        'consumedAt', handoff.consumed_at,
        'consumedBy', handoff.consumed_by,
        'blockedAt', handoff.blocked_at,
        'overriddenAt', handoff.overridden_at,
        'overriddenBy', handoff.overridden_by,
        'overrideReason', handoff.override_reason
      ) order by handoff.created_at, handoff.id)
      from dastak_v1.verification_handoffs handoff
      where handoff.order_id = p_order_id
    ), '[]'::jsonb),
    'deliveryEvidence', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', evidence.id,
        'missionId', evidence.mission_id,
        'verificationHandoffId', evidence.verification_handoff_id,
        'type', evidence.evidence_type,
        'objectPath', evidence.object_path,
        'contentType', evidence.content_type,
        'contentLengthBytes', evidence.content_length_bytes,
        'capturedBy', evidence.captured_by,
        'capturedAt', evidence.captured_at,
        'packageIds', coalesce((
          select pg_catalog.jsonb_agg(link.package_id order by link.package_id)
          from dastak_v1.delivery_evidence_packages link
          where link.evidence_id = evidence.id
        ), '[]'::jsonb)
      ) order by evidence.captured_at, evidence.id)
      from dastak_v1.delivery_evidence evidence
      where evidence.order_id = p_order_id
    ), '[]'::jsonb),
    'exceptionalHandoffs', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', exception_record.id,
        'missionId', exception_record.mission_id,
        'verificationHandoffId', exception_record.verification_handoff_id,
        'deliveryEvidenceId', exception_record.delivery_evidence_id,
        'authorizedBy', exception_record.authorized_by,
        'authorizerName', account.display_name,
        'reason', exception_record.reason,
        'authorizedAt', exception_record.authorized_at,
        'normalVerificationOccurred', false
      ) order by exception_record.authorized_at, exception_record.id)
      from dastak_v1.exceptional_handoff_authorizations exception_record
      join public.accounts account on account.id = exception_record.authorized_by
      where exception_record.order_id = p_order_id
    ), '[]'::jsonb),
    'canAuthorizeExceptionalHandoff',
      dastak_v1_api.actor_has_platform_permission(
        p_actor_id, 'platform.delivery.handoff_override'
      )
  );
  return pg_catalog.jsonb_set(v_trace, '{delivery}', v_delivery, true)
    || pg_catalog.jsonb_build_object(
      'order', (v_trace -> 'order') || pg_catalog.jsonb_build_object(
        'deliveredAt', v_delivered_at
      )
    );
end;
$$;

revoke all on function dastak_v1_api.delivery_verification_attempt_limit()
  from public;
revoke all on function dastak_v1_api.delivery_evidence_covers_packages(
  uuid, uuid, uuid
) from public;
revoke all on function dastak_v1_api.complete_final_delivery_locked(
  uuid, uuid, uuid, dastak_v1.verification_handoff_status, timestamptz
) from public;
revoke all on function dastak_v1_api.authorize_exceptional_delivery_handoff(
  uuid, uuid, uuid, text, bigint, text
) from public;
revoke all on function dastak_v1_api.rider_mission_json_step4a(uuid, uuid)
  from public;
revoke all on function dastak_v1_api.rider_mission_json(uuid, uuid)
  from public;
revoke all on function dastak_v1_api.order_json_step4a(uuid, uuid)
  from public;
revoke all on function dastak_v1_api.order_json(uuid, uuid)
  from public;
revoke all on function dastak_v1_api.admin_execution_trace_step4a(uuid, uuid)
  from public;
revoke all on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  from public;
revoke all on function public.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) from public, anon, authenticated;
revoke all on function public.dastak_v1_authorize_exceptional_delivery_handoff(
  uuid, uuid, text, bigint, text
) from public, anon, service_role;

grant execute on function dastak_v1_api.delivery_verification_attempt_limit()
  to service_role;
grant execute on function dastak_v1_api.delivery_evidence_covers_packages(
  uuid, uuid, uuid
) to authenticated, service_role;
grant execute on function dastak_v1_api.complete_final_delivery_locked(
  uuid, uuid, uuid, dastak_v1.verification_handoff_status, timestamptz
) to service_role;
grant execute on function dastak_v1_api.authorize_exceptional_delivery_handoff(
  uuid, uuid, uuid, text, bigint, text
) to authenticated, service_role;
grant execute on function dastak_v1_api.rider_mission_json_step4a(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.rider_mission_json(uuid, uuid)
  to service_role;
grant execute on function dastak_v1_api.order_json_step4a(uuid, uuid)
  to authenticated, service_role;
grant execute on function dastak_v1_api.order_json(uuid, uuid)
  to authenticated, service_role;
grant execute on function dastak_v1_api.admin_execution_trace_step4a(uuid, uuid)
  to authenticated, service_role;
grant execute on function dastak_v1_api.admin_execution_trace(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) to service_role;
grant execute on function public.dastak_v1_authorize_exceptional_delivery_handoff(
  uuid, uuid, text, bigint, text
) to authenticated;

comment on function public.dastak_v1_advance_final_delivery(
  uuid, uuid, text, text, text, text, text
) is
  'Assigned-rider-only final delivery commands with immutable evidence, one-time code and atomic Customer custody.';
comment on function public.dastak_v1_authorize_exceptional_delivery_handoff(
  uuid, uuid, text, bigint, text
) is
  'Permission-scoped exceptional handoff that records OVERRIDDEN separately from normal verification.';
