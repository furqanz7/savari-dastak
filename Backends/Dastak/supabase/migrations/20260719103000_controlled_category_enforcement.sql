alter table private.catalogue_products
  add column requires_prescription boolean not null default false,
  add column restricted_tobacco_kind text;

update private.catalogue_products
set requires_prescription = true
where catalogue_kind = 'prescription_medicine';

alter table private.catalogue_products
  add constraint catalogue_products_controlled_metadata_check check (
    (
      catalogue_kind = 'general'
      and requires_prescription = false
      and restricted_tobacco_kind is null
    )
    or (
      catalogue_kind = 'otc_medicine'
      and requires_prescription = false
      and restricted_tobacco_kind is null
    )
    or (
      catalogue_kind = 'prescription_medicine'
      and requires_prescription = true
      and restricted_tobacco_kind is null
    )
    or (
      catalogue_kind = 'paan_corner'
      and requires_prescription = false
      and (
        restricted_tobacco_kind is null
        or restricted_tobacco_kind in ('cigarette', 'cigar', 'rolling_tobacco')
      )
    )
  );

create table private.controlled_category_policies (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  version text not null unique check (
    pg_catalog.char_length(pg_catalog.btrim(version)) between 1 and 80
  ),
  minimum_age integer not null default 18 check (minimum_age = 18),
  allowed_tobacco_kinds text[] not null default '{}'::text[] check (
    allowed_tobacco_kinds <@ array['cigarette', 'cigar', 'rolling_tobacco']::text[]
    and pg_catalog.cardinality(allowed_tobacco_kinds) <= 3
  ),
  active boolean not null default false,
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  deactivated_at timestamptz,
  check (active or deactivated_at is not null),
  check (not active or pg_catalog.cardinality(allowed_tobacco_kinds) > 0)
);

create unique index controlled_category_policy_active_uidx
  on private.controlled_category_policies(active)
  where active = true;

create table private.controlled_store_compliance (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  store_id uuid not null references private.merchant_stores(id) on delete cascade,
  scope text not null check (scope in ('medicine', 'tobacco')),
  evidence_object_path text,
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'rejected', 'suspended')
  ),
  valid_until timestamptz,
  submitted_at timestamptz not null default pg_catalog.now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.accounts(id),
  review_reason text check (
    review_reason is null
    or pg_catalog.char_length(pg_catalog.btrim(review_reason)) between 1 and 500
  ),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (store_id, scope),
  check (scope <> 'medicine' or evidence_object_path is not null),
  check (
    (status = 'pending' and reviewed_at is null and reviewed_by is null)
    or (status <> 'pending' and reviewed_at is not null and reviewed_by is not null)
  ),
  check (
    status <> 'approved'
    or scope <> 'medicine'
    or valid_until > reviewed_at
  )
);

create index controlled_store_compliance_status_idx
  on private.controlled_store_compliance(scope, status, valid_until);

create table private.adult_attestations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  customer_account_id uuid not null references public.accounts(id) on delete cascade,
  policy_id uuid not null references private.controlled_category_policies(id),
  affirmed_adult boolean not null check (affirmed_adult = true),
  affirmed_not_for_minor boolean not null check (affirmed_not_for_minor = true),
  attested_at timestamptz not null default pg_catalog.now(),
  unique (customer_account_id, policy_id)
);

create table private.restricted_exclusion_zones (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  name text not null check (
    pg_catalog.char_length(pg_catalog.btrim(name)) between 1 and 120
  ),
  kind text not null check (kind in ('school', 'college')),
  center extensions.geometry(Point, 4326) not null,
  radius_meters integer not null check (radius_meters between 1 and 5000),
  active boolean not null default true,
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create index restricted_exclusion_zones_center_gix
  on private.restricted_exclusion_zones using gist(center);
create index restricted_exclusion_zones_active_idx
  on private.restricted_exclusion_zones(active);

create table private.prescription_evidence (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  customer_account_id uuid not null references public.accounts(id) on delete cascade,
  object_path text not null,
  created_at timestamptz not null default pg_catalog.now(),
  unique (customer_account_id, object_path)
);

alter table private.merchant_order_quotes
  add column controlled_scope text not null default 'general' check (
    controlled_scope in ('general', 'medicine', 'tobacco')
  ),
  add column controlled_policy_id uuid references private.controlled_category_policies(id),
  add column adult_attestation_id uuid references private.adult_attestations(id),
  add column prescription_evidence_id uuid references private.prescription_evidence(id),
  add constraint merchant_order_quotes_controlled_context_check check (
    (controlled_scope = 'general' and controlled_policy_id is null and adult_attestation_id is null)
    or (controlled_scope = 'medicine' and controlled_policy_id is null and adult_attestation_id is null)
    or (controlled_scope = 'tobacco' and controlled_policy_id is not null and adult_attestation_id is not null)
  );

alter table private.merchant_orders
  add column controlled_scope text not null default 'general' check (
    controlled_scope in ('general', 'medicine', 'tobacco')
  ),
  add column controlled_policy_id uuid references private.controlled_category_policies(id),
  add column adult_attestation_id uuid references private.adult_attestations(id),
  add column prescription_evidence_id uuid references private.prescription_evidence(id),
  add constraint merchant_orders_controlled_context_check check (
    (controlled_scope = 'general' and controlled_policy_id is null and adult_attestation_id is null)
    or (controlled_scope = 'medicine' and controlled_policy_id is null and adult_attestation_id is null)
    or (controlled_scope = 'tobacco' and controlled_policy_id is not null and adult_attestation_id is not null)
  );

create index merchant_orders_controlled_scope_idx
  on private.merchant_orders(controlled_scope, status, created_at desc)
  where controlled_scope <> 'general';

create table private.restricted_handoff_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  order_id uuid not null unique references private.merchant_orders(id),
  assignment_id uuid not null references private.delivery_assignment_attempts(id),
  partner_account_id uuid not null references public.accounts(id),
  visual_age_check text not null check (
    visual_age_check in ('passed', 'failed', 'uncertain')
  ),
  reason text check (
    reason is null
    or pg_catalog.char_length(pg_catalog.btrim(reason)) between 1 and 500
  ),
  created_at timestamptz not null default pg_catalog.now(),
  check (
    visual_age_check = 'passed'
    or reason is not null
  )
);

create table private.restricted_return_confirmations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  order_id uuid not null unique references private.merchant_orders(id),
  merchant_account_id uuid not null references public.accounts(id),
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 1 and 500
  ),
  confirmed_at timestamptz not null default pg_catalog.now()
);

alter table private.controlled_category_policies enable row level security;
alter table private.controlled_store_compliance enable row level security;
alter table private.adult_attestations enable row level security;
alter table private.restricted_exclusion_zones enable row level security;
alter table private.prescription_evidence enable row level security;
alter table private.restricted_handoff_events enable row level security;
alter table private.restricted_return_confirmations enable row level security;

revoke all on table private.controlled_category_policies from public, anon, authenticated;
revoke all on table private.controlled_store_compliance from public, anon, authenticated;
revoke all on table private.adult_attestations from public, anon, authenticated;
revoke all on table private.restricted_exclusion_zones from public, anon, authenticated;
revoke all on table private.prescription_evidence from public, anon, authenticated;
revoke all on table private.restricted_handoff_events from public, anon, authenticated;
revoke all on table private.restricted_return_confirmations from public, anon, authenticated;

grant select, insert, update on table private.controlled_category_policies to service_role;
grant select, insert, update on table private.controlled_store_compliance to service_role;
grant select, insert on table private.adult_attestations to service_role;
grant select, insert, update on table private.restricted_exclusion_zones to service_role;
grant select, insert on table private.prescription_evidence to service_role;
grant select, insert on table private.restricted_handoff_events to service_role;
grant select, insert on table private.restricted_return_confirmations to service_role;

create policy dastak_pharmacy_evidence_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'pharmacy'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(pg_catalog.btrim(pg_catalog.split_part(name, '/', 3)), '') is not null
  and pg_catalog.split_part(name, '/', 3) not in ('.', '..')
);

create policy dastak_pharmacy_evidence_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'pharmacy'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(pg_catalog.btrim(pg_catalog.split_part(name, '/', 3)), '') is not null
  and pg_catalog.split_part(name, '/', 3) not in ('.', '..')
);

create policy dastak_prescription_evidence_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'prescription'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(pg_catalog.btrim(pg_catalog.split_part(name, '/', 3)), '') is not null
  and pg_catalog.split_part(name, '/', 3) not in ('.', '..')
);

create policy dastak_prescription_evidence_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'prescription'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and nullif(pg_catalog.btrim(pg_catalog.split_part(name, '/', 3)), '') is not null
  and pg_catalog.split_part(name, '/', 3) not in ('.', '..')
);

create function private.reject_controlled_evidence_mutation()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  raise exception 'controlled category evidence is append-only';
end;
$$;

create function public.browse_controlled_catalogue(
  p_account_id uuid,
  p_scope text,
  p_latitude double precision,
  p_longitude double precision
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_location extensions.geometry(Point, 4326);
  v_zone_id uuid;
  v_policy private.controlled_category_policies%rowtype;
  v_stores jsonb;
  v_categories jsonb;
  v_products jsonb;
begin
  if not private.has_active_membership(p_account_id, 'customer') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active customer account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_scope not in ('medicine', 'tobacco')
    or p_latitude is null or p_latitude not between -90 and 90
    or p_longitude is null or p_longitude not between -180 and 180
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The controlled catalogue request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  v_location := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude), 4326
  );

  select zone.id into v_zone_id
  from public.service_zones as zone
  where zone.active = true
    and extensions.st_covers(zone.boundary, v_location)
  order by zone.created_at, zone.id
  limit 1;

  if v_zone_id is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'The delivery point is outside an active Dastak service area.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  if p_scope = 'tobacco' then
    select policy.* into v_policy
    from private.controlled_category_policies as policy
    where policy.active = true;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'restricted_product_unavailable',
          'message', 'Restricted products are not currently available.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    if not exists (
      select 1 from private.adult_attestations as attestation
      where attestation.customer_account_id = p_account_id
        and attestation.policy_id = v_policy.id
    ) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'adult_attestation_required',
          'message', 'Confirm the current adult-use terms before browsing restricted products.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    if private.is_restricted_location(v_location) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'restricted_location_prohibited',
          'message', 'Restricted products cannot be delivered to this location.'
        )
      );
      response_status := 422;
      return next;
      return;
    end if;
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_product_json(product)
      order by category.display_order, product.name, product.id
    ),
    '[]'::jsonb
  ) into v_products
  from private.catalogue_products as product
  join private.catalogue_categories as category
    on category.id = product.category_id
   and category.store_id = product.store_id
  join private.merchant_stores as store on store.id = product.store_id
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
   and membership.role = 'merchant'
   and membership.approved_at is not null
   and (
     membership.suspended_until is null
     or membership.suspended_until <= pg_catalog.now()
   )
  join private.controlled_store_compliance as compliance
    on compliance.store_id = store.id
   and compliance.scope = p_scope
   and compliance.status = 'approved'
   and (compliance.valid_until is null or compliance.valid_until > pg_catalog.now())
  where store.service_zone_id = v_zone_id
    and store.is_published = true
    and store.accepting_orders = true
    and category.is_active = true
    and product.is_active = true
    and product.availability = 'in_stock'
    and product.restricted_approval_state = 'approved'
    and (
      (
        p_scope = 'medicine'
        and product.catalogue_kind in ('otc_medicine', 'prescription_medicine')
      )
      or (
        p_scope = 'tobacco'
        and product.catalogue_kind = 'paan_corner'
        and product.restricted_tobacco_kind = any(v_policy.allowed_tobacco_kinds)
        and not private.is_restricted_location(store.location)
      )
    );

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_category_json(category)
      order by category.display_order, category.name, category.id
    ),
    '[]'::jsonb
  ) into v_categories
  from private.catalogue_categories as category
  where category.is_active = true
    and exists (
      select 1
      from private.catalogue_products as product
      join private.merchant_stores as store on store.id = product.store_id
      join private.controlled_store_compliance as compliance
        on compliance.store_id = store.id
       and compliance.scope = p_scope
       and compliance.status = 'approved'
       and (compliance.valid_until is null or compliance.valid_until > pg_catalog.now())
      where product.category_id = category.id
        and store.service_zone_id = v_zone_id
        and store.is_published = true
        and store.accepting_orders = true
        and product.is_active = true
        and product.availability = 'in_stock'
        and product.restricted_approval_state = 'approved'
        and (
          (p_scope = 'medicine' and product.catalogue_kind in ('otc_medicine', 'prescription_medicine'))
          or (
            p_scope = 'tobacco'
            and product.catalogue_kind = 'paan_corner'
            and product.restricted_tobacco_kind = any(v_policy.allowed_tobacco_kinds)
            and not private.is_restricted_location(store.location)
          )
        )
    );

  select coalesce(
    pg_catalog.jsonb_agg(
      private.catalogue_store_json(store)
      order by store.name, store.id
    ),
    '[]'::jsonb
  ) into v_stores
  from private.merchant_stores as store
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
   and membership.role = 'merchant'
   and membership.approved_at is not null
   and (
     membership.suspended_until is null
     or membership.suspended_until <= pg_catalog.now()
   )
  join private.controlled_store_compliance as compliance
    on compliance.store_id = store.id
   and compliance.scope = p_scope
   and compliance.status = 'approved'
   and (compliance.valid_until is null or compliance.valid_until > pg_catalog.now())
  where store.service_zone_id = v_zone_id
    and store.is_published = true
    and store.accepting_orders = true
    and (p_scope <> 'tobacco' or not private.is_restricted_location(store.location))
    and exists (
      select 1
      from private.catalogue_products as product
      join private.catalogue_categories as category
        on category.id = product.category_id
       and category.store_id = product.store_id
      where product.store_id = store.id
        and category.is_active = true
        and product.is_active = true
        and product.availability = 'in_stock'
        and product.restricted_approval_state = 'approved'
        and (
          (p_scope = 'medicine' and product.catalogue_kind in ('otc_medicine', 'prescription_medicine'))
          or (
            p_scope = 'tobacco'
            and product.catalogue_kind = 'paan_corner'
            and product.restricted_tobacco_kind = any(v_policy.allowed_tobacco_kinds)
          )
        )
    );

  response_body := pg_catalog.jsonb_build_object(
    'serviceZoneId', v_zone_id,
    'scope', p_scope,
    'policyVersion', case when p_scope = 'tobacco' then v_policy.version else null end,
    'stores', v_stores,
    'categories', v_categories,
    'products', v_products
  );
  response_status := 200;
  return next;
end;
$$;

create function public.quote_controlled_merchant_order(
  p_account_id uuid,
  p_scope text,
  p_store_id uuid,
  p_lines jsonb,
  p_dropoff_latitude double precision,
  p_dropoff_longitude double precision,
  p_prescription_evidence_path text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'quote_controlled_merchant_order';
  v_existing private.request_deduplication%rowtype;
  v_store private.merchant_stores%rowtype;
  v_rate private.merchant_order_rate_cards%rowtype;
  v_policy private.controlled_category_policies%rowtype;
  v_attestation private.adult_attestations%rowtype;
  v_evidence private.prescription_evidence%rowtype;
  v_quote private.merchant_order_quotes%rowtype;
  v_dropoff extensions.geometry(Point, 4326);
  v_requested_count integer;
  v_matched_count integer;
  v_item_subtotal bigint;
  v_requires_prescription boolean;
begin
  if not private.has_active_membership(p_account_id, 'customer') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active customer account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_scope not in ('medicine', 'tobacco')
    or p_store_id is null
    or p_lines is null
    or pg_catalog.jsonb_typeof(p_lines) <> 'array'
    or pg_catalog.jsonb_array_length(p_lines) not between 1 and 50
    or p_dropoff_latitude is null or p_dropoff_latitude not between -90 and 90
    or p_dropoff_longitude is null or p_dropoff_longitude not between -180 and 180
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_lines) as requested(line)
      where pg_catalog.jsonb_typeof(requested.line) <> 'object'
        or coalesce(requested.line ->> 'productId', '') !~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        or case
          when coalesce(requested.line ->> 'quantity', '') ~ '^[0-9]+$'
            then (requested.line ->> 'quantity')::numeric not between 1 and 99
          else true
        end
    )
    or exists (
      select (requested.line ->> 'productId')::uuid
      from pg_catalog.jsonb_array_elements(p_lines) as requested(line)
      group by (requested.line ->> 'productId')::uuid
      having pg_catalog.count(*) > 1
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The controlled checkout quote request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select store.* into v_store
  from private.merchant_stores as store
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
   and membership.role = 'merchant'
   and membership.approved_at is not null
   and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now())
  join private.controlled_store_compliance as compliance
    on compliance.store_id = store.id
   and compliance.scope = p_scope
   and compliance.status = 'approved'
   and (compliance.valid_until is null or compliance.valid_until > pg_catalog.now())
  where store.id = p_store_id
    and store.is_published = true
    and store.accepting_orders = true
  for share of store;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'restricted_product_unavailable',
        'message', 'The merchant is not approved for this controlled category.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  v_dropoff := extensions.st_setsrid(
    extensions.st_makepoint(p_dropoff_longitude, p_dropoff_latitude), 4326
  );

  if not exists (
    select 1 from public.service_zones as zone
    where zone.id = v_store.service_zone_id
      and zone.active = true
      and extensions.st_covers(zone.boundary, v_dropoff)
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'outside_service_area',
        'message', 'The delivery point must be inside the merchant service area.'
      )
    );
    response_status := 422;
    return next;
    return;
  end if;

  if p_scope = 'tobacco' then
    select policy.* into v_policy
    from private.controlled_category_policies as policy
    where policy.active = true
    for share;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'restricted_product_unavailable',
          'message', 'Restricted products are not currently available.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    select attestation.* into v_attestation
    from private.adult_attestations as attestation
    where attestation.customer_account_id = p_account_id
      and attestation.policy_id = v_policy.id;

    if not found then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'adult_attestation_required',
          'message', 'Confirm the current adult-use terms before ordering restricted products.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    if private.is_restricted_location(v_store.location)
      or private.is_restricted_location(v_dropoff)
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'restricted_location_prohibited',
          'message', 'Restricted products cannot be sold or delivered at this location.'
        )
      );
      response_status := 422;
      return next;
      return;
    end if;
  end if;

  select rate.* into v_rate
  from private.merchant_order_rate_cards as rate
  where rate.service_zone_id = v_store.service_zone_id
    and rate.active = true
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'pricing_unavailable',
        'message', 'Checkout pricing is not configured for this service area.'
      )
    );
    response_status := 503;
    return next;
    return;
  end if;

  perform 1
  from pg_catalog.jsonb_array_elements(p_lines) as source(line)
  join private.catalogue_products as product
    on product.id = (source.line ->> 'productId')::uuid
  join private.catalogue_categories as category
    on category.id = product.category_id
   and category.store_id = product.store_id
  where product.store_id = v_store.id
  for share of product, category;

  v_requested_count := pg_catalog.jsonb_array_length(p_lines);
  with requested as (
    select
      (line ->> 'productId')::uuid as product_id,
      (line ->> 'quantity')::integer as quantity
    from pg_catalog.jsonb_array_elements(p_lines) as source(line)
  )
  select
    pg_catalog.count(product.id)::integer,
    coalesce(
      pg_catalog.sum(product.price_paise::bigint * requested.quantity), 0
    ),
    coalesce(pg_catalog.bool_or(product.requires_prescription), false)
  into v_matched_count, v_item_subtotal, v_requires_prescription
  from requested
  join private.catalogue_products as product on product.id = requested.product_id
  join private.catalogue_categories as category
    on category.id = product.category_id
   and category.store_id = product.store_id
  where product.store_id = v_store.id
    and product.is_active = true
    and product.availability = 'in_stock'
    and product.restricted_approval_state = 'approved'
    and category.is_active = true
    and (
      (p_scope = 'medicine' and product.catalogue_kind in ('otc_medicine', 'prescription_medicine'))
      or (
        p_scope = 'tobacco'
        and product.catalogue_kind = 'paan_corner'
        and product.restricted_tobacco_kind = any(v_policy.allowed_tobacco_kinds)
      )
    );

  if v_matched_count <> v_requested_count or v_item_subtotal <= 0 then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'restricted_product_unavailable',
        'message', 'One or more controlled products are unavailable.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_requires_prescription and p_prescription_evidence_path is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'prescription_required',
        'message', 'Prescription evidence is required for this medicine.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if p_prescription_evidence_path is not null then
    if p_scope <> 'medicine'
      or p_prescription_evidence_path <> (
        'prescription/' || p_account_id::text || '/' ||
        pg_catalog.split_part(p_prescription_evidence_path, '/', 3)
      )
      or pg_catalog.array_length(
        pg_catalog.string_to_array(p_prescription_evidence_path, '/'), 1
      ) <> 3
      or nullif(
        pg_catalog.btrim(pg_catalog.split_part(p_prescription_evidence_path, '/', 3)), ''
      ) is null
      or pg_catalog.split_part(p_prescription_evidence_path, '/', 3) in ('.', '..')
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'validation_failed',
          'message', 'The prescription evidence path is invalid.'
        )
      );
      response_status := 400;
      return next;
      return;
    end if;

    if not exists (
      select 1 from storage.objects as object
      where object.bucket_id = 'dastak-evidence'
        and object.name = p_prescription_evidence_path
    ) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'prescription_required',
          'message', 'Upload the prescription evidence before checkout.'
        )
      );
      response_status := 409;
      return next;
      return;
    end if;

    insert into private.prescription_evidence (customer_account_id, object_path)
    values (p_account_id, p_prescription_evidence_path)
    on conflict (customer_account_id, object_path) do nothing;
    select evidence.* into v_evidence
    from private.prescription_evidence as evidence
    where evidence.customer_account_id = p_account_id
      and evidence.object_path = p_prescription_evidence_path;
  end if;

  insert into private.merchant_order_quotes (
    customer_account_id, store_id, rate_card_id, rate_card_version,
    dropoff, item_subtotal_paise, delivery_fee_paise, total_paise,
    expires_at, controlled_scope, controlled_policy_id,
    adult_attestation_id, prescription_evidence_id
  ) values (
    p_account_id, v_store.id, v_rate.id, v_rate.version,
    v_dropoff, v_item_subtotal, v_rate.delivery_fee_paise,
    v_item_subtotal + v_rate.delivery_fee_paise,
    pg_catalog.now() + interval '5 minutes', p_scope,
    case when p_scope = 'tobacco' then v_policy.id else null end,
    case when p_scope = 'tobacco' then v_attestation.id else null end,
    v_evidence.id
  ) returning * into v_quote;

  with requested as (
    select
      (line ->> 'productId')::uuid as product_id,
      (line ->> 'quantity')::integer as quantity
    from pg_catalog.jsonb_array_elements(p_lines) as source(line)
  )
  insert into private.merchant_order_quote_lines (
    quote_id, product_id, product_name, unit_label,
    unit_price_paise, quantity, line_subtotal_paise
  )
  select
    v_quote.id, product.id, product.name, product.unit_label,
    product.price_paise, requested.quantity,
    product.price_paise::bigint * requested.quantity
  from requested
  join private.catalogue_products as product on product.id = requested.product_id;

  response_body := private.controlled_quote_json(v_quote);
  response_status := 200;
  insert into audit.events (
    actor_id, action, entity_type, entity_id, after_state
  ) values (
    p_account_id, 'controlled_merchant_order_quoted',
    'merchant_order_quote', v_quote.id, response_body
  );
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.submit_controlled_product(
  p_account_id uuid,
  p_product_id uuid,
  p_tobacco_kind text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'submit_controlled_product';
  v_existing private.request_deduplication%rowtype;
  v_product private.catalogue_products%rowtype;
  v_before jsonb;
begin
  if not private.has_active_membership(p_account_id, 'merchant') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved merchant account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_product_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or (
      p_tobacco_kind is not null
      and p_tobacco_kind not in ('cigarette', 'cigar', 'rolling_tobacco')
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The controlled-product submission is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select product.* into v_product
  from private.catalogue_products as product
  join private.merchant_stores as store
    on store.id = product.store_id
   and store.merchant_account_id = p_account_id
  where product.id = p_product_id
  for update of product;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_product_not_found',
        'message', 'The controlled product was not found.'
      )
    );
    response_status := 404;
  elsif v_product.catalogue_kind = 'general'
    or (v_product.catalogue_kind = 'paan_corner' and p_tobacco_kind is null)
    or (v_product.catalogue_kind <> 'paan_corner' and p_tobacco_kind is not null)
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The product category and controlled metadata do not match.'
      )
    );
    response_status := 400;
  else
    v_before := private.catalogue_product_json(v_product);
    update private.catalogue_products as product
    set requires_prescription = product.catalogue_kind = 'prescription_medicine',
        restricted_tobacco_kind = case
          when product.catalogue_kind = 'paan_corner' then p_tobacco_kind
          else null
        end,
        restricted_approval_state = 'pending',
        updated_at = pg_catalog.now()
    where product.id = v_product.id
    returning * into v_product;

    response_body := private.catalogue_product_json(v_product);
    response_status := 200;
    insert into audit.events (
      actor_id, action, entity_type, entity_id, before_state, after_state
    ) values (
      p_account_id, 'controlled_product_submitted', 'catalogue_product',
      v_product.id, v_before, response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.review_controlled_product(
  p_owner_id uuid,
  p_product_id uuid,
  p_decision text,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'review_controlled_product';
  v_existing private.request_deduplication%rowtype;
  v_product private.catalogue_products%rowtype;
  v_scope text;
  v_before jsonb;
begin
  if not private.has_active_membership(p_owner_id, 'owner') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only an active owner can review controlled products.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_product_id is null
    or p_decision not in ('approve', 'reject', 'suspend')
    or (p_decision <> 'approve' and nullif(pg_catalog.btrim(p_reason), '') is null)
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The controlled-product review request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_owner_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_owner_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select product.* into v_product
  from private.catalogue_products as product
  where product.id = p_product_id
  for update;

  if not found or v_product.catalogue_kind = 'general' then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_product_not_found',
        'message', 'The controlled product was not found.'
      )
    );
    response_status := 404;
  else
    v_scope := case
      when v_product.catalogue_kind in ('otc_medicine', 'prescription_medicine')
        then 'medicine'
      else 'tobacco'
    end;

    if p_decision = 'approve' and not exists (
      select 1
      from private.controlled_store_compliance as compliance
      where compliance.store_id = v_product.store_id
        and compliance.scope = v_scope
        and compliance.status = 'approved'
        and (
          compliance.valid_until is null
          or compliance.valid_until > pg_catalog.now()
        )
    ) then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'restricted_product_unavailable',
          'message', 'The merchant is not approved for this controlled category.'
        )
      );
      response_status := 409;
    elsif p_decision = 'approve'
      and v_scope = 'tobacco'
      and (
        v_product.restricted_tobacco_kind is null
        or not exists (
          select 1
          from private.controlled_category_policies as policy
          where policy.active = true
            and v_product.restricted_tobacco_kind = any(policy.allowed_tobacco_kinds)
        )
      )
    then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'restricted_product_unavailable',
          'message', 'The tobacco kind is not allowed by the active policy.'
        )
      );
      response_status := 409;
    else
      v_before := private.catalogue_product_json(v_product);
      update private.catalogue_products as product
      set restricted_approval_state = case p_decision
            when 'approve' then 'approved'
            when 'reject' then 'rejected'
            else 'suspended'
          end,
          updated_at = pg_catalog.now()
      where product.id = v_product.id
      returning * into v_product;

      response_body := private.catalogue_product_json(v_product);
      response_status := 200;
      insert into audit.events (
        actor_id, action, entity_type, entity_id, reason, before_state, after_state
      ) values (
        p_owner_id, 'controlled_product_reviewed', 'catalogue_product',
        v_product.id, nullif(pg_catalog.btrim(p_reason), ''),
        v_before, response_body
      );
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_owner_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.upsert_restricted_exclusion_zone(
  p_owner_id uuid,
  p_zone_id uuid,
  p_name text,
  p_kind text,
  p_latitude double precision,
  p_longitude double precision,
  p_radius_meters integer,
  p_active boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_restricted_exclusion_zone';
  v_existing private.request_deduplication%rowtype;
  v_zone private.restricted_exclusion_zones%rowtype;
begin
  if not private.has_active_membership(p_owner_id, 'owner') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only an active owner can configure exclusion zones.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_name is null
    or pg_catalog.char_length(pg_catalog.btrim(p_name)) not between 1 and 120
    or p_kind not in ('school', 'college')
    or p_latitude is null or p_latitude not between -90 and 90
    or p_longitude is null or p_longitude not between -180 and 180
    or p_radius_meters is null or p_radius_meters not between 1 and 5000
    or p_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The restricted exclusion-zone request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_owner_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_owner_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  if p_zone_id is null then
    insert into private.restricted_exclusion_zones (
      name, kind, center, radius_meters, active, created_by
    ) values (
      pg_catalog.btrim(p_name), p_kind,
      extensions.st_setsrid(
        extensions.st_makepoint(p_longitude, p_latitude), 4326
      ),
      p_radius_meters, p_active, p_owner_id
    ) returning * into v_zone;
    response_status := 201;
  else
    update private.restricted_exclusion_zones as exclusion
    set name = pg_catalog.btrim(p_name),
        kind = p_kind,
        center = extensions.st_setsrid(
          extensions.st_makepoint(p_longitude, p_latitude), 4326
        ),
        radius_meters = p_radius_meters,
        active = p_active,
        updated_at = pg_catalog.now()
    where exclusion.id = p_zone_id
    returning * into v_zone;
    response_status := case when found then 200 else 404 end;
  end if;

  if v_zone.id is null then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'exclusion_zone_not_found',
        'message', 'The restricted exclusion zone was not found.'
      )
    );
  else
    response_body := pg_catalog.jsonb_build_object(
      'zoneId', v_zone.id,
      'name', v_zone.name,
      'kind', v_zone.kind,
      'center', pg_catalog.jsonb_build_object(
        'latitude', extensions.st_y(v_zone.center),
        'longitude', extensions.st_x(v_zone.center)
      ),
      'radiusMeters', v_zone.radius_meters,
      'active', v_zone.active
    );
    insert into audit.events (
      actor_id, action, entity_type, entity_id, after_state
    ) values (
      p_owner_id, 'restricted_exclusion_zone_upserted',
      'restricted_exclusion_zone', v_zone.id, response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_owner_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create trigger adult_attestations_immutable
before update or delete on private.adult_attestations
for each row execute function private.reject_controlled_evidence_mutation();
create trigger prescription_evidence_immutable
before update or delete on private.prescription_evidence
for each row execute function private.reject_controlled_evidence_mutation();
create trigger restricted_handoff_events_immutable
before update or delete on private.restricted_handoff_events
for each row execute function private.reject_controlled_evidence_mutation();
create trigger restricted_return_confirmations_immutable
before update or delete on private.restricted_return_confirmations
for each row execute function private.reject_controlled_evidence_mutation();

revoke execute on function private.reject_controlled_evidence_mutation()
  from public, anon, authenticated;
grant execute on function private.reject_controlled_evidence_mutation() to service_role;

create function private.has_active_membership(p_account_id uuid, p_role text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from private.account_memberships as membership
    where membership.account_id = p_account_id
      and membership.role::text = p_role
      and (p_role = 'customer' or membership.approved_at is not null)
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
  );
$$;

create function private.is_restricted_location(p_location extensions.geometry)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from private.restricted_exclusion_zones as exclusion
    where exclusion.active = true
      and extensions.st_dwithin(
        exclusion.center::extensions.geography,
        p_location::extensions.geography,
        exclusion.radius_meters
      )
  );
$$;

create or replace function private.catalogue_product_json(
  product_row private.catalogue_products
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'productId', (product_row).id,
    'storeId', (product_row).store_id,
    'categoryId', (product_row).category_id,
    'name', (product_row).name,
    'description', (product_row).description,
    'unitLabel', (product_row).unit_label,
    'price', pg_catalog.jsonb_build_object('paise', (product_row).price_paise),
    'imageObjectPath', (product_row).image_object_path,
    'availability', (product_row).availability,
    'catalogueKind', (product_row).catalogue_kind,
    'restrictedApprovalState', (product_row).restricted_approval_state,
    'requiresPrescription', (product_row).requires_prescription,
    'restrictedTobaccoKind', (product_row).restricted_tobacco_kind,
    'isActive', (product_row).is_active
  );
$$;

create function private.controlled_policy_json(
  policy_row private.controlled_category_policies
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'policyId', (policy_row).id,
    'version', (policy_row).version,
    'minimumAge', (policy_row).minimum_age,
    'allowedTobaccoKinds', (policy_row).allowed_tobacco_kinds,
    'active', (policy_row).active,
    'createdAt', (policy_row).created_at
  );
$$;

create function private.controlled_store_compliance_json(
  compliance_row private.controlled_store_compliance
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'complianceId', (compliance_row).id,
    'storeId', (compliance_row).store_id,
    'scope', (compliance_row).scope,
    'status', (compliance_row).status,
    'evidenceObjectPath', (compliance_row).evidence_object_path,
    'validUntil', (compliance_row).valid_until,
    'submittedAt', (compliance_row).submitted_at,
    'reviewedAt', (compliance_row).reviewed_at,
    'reviewReason', (compliance_row).review_reason
  );
$$;

create function private.controlled_quote_json(
  quote_row private.merchant_order_quotes
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.merchant_order_quote_json(quote_row)
    || pg_catalog.jsonb_build_object(
      'controlledCategory', pg_catalog.jsonb_build_object(
        'scope', (quote_row).controlled_scope,
        'policyVersion', (
          select policy.version
          from private.controlled_category_policies as policy
          where policy.id = (quote_row).controlled_policy_id
        ),
        'requiresPrescription', (quote_row).prescription_evidence_id is not null
      )
    );
$$;

create function private.controlled_order_json(
  order_row private.merchant_orders
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.merchant_order_json(order_row)
    || pg_catalog.jsonb_build_object(
      'controlledCategory', pg_catalog.jsonb_build_object(
        'scope', (order_row).controlled_scope,
        'policyVersion', (
          select policy.version
          from private.controlled_category_policies as policy
          where policy.id = (order_row).controlled_policy_id
        ),
        'requiresPrescription', (order_row).prescription_evidence_id is not null,
        'restrictedHandoffState', (
          select case handoff.visual_age_check
            when 'passed' then 'passed'
            else 'return_required'
          end
          from private.restricted_handoff_events as handoff
          where handoff.order_id = (order_row).id
        )
      )
    );
$$;

revoke execute on function private.has_active_membership(uuid, text)
  from public, anon, authenticated;
revoke execute on function private.is_restricted_location(extensions.geometry)
  from public, anon, authenticated;
revoke execute on function private.controlled_policy_json(private.controlled_category_policies)
  from public, anon, authenticated;
revoke execute on function private.controlled_store_compliance_json(private.controlled_store_compliance)
  from public, anon, authenticated;
revoke execute on function private.controlled_quote_json(private.merchant_order_quotes)
  from public, anon, authenticated;
revoke execute on function private.controlled_order_json(private.merchant_orders)
  from public, anon, authenticated;
grant execute on function private.has_active_membership(uuid, text) to service_role;
grant execute on function private.is_restricted_location(extensions.geometry) to service_role;
grant execute on function private.controlled_policy_json(private.controlled_category_policies)
  to service_role;
grant execute on function private.controlled_store_compliance_json(private.controlled_store_compliance)
  to service_role;
grant execute on function private.controlled_quote_json(private.merchant_order_quotes)
  to service_role;
grant execute on function private.controlled_order_json(private.merchant_orders)
  to service_role;

create function public.upsert_controlled_category_policy(
  p_owner_id uuid,
  p_version text,
  p_allowed_tobacco_kinds jsonb,
  p_active boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'upsert_controlled_category_policy';
  v_existing private.request_deduplication%rowtype;
  v_kinds text[];
  v_policy private.controlled_category_policies%rowtype;
begin
  if not private.has_active_membership(p_owner_id, 'owner') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only an active owner can configure controlled-category policy.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_version is null
    or pg_catalog.char_length(pg_catalog.btrim(p_version)) not between 1 and 80
    or p_allowed_tobacco_kinds is null
    or pg_catalog.jsonb_typeof(p_allowed_tobacco_kinds) <> 'array'
    or pg_catalog.jsonb_array_length(p_allowed_tobacco_kinds) not between 1 and 3
    or p_active is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
    or exists (
      select 1
      from pg_catalog.jsonb_array_elements_text(p_allowed_tobacco_kinds) as kind(value)
      where kind.value not in ('cigarette', 'cigar', 'rolling_tobacco')
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The controlled-category policy request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  select pg_catalog.array_agg(distinct kind.value order by kind.value)
  into v_kinds
  from pg_catalog.jsonb_array_elements_text(p_allowed_tobacco_kinds) as kind(value);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('controlled-policy', 0)
  );

  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_owner_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select policy.* into v_policy
  from private.controlled_category_policies as policy
  where policy.version = pg_catalog.btrim(p_version)
  for update;

  if found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'policy_version_exists',
        'message', 'Policy versions are immutable. Create a new version.'
      )
    );
    response_status := 409;
  else
    if p_active then
      update private.controlled_category_policies
      set active = false,
          deactivated_at = pg_catalog.now()
      where active = true;
    end if;

    insert into private.controlled_category_policies (
      version, allowed_tobacco_kinds, active, created_by, deactivated_at
    ) values (
      pg_catalog.btrim(p_version),
      v_kinds,
      p_active,
      p_owner_id,
      case when p_active then null else pg_catalog.now() end
    ) returning * into v_policy;

    response_body := private.controlled_policy_json(v_policy);
    response_status := 201;

    insert into audit.events (
      actor_id, action, entity_type, entity_id, after_state
    ) values (
      p_owner_id, 'controlled_policy_created', 'controlled_category_policy',
      v_policy.id, response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_owner_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.record_adult_attestation(
  p_account_id uuid,
  p_policy_version text,
  p_affirmed_adult boolean,
  p_affirmed_not_for_minor boolean,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'record_adult_attestation';
  v_existing private.request_deduplication%rowtype;
  v_policy private.controlled_category_policies%rowtype;
  v_attestation private.adult_attestations%rowtype;
begin
  if not private.has_active_membership(p_account_id, 'customer') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active customer account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_policy_version is null
    or p_affirmed_adult is distinct from true
    or p_affirmed_not_for_minor is distinct from true
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Both adult-use confirmations are required.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);

  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select policy.* into v_policy
  from private.controlled_category_policies as policy
  where policy.active = true
    and policy.version = pg_catalog.btrim(p_policy_version)
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'policy_unavailable',
        'message', 'The current restricted-product terms must be reviewed.'
      )
    );
    response_status := 409;
  else
    insert into private.adult_attestations (
      customer_account_id, policy_id, affirmed_adult, affirmed_not_for_minor
    ) values (p_account_id, v_policy.id, true, true)
    on conflict (customer_account_id, policy_id) do nothing;

    select attestation.* into v_attestation
    from private.adult_attestations as attestation
    where attestation.customer_account_id = p_account_id
      and attestation.policy_id = v_policy.id;

    response_body := pg_catalog.jsonb_build_object(
      'attestationId', v_attestation.id,
      'policyVersion', v_policy.version,
      'attestedAt', v_attestation.attested_at
    );
    response_status := 200;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.submit_controlled_store_compliance(
  p_account_id uuid,
  p_scope text,
  p_evidence_object_path text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'submit_controlled_store_compliance';
  v_existing private.request_deduplication%rowtype;
  v_store private.merchant_stores%rowtype;
  v_compliance private.controlled_store_compliance%rowtype;
begin
  if not private.has_active_membership(p_account_id, 'merchant') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active approved merchant account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_scope not in ('medicine', 'tobacco')
    or (p_scope = 'medicine' and p_evidence_object_path is null)
    or (p_scope = 'tobacco' and p_evidence_object_path is not null)
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The controlled-store compliance request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  if p_scope = 'medicine' and (
    p_evidence_object_path <> (
      'pharmacy/' || p_account_id::text || '/' ||
      pg_catalog.split_part(p_evidence_object_path, '/', 3)
    )
    or pg_catalog.array_length(
      pg_catalog.string_to_array(p_evidence_object_path, '/'), 1
    ) <> 3
    or nullif(
      pg_catalog.btrim(pg_catalog.split_part(p_evidence_object_path, '/', 3)), ''
    ) is null
    or pg_catalog.split_part(p_evidence_object_path, '/', 3) in ('.', '..')
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The pharmacy licence evidence path is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select store.* into v_store
  from private.merchant_stores as store
  where store.merchant_account_id = p_account_id
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'store_required',
        'message', 'Create the merchant store before submitting compliance.'
      )
    );
    response_status := 409;
  elsif p_scope = 'medicine' and not exists (
    select 1 from storage.objects as object
    where object.bucket_id = 'dastak-evidence'
      and object.name = p_evidence_object_path
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'evidence_not_found',
        'message', 'Upload the pharmacy licence evidence before submitting.'
      )
    );
    response_status := 400;
  else
    insert into private.controlled_store_compliance (
      store_id, scope, evidence_object_path
    ) values (v_store.id, p_scope, p_evidence_object_path)
    on conflict (store_id, scope) do update
    set evidence_object_path = excluded.evidence_object_path,
        status = 'pending',
        valid_until = null,
        submitted_at = pg_catalog.now(),
        reviewed_at = null,
        reviewed_by = null,
        review_reason = null,
        updated_at = pg_catalog.now()
    returning * into v_compliance;

    response_body := private.controlled_store_compliance_json(v_compliance);
    response_status := 200;
    insert into audit.events (
      actor_id, action, entity_type, entity_id, after_state
    ) values (
      p_account_id, 'controlled_store_compliance_submitted',
      'controlled_store_compliance', v_compliance.id, response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.review_controlled_store_compliance(
  p_owner_id uuid,
  p_compliance_id uuid,
  p_decision text,
  p_valid_until timestamptz,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'review_controlled_store_compliance';
  v_existing private.request_deduplication%rowtype;
  v_compliance private.controlled_store_compliance%rowtype;
  v_before jsonb;
begin
  if not private.has_active_membership(p_owner_id, 'owner') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only an active owner can review controlled-store compliance.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_compliance_id is null
    or p_decision not in ('approve', 'reject', 'suspend')
    or (p_decision <> 'approve' and nullif(pg_catalog.btrim(p_reason), '') is null)
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The controlled-store review request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_owner_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_owner_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select compliance.* into v_compliance
  from private.controlled_store_compliance as compliance
  where compliance.id = p_compliance_id
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'compliance_not_found',
        'message', 'The controlled-store compliance submission was not found.'
      )
    );
    response_status := 404;
  elsif p_decision = 'approve'
    and v_compliance.scope = 'medicine'
    and (p_valid_until is null or p_valid_until <= pg_catalog.now())
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'An unexpired pharmacy licence validity is required.'
      )
    );
    response_status := 400;
  else
    v_before := private.controlled_store_compliance_json(v_compliance);
    update private.controlled_store_compliance as compliance
    set status = case p_decision
          when 'approve' then 'approved'
          when 'reject' then 'rejected'
          else 'suspended'
        end,
        valid_until = case when p_decision = 'approve' then p_valid_until else null end,
        reviewed_at = pg_catalog.now(),
        reviewed_by = p_owner_id,
        review_reason = nullif(pg_catalog.btrim(p_reason), ''),
        updated_at = pg_catalog.now()
    where compliance.id = v_compliance.id
    returning * into v_compliance;

    response_body := private.controlled_store_compliance_json(v_compliance);
    response_status := 200;
    insert into audit.events (
      actor_id, action, entity_type, entity_id, reason, before_state, after_state
    ) values (
      p_owner_id, 'controlled_store_compliance_reviewed',
      'controlled_store_compliance', v_compliance.id,
      nullif(pg_catalog.btrim(p_reason), ''), v_before, response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_owner_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.create_controlled_merchant_order(
  p_account_id uuid,
  p_quote_id uuid,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'create_controlled_merchant_order';
  v_existing private.request_deduplication%rowtype;
  v_quote private.merchant_order_quotes%rowtype;
  v_store private.merchant_stores%rowtype;
  v_rate private.merchant_order_rate_cards%rowtype;
  v_order private.merchant_orders%rowtype;
  v_line_count integer;
  v_valid_line_count integer;
begin
  if not private.has_active_membership(p_account_id, 'customer') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'An active customer account is required.'
      )
    );
    response_status := 403;
    return next;
    return;
  end if;

  if p_quote_id is null
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The controlled order creation request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select quote.* into v_quote
  from private.merchant_order_quotes as quote
  where quote.id = p_quote_id
    and quote.customer_account_id = p_account_id
    and quote.controlled_scope in ('medicine', 'tobacco')
  for update;

  if not found
    or v_quote.consumed_at is not null
    or v_quote.expires_at <= pg_catalog.now()
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'quote_unavailable',
        'message', 'The controlled checkout quote is missing, expired, or already used.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select store.* into v_store
  from private.merchant_stores as store
  join private.account_memberships as membership
    on membership.account_id = store.merchant_account_id
   and membership.role = 'merchant'
   and membership.approved_at is not null
   and (membership.suspended_until is null or membership.suspended_until <= pg_catalog.now())
  join private.controlled_store_compliance as compliance
    on compliance.store_id = store.id
   and compliance.scope = v_quote.controlled_scope
   and compliance.status = 'approved'
   and (compliance.valid_until is null or compliance.valid_until > pg_catalog.now())
  join public.service_zones as zone
    on zone.id = store.service_zone_id
   and zone.active = true
   and extensions.st_covers(zone.boundary, v_quote.dropoff)
  where store.id = v_quote.store_id
    and store.is_published = true
    and store.accepting_orders = true
  for share of store;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'restricted_product_unavailable',
        'message', 'The merchant is no longer approved for this controlled category.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_quote.controlled_scope = 'tobacco' and (
    not exists (
      select 1
      from private.controlled_category_policies as policy
      join private.adult_attestations as attestation
        on attestation.policy_id = policy.id
       and attestation.id = v_quote.adult_attestation_id
       and attestation.customer_account_id = p_account_id
      where policy.id = v_quote.controlled_policy_id
        and policy.active = true
    )
    or private.is_restricted_location(v_store.location)
    or private.is_restricted_location(v_quote.dropoff)
  ) then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'adult_attestation_required',
        'message', 'The restricted-product approval context changed. Request a new quote.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  select rate.* into v_rate
  from private.merchant_order_rate_cards as rate
  where rate.id = v_quote.rate_card_id
    and rate.service_zone_id = v_store.service_zone_id
    and rate.version = v_quote.rate_card_version
    and rate.delivery_fee_paise = v_quote.delivery_fee_paise
    and rate.active = true
  for share;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'catalogue_changed',
        'message', 'Checkout pricing changed. Request a new quote.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  perform 1
  from private.merchant_order_quote_lines as quote_line
  join private.catalogue_products as product on product.id = quote_line.product_id
  join private.catalogue_categories as category
    on category.id = product.category_id
   and category.store_id = product.store_id
  where quote_line.quote_id = v_quote.id
  for share of product, category;

  select pg_catalog.count(*)::integer into v_line_count
  from private.merchant_order_quote_lines as quote_line
  where quote_line.quote_id = v_quote.id;

  select pg_catalog.count(*)::integer into v_valid_line_count
  from private.merchant_order_quote_lines as quote_line
  join private.catalogue_products as product on product.id = quote_line.product_id
  join private.catalogue_categories as category
    on category.id = product.category_id
   and category.store_id = product.store_id
  where quote_line.quote_id = v_quote.id
    and product.store_id = v_store.id
    and product.name = quote_line.product_name
    and product.unit_label = quote_line.unit_label
    and product.price_paise = quote_line.unit_price_paise
    and product.is_active = true
    and product.availability = 'in_stock'
    and product.restricted_approval_state = 'approved'
    and category.is_active = true
    and (
      (
        v_quote.controlled_scope = 'medicine'
        and product.catalogue_kind in ('otc_medicine', 'prescription_medicine')
      )
      or (
        v_quote.controlled_scope = 'tobacco'
        and product.catalogue_kind = 'paan_corner'
        and exists (
          select 1
          from private.controlled_category_policies as policy
          where policy.id = v_quote.controlled_policy_id
            and policy.active = true
            and product.restricted_tobacco_kind = any(policy.allowed_tobacco_kinds)
        )
      )
    );

  if v_line_count < 1 or v_valid_line_count <> v_line_count then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'restricted_product_unavailable',
        'message', 'The controlled catalogue changed after this quote.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  if v_quote.controlled_scope = 'medicine'
    and exists (
      select 1
      from private.merchant_order_quote_lines as quote_line
      join private.catalogue_products as product on product.id = quote_line.product_id
      where quote_line.quote_id = v_quote.id
        and product.requires_prescription = true
    )
    and v_quote.prescription_evidence_id is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'prescription_required',
        'message', 'Prescription evidence is required for this medicine.'
      )
    );
    response_status := 409;
    return next;
    return;
  end if;

  insert into private.merchant_orders (
    customer_account_id, store_id, service_zone_id, quote_id,
    status, payment_state, dropoff, item_subtotal_paise,
    delivery_fee_paise, total_paise, controlled_scope,
    controlled_policy_id, adult_attestation_id, prescription_evidence_id
  ) values (
    p_account_id, v_store.id, v_store.service_zone_id, v_quote.id,
    'payment_pending', 'payment_pending', v_quote.dropoff,
    v_quote.item_subtotal_paise, v_quote.delivery_fee_paise, v_quote.total_paise,
    v_quote.controlled_scope, v_quote.controlled_policy_id,
    v_quote.adult_attestation_id, v_quote.prescription_evidence_id
  ) returning * into v_order;

  insert into private.merchant_order_lines (
    order_id, product_id, product_name, unit_label,
    unit_price_paise, quantity, line_subtotal_paise
  )
  select
    v_order.id, quote_line.product_id, quote_line.product_name,
    quote_line.unit_label, quote_line.unit_price_paise,
    quote_line.quantity, quote_line.line_subtotal_paise
  from private.merchant_order_quote_lines as quote_line
  where quote_line.quote_id = v_quote.id;

  update private.merchant_order_quotes as quote
  set consumed_at = pg_catalog.now()
  where quote.id = v_quote.id;

  response_body := private.controlled_order_json(v_order);
  response_status := 201;
  insert into audit.events (
    actor_id, action, entity_type, entity_id, after_state
  ) values (
    p_account_id, 'controlled_merchant_order_created',
    'merchant_order', v_order.id, response_body
  );
  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.get_controlled_order_snapshot(
  p_account_id uuid,
  p_order_id uuid
)
returns table (response_body jsonb, response_status integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_order private.merchant_orders%rowtype;
begin
  select merchant_order.* into v_order
  from private.merchant_orders as merchant_order
  join private.merchant_stores as store on store.id = merchant_order.store_id
  where merchant_order.id = p_order_id
    and merchant_order.controlled_scope <> 'general'
    and (
      merchant_order.customer_account_id = p_account_id
      or store.merchant_account_id = p_account_id
      or private.has_active_membership(p_account_id, 'owner')
      or exists (
        select 1 from private.delivery_assignment_attempts as assignment
        where assignment.order_id = merchant_order.id
          and assignment.partner_account_id = p_account_id
      )
    );

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'order_not_found',
        'message', 'The controlled order was not found.'
      )
    );
    response_status := 404;
  else
    response_body := private.controlled_order_json(v_order);
    response_status := 200;
  end if;
  return next;
end;
$$;

create function public.get_order_prescription_evidence_path(
  p_account_id uuid,
  p_order_id uuid
)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select evidence.object_path
  from private.merchant_orders as merchant_order
  join private.merchant_stores as store on store.id = merchant_order.store_id
  join private.prescription_evidence as evidence
    on evidence.id = merchant_order.prescription_evidence_id
  where merchant_order.id = p_order_id
    and merchant_order.controlled_scope = 'medicine'
    and (
      (
        store.merchant_account_id = p_account_id
        and private.has_active_membership(p_account_id, 'merchant')
      )
      or private.has_active_membership(p_account_id, 'owner')
    );
$$;

create function public.get_delivery_assignment_controlled_scope(
  p_account_id uuid,
  p_assignment_id uuid
)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select merchant_order.controlled_scope
  from private.delivery_assignment_attempts as assignment
  join private.merchant_orders as merchant_order on merchant_order.id = assignment.order_id
  where assignment.id = p_assignment_id
    and assignment.partner_account_id = p_account_id;
$$;

create function private.enforce_restricted_handoff()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if old.controlled_scope = 'tobacco'
    and old.status is distinct from 'delivered'
    and new.status = 'delivered'
    and not exists (
      select 1
      from private.restricted_handoff_events as handoff
      where handoff.order_id = old.id
        and handoff.visual_age_check = 'passed'
    )
  then
    raise exception using
      errcode = '23514',
      message = 'restricted_handoff_required';
  end if;
  return new;
end;
$$;

create trigger merchant_order_restricted_handoff
before update of status on private.merchant_orders
for each row
when (old.status is distinct from new.status)
execute function private.enforce_restricted_handoff();

revoke execute on function private.enforce_restricted_handoff()
  from public, anon, authenticated;
grant execute on function private.enforce_restricted_handoff() to service_role;

create function public.verify_restricted_handoff(
  p_account_id uuid,
  p_assignment_id uuid,
  p_verification_code text,
  p_visual_age_check text,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'verify_restricted_handoff';
  v_existing private.request_deduplication%rowtype;
  v_assignment private.delivery_assignment_attempts%rowtype;
  v_order private.merchant_orders%rowtype;
  v_failed_attempts integer;
begin
  if p_assignment_id is null
    or p_verification_code is null
    or p_verification_code !~ '^[0-9]{4}$'
    or p_visual_age_check not in ('passed', 'failed', 'uncertain')
    or (
      p_visual_age_check <> 'passed'
      and nullif(pg_catalog.btrim(p_reason), '') is null
    )
    or (
      p_reason is not null
      and pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 1 and 500
    )
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The restricted handoff request is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select assignment.* into v_assignment
  from private.delivery_assignment_attempts as assignment
  where assignment.id = p_assignment_id
    and assignment.partner_account_id = p_account_id
    and assignment.status = 'accepted'
  for update;

  if not found then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'assignment_not_found',
        'message', 'The active restricted delivery assignment was not found.'
      )
    );
    response_status := 404;
  else
    select merchant_order.* into v_order
    from private.merchant_orders as merchant_order
    where merchant_order.id = v_assignment.order_id
    for update;

    if v_order.controlled_scope <> 'tobacco' or v_order.status <> 'in_transit' then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'invalid_order_transition',
          'message', 'This order is not ready for restricted handoff.'
        )
      );
      response_status := 409;
    elsif v_order.delivery_code_digest is null then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'verification_code_unavailable',
          'message', 'The delivery handoff code is unavailable.'
        )
      );
      response_status := 409;
    elsif v_order.delivery_code_locked_at is not null then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'verification_code_locked',
          'message', 'Handoff verification is locked for owner review.'
        )
      );
      response_status := 423;
    elsif v_order.delivery_code_expires_at <= pg_catalog.now() then
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'verification_code_expired',
          'message', 'The delivery handoff code has expired.'
        )
      );
      response_status := 410;
    elsif v_order.delivery_code_digest <> private.order_handoff_digest(p_verification_code) then
      v_failed_attempts := least(v_order.delivery_code_failed_attempts + 1, 5);
      update private.merchant_orders as merchant_order
      set delivery_code_failed_attempts = v_failed_attempts,
          delivery_code_locked_at = case
            when v_failed_attempts = 5 then pg_catalog.now()
            else null
          end,
          updated_at = pg_catalog.now()
      where merchant_order.id = v_order.id;
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', case
            when v_failed_attempts = 5 then 'verification_code_locked'
            else 'verification_code_invalid'
          end,
          'message', case
            when v_failed_attempts = 5 then 'Handoff verification is locked for owner review.'
            else 'The handoff code is incorrect.'
          end
        )
      );
      response_status := case when v_failed_attempts = 5 then 423 else 422 end;
    else
      insert into private.restricted_handoff_events (
        order_id, assignment_id, partner_account_id, visual_age_check, reason
      ) values (
        v_order.id, v_assignment.id, p_account_id, p_visual_age_check,
        nullif(pg_catalog.btrim(p_reason), '')
      );

      update private.merchant_orders as merchant_order
      set status = case
            when p_visual_age_check = 'passed' then 'delivered'
            else 'returning_to_merchant'
          end,
          state_version = merchant_order.state_version + 1,
          updated_at = pg_catalog.now()
      where merchant_order.id = v_order.id
      returning * into v_order;

      insert into audit.events (
        actor_id, action, entity_type, entity_id, reason, after_state
      ) values (
        p_account_id,
        case when p_visual_age_check = 'passed'
          then 'restricted_handoff_passed'
          else 'restricted_handoff_return_required'
        end,
        'merchant_order', v_order.id,
        nullif(pg_catalog.btrim(p_reason), ''),
        private.controlled_order_json(v_order)
      );

      response_body := private.delivery_partner_dispatch_snapshot_json(p_account_id);
      response_status := 200;
    end if;
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

create function public.confirm_restricted_return(
  p_account_id uuid,
  p_order_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_request_digest text
)
returns table (response_body jsonb, response_status integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_function_name constant text := 'confirm_restricted_return';
  v_existing private.request_deduplication%rowtype;
  v_order private.merchant_orders%rowtype;
begin
  if p_order_id is null
    or p_reason is null
    or pg_catalog.char_length(pg_catalog.btrim(p_reason)) not between 1 and 500
    or nullif(pg_catalog.btrim(p_idempotency_key), '') is null
    or nullif(pg_catalog.btrim(p_request_digest), '') is null
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The restricted return confirmation is invalid.'
      )
    );
    response_status := 400;
    return next;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_account_id::text || ':' || v_function_name, 0)
  );
  select dedup.* into v_existing
  from private.request_deduplication as dedup
  where dedup.account_id = p_account_id
    and dedup.function_name = v_function_name
    and dedup.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_digest = pg_catalog.btrim(p_request_digest) then
      response_body := v_existing.response_body;
      response_status := v_existing.response_status;
    else
      response_body := pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'idempotency_conflict',
          'message', 'The idempotency key was already used with a different request.'
        )
      );
      response_status := 409;
    end if;
    return next;
    return;
  end if;

  select merchant_order.* into v_order
  from private.merchant_orders as merchant_order
  join private.merchant_stores as store
    on store.id = merchant_order.store_id
   and store.merchant_account_id = p_account_id
  where merchant_order.id = p_order_id
  for update of merchant_order;

  if not found or not private.has_active_membership(p_account_id, 'merchant') then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'access_denied',
        'message', 'Only the approved merchant can confirm this return.'
      )
    );
    response_status := 403;
  elsif v_order.controlled_scope <> 'tobacco'
    or v_order.status <> 'returning_to_merchant'
    or v_order.payment_state <> 'paid'
    or not exists (
      select 1 from private.restricted_handoff_events as handoff
      where handoff.order_id = v_order.id
        and handoff.visual_age_check in ('failed', 'uncertain')
    )
  then
    response_body := pg_catalog.jsonb_build_object(
      'error', pg_catalog.jsonb_build_object(
        'code', 'invalid_order_transition',
        'message', 'This order is not awaiting a restricted-item return.'
      )
    );
    response_status := 409;
  else
    insert into private.restricted_return_confirmations (
      order_id, merchant_account_id, reason
    ) values (v_order.id, p_account_id, pg_catalog.btrim(p_reason));

    insert into private.merchant_order_refund_decisions (
      order_id, requested_by_account_id, source, order_status,
      eligibility, decision_status, item_refund_paise,
      delivery_fee_refund_paise, reason
    ) values (
      v_order.id, p_account_id, 'merchant', v_order.status,
      'full_refund', 'eligible', v_order.item_subtotal_paise,
      0, 'Restricted item returned after recipient age check did not pass.'
    );

    update private.merchant_orders as merchant_order
    set payment_state = 'refund_pending',
        state_version = merchant_order.state_version + 1,
        updated_at = pg_catalog.now()
    where merchant_order.id = v_order.id
    returning * into v_order;

    update private.delivery_assignment_attempts as assignment
    set status = 'completed',
        responded_at = coalesce(assignment.responded_at, pg_catalog.now()),
        response_reason = 'restricted_item_returned',
        updated_at = pg_catalog.now()
    where assignment.order_id = v_order.id
      and assignment.status = 'accepted';

    response_body := private.controlled_order_json(v_order);
    response_status := 200;
    insert into audit.events (
      actor_id, action, entity_type, entity_id, reason, after_state
    ) values (
      p_account_id, 'restricted_return_confirmed', 'merchant_order',
      v_order.id, pg_catalog.btrim(p_reason), response_body
    );
  end if;

  insert into private.request_deduplication (
    account_id, function_name, idempotency_key, request_digest,
    response_body, response_status
  ) values (
    p_account_id, v_function_name, pg_catalog.btrim(p_idempotency_key),
    pg_catalog.btrim(p_request_digest), response_body, response_status
  );
  return next;
end;
$$;

revoke execute on function public.upsert_controlled_category_policy(
  uuid, text, jsonb, boolean, text, text
) from public, anon, authenticated;
revoke execute on function public.record_adult_attestation(
  uuid, text, boolean, boolean, text, text
) from public, anon, authenticated;
revoke execute on function public.submit_controlled_store_compliance(
  uuid, text, text, text, text
) from public, anon, authenticated;
revoke execute on function public.review_controlled_store_compliance(
  uuid, uuid, text, timestamp with time zone, text, text, text
) from public, anon, authenticated;
revoke execute on function public.submit_controlled_product(
  uuid, uuid, text, text, text
) from public, anon, authenticated;
revoke execute on function public.review_controlled_product(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated;
revoke execute on function public.upsert_restricted_exclusion_zone(
  uuid, uuid, text, text, double precision, double precision,
  integer, boolean, text, text
) from public, anon, authenticated;
revoke execute on function public.browse_controlled_catalogue(
  uuid, text, double precision, double precision
) from public, anon, authenticated;
revoke execute on function public.quote_controlled_merchant_order(
  uuid, text, uuid, jsonb, double precision, double precision, text, text, text
) from public, anon, authenticated;
revoke execute on function public.create_controlled_merchant_order(
  uuid, uuid, text, text
) from public, anon, authenticated;
revoke execute on function public.get_controlled_order_snapshot(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.get_order_prescription_evidence_path(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.get_delivery_assignment_controlled_scope(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.verify_restricted_handoff(
  uuid, uuid, text, text, text, text, text
) from public, anon, authenticated;
revoke execute on function public.confirm_restricted_return(
  uuid, uuid, text, text, text
) from public, anon, authenticated;

grant execute on function public.upsert_controlled_category_policy(
  uuid, text, jsonb, boolean, text, text
) to service_role;
grant execute on function public.record_adult_attestation(
  uuid, text, boolean, boolean, text, text
) to service_role;
grant execute on function public.submit_controlled_store_compliance(
  uuid, text, text, text, text
) to service_role;
grant execute on function public.review_controlled_store_compliance(
  uuid, uuid, text, timestamp with time zone, text, text, text
) to service_role;
grant execute on function public.submit_controlled_product(
  uuid, uuid, text, text, text
) to service_role;
grant execute on function public.review_controlled_product(
  uuid, uuid, text, text, text, text
) to service_role;
grant execute on function public.upsert_restricted_exclusion_zone(
  uuid, uuid, text, text, double precision, double precision,
  integer, boolean, text, text
) to service_role;
grant execute on function public.browse_controlled_catalogue(
  uuid, text, double precision, double precision
) to service_role;
grant execute on function public.quote_controlled_merchant_order(
  uuid, text, uuid, jsonb, double precision, double precision, text, text, text
) to service_role;
grant execute on function public.create_controlled_merchant_order(
  uuid, uuid, text, text
) to service_role;
grant execute on function public.get_controlled_order_snapshot(uuid, uuid)
  to service_role;
grant execute on function public.get_order_prescription_evidence_path(uuid, uuid)
  to service_role;
grant execute on function public.get_delivery_assignment_controlled_scope(uuid, uuid)
  to service_role;
grant execute on function public.verify_restricted_handoff(
  uuid, uuid, text, text, text, text, text
) to service_role;
grant execute on function public.confirm_restricted_return(
  uuid, uuid, text, text, text
) to service_role;
