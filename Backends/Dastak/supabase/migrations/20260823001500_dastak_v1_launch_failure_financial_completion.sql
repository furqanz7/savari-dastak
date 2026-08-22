-- Dastak V1 Step 5: launch failure handling and financial completion.

create type dastak_v1.recovery_case_type as enum ('EXACT_SKU', 'DELIVERY');
create type dastak_v1.recovery_case_status as enum (
  'OPEN', 'SEARCHING_EXACT_SKU', 'ACTION_REQUIRED',
  'RECOVERED', 'RECOVERY_FAILED', 'RESOLVED'
);
create type dastak_v1.recovery_fault_source as enum (
  'MERCHANT', 'RIDER', 'DASTAK', 'CUSTOMER', 'UNKNOWN'
);
create type dastak_v1.recovery_opportunity_status as enum (
  'OFFERED', 'SELECTED', 'DECLINED', 'EXPIRED', 'CLOSED'
);
create type dastak_v1.customer_issue_category as enum (
  'WRONG_SKU', 'WRONG_QUANTITY', 'DAMAGED', 'DEFECTIVE', 'EXPIRED',
  'TAMPERED_OR_BROKEN_SEAL', 'INCORRECT_PACKAGE',
  'SUSPECTED_MERCHANT_MISFULFILMENT', 'DELIVERY_PROBLEM', 'OTHER'
);
create type dastak_v1.customer_issue_status as enum (
  'OPEN', 'UNDER_REVIEW', 'RESOLVED', 'REJECTED'
);
create type dastak_v1.return_status as enum (
  'REQUESTED', 'UNDER_REVIEW', 'REJECTED', 'APPROVED',
  'RESOLUTION_WITHOUT_PHYSICAL_RETURN', 'RETURN_REQUIRED', 'RIDER_SEARCH',
  'CUSTOMER_PICKUP', 'IN_RIDER_CUSTODY',
  'RETURNED_TO_ORIGINAL_MERCHANT', 'COMPLETED'
);
create type dastak_v1.return_source as enum ('CUSTOMER_ISSUE', 'DELIVERY_RECOVERY');
create type dastak_v1.return_package_status as enum (
  'CUSTOMER_READY', 'RETURN_RIDER_CUSTODY', 'MERCHANT_RETURN_CUSTODY'
);
create type dastak_v1.return_mission_status as enum (
  'RIDER_SEARCH', 'ASSIGNED', 'AT_CUSTOMER', 'RETURNING_TO_MERCHANTS',
  'COMPLETED', 'CANCELLED'
);
create type dastak_v1.return_stop_status as enum ('PENDING', 'ARRIVED', 'COMPLETED');
create type dastak_v1.refund_status as enum (
  'CREATED', 'APPROVED', 'PROCESSING', 'COMPLETED', 'FAILED'
);
create type dastak_v1.refund_fault_source as enum (
  'MERCHANT', 'RIDER', 'DASTAK', 'CUSTOMER', 'NONE', 'UNKNOWN'
);
create type dastak_v1.settlement_subject_type as enum (
  'MERCHANT_ORGANIZATION', 'RIDER'
);
create type dastak_v1.settlement_entry_type as enum (
  'EARNING', 'BONUS', 'DEBIT_ADJUSTMENT', 'CREDIT_ADJUSTMENT',
  'REFUND_ADJUSTMENT'
);
create type dastak_v1.settlement_status as enum ('PENDING', 'ELIGIBLE', 'SETTLED');
create type dastak_v1.settlement_calculation_status as enum (
  'CALCULATED', 'SYSTEM_CONFIGURATION_REQUIRED'
);

alter type dastak_v1.delivery_mission_status add value 'RECOVERED_RETURNED';

alter table dastak_v1.fulfilments
  alter column source_opportunity_id drop not null,
  add column source_recovery_opportunity_id uuid,
  add constraint fulfilments_exactly_one_source_check check (
    pg_catalog.num_nonnulls(source_opportunity_id, source_recovery_opportunity_id) = 1
  );

create table dastak_v1.recovery_cases (
  id uuid primary key default gen_random_uuid(),
  case_type dastak_v1.recovery_case_type not null,
  order_id uuid not null references dastak_v1.orders(id),
  order_line_id uuid references dastak_v1.order_lines(id),
  source_fulfilment_id uuid references dastak_v1.fulfilments(id),
  delivery_mission_id uuid references dastak_v1.delivery_missions(id),
  replacement_fulfilment_id uuid references dastak_v1.fulfilments(id),
  status dastak_v1.recovery_case_status not null,
  fault_source dastak_v1.recovery_fault_source not null default 'UNKNOWN',
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 500
  ),
  resolution text,
  opened_by uuid not null references public.accounts(id),
  opened_at timestamptz not null default pg_catalog.now(),
  resolved_by uuid references public.accounts(id),
  resolved_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (case_type = 'EXACT_SKU' and order_line_id is not null
      and source_fulfilment_id is not null and delivery_mission_id is null)
    or (case_type = 'DELIVERY' and order_line_id is null
      and source_fulfilment_id is null and delivery_mission_id is not null)
  ),
  check (
    (status in ('RECOVERED', 'RECOVERY_FAILED', 'RESOLVED')
      and resolved_at is not null and resolution is not null)
    or (status not in ('RECOVERED', 'RECOVERY_FAILED', 'RESOLVED')
      and resolved_at is null)
  )
);

create unique index recovery_cases_exact_line_open_uidx
  on dastak_v1.recovery_cases (order_line_id)
  where case_type = 'EXACT_SKU'
    and status in ('OPEN', 'SEARCHING_EXACT_SKU', 'ACTION_REQUIRED');
create unique index recovery_cases_delivery_mission_uidx
  on dastak_v1.recovery_cases (delivery_mission_id)
  where case_type = 'DELIVERY';
create index recovery_cases_order_idx
  on dastak_v1.recovery_cases (order_id, opened_at desc, id);
create index recovery_cases_status_idx
  on dastak_v1.recovery_cases (status, opened_at, id);
create index recovery_cases_actor_idx
  on dastak_v1.recovery_cases (opened_by, opened_at desc);
create index recovery_cases_resolved_by_idx
  on dastak_v1.recovery_cases (resolved_by, resolved_at desc);
create index recovery_cases_source_fulfilment_idx
  on dastak_v1.recovery_cases (source_fulfilment_id);
create index recovery_cases_replacement_fulfilment_idx
  on dastak_v1.recovery_cases (replacement_fulfilment_id);

create table dastak_v1.recovery_opportunities (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references dastak_v1.recovery_cases(id),
  order_id uuid not null references dastak_v1.orders(id),
  order_line_id uuid not null references dastak_v1.order_lines(id),
  sku_id uuid not null references dastak_v1.skus(id),
  organization_id uuid not null references dastak_v1.merchant_organizations(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  requested_quantity integer not null check (requested_quantity > 0),
  status dastak_v1.recovery_opportunity_status not null default 'OFFERED',
  started_at timestamptz not null,
  expires_at timestamptz not null check (expires_at > started_at),
  promised_prep_minutes integer check (promised_prep_minutes > 0),
  responded_by uuid references public.accounts(id),
  responded_at timestamptz,
  closed_reason text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  unique (recovery_case_id, branch_id),
  check (
    (status = 'OFFERED' and responded_by is null and responded_at is null
      and promised_prep_minutes is null)
    or (status = 'SELECTED' and responded_by is not null
      and responded_at is not null and promised_prep_minutes is not null)
    or (status = 'DECLINED' and responded_by is not null
      and responded_at is not null and promised_prep_minutes is null)
    or (status in ('EXPIRED', 'CLOSED') and promised_prep_minutes is null)
  )
);

create unique index recovery_opportunities_one_selected_case_uidx
  on dastak_v1.recovery_opportunities (recovery_case_id)
  where status = 'SELECTED';
create index recovery_opportunities_branch_idx
  on dastak_v1.recovery_opportunities (branch_id, status, expires_at);
create index recovery_opportunities_order_idx
  on dastak_v1.recovery_opportunities (order_id, status, started_at);
create index recovery_opportunities_actor_idx
  on dastak_v1.recovery_opportunities (responded_by, responded_at);

alter table dastak_v1.fulfilments
  add constraint fulfilments_recovery_opportunity_fk
  foreign key (source_recovery_opportunity_id)
  references dastak_v1.recovery_opportunities(id);
create unique index fulfilments_recovery_opportunity_uidx
  on dastak_v1.fulfilments (source_recovery_opportunity_id)
  where source_recovery_opportunity_id is not null;

create table dastak_v1.customer_issues (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  customer_id uuid not null references public.accounts(id),
  order_line_id uuid references dastak_v1.order_lines(id),
  category dastak_v1.customer_issue_category not null,
  status dastak_v1.customer_issue_status not null default 'OPEN',
  description text not null check (
    pg_catalog.char_length(pg_catalog.btrim(description)) between 3 and 1000
  ),
  reported_at timestamptz not null default pg_catalog.now(),
  reviewed_by uuid references public.accounts(id),
  reviewed_at timestamptz,
  resolution text,
  resolved_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (status in ('RESOLVED', 'REJECTED') and resolved_at is not null
      and resolution is not null)
    or (status not in ('RESOLVED', 'REJECTED') and resolved_at is null)
  )
);

create index customer_issues_customer_idx
  on dastak_v1.customer_issues (customer_id, reported_at desc, id);
create index customer_issues_order_idx
  on dastak_v1.customer_issues (order_id, reported_at desc, id);
create index customer_issues_status_idx
  on dastak_v1.customer_issues (status, reported_at, id);
create index customer_issues_order_line_idx
  on dastak_v1.customer_issues (order_line_id, reported_at desc);
create index customer_issues_reviewed_by_idx
  on dastak_v1.customer_issues (reviewed_by, reviewed_at desc);

create table dastak_v1.customer_issue_evidence (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references dastak_v1.customer_issues(id),
  order_id uuid not null references dastak_v1.orders(id),
  order_line_id uuid references dastak_v1.order_lines(id),
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

create index customer_issue_evidence_issue_idx
  on dastak_v1.customer_issue_evidence (issue_id, captured_at, id);
create index customer_issue_evidence_order_idx
  on dastak_v1.customer_issue_evidence (order_id, captured_at, id);
create index customer_issue_evidence_actor_idx
  on dastak_v1.customer_issue_evidence (captured_by, captured_at, id);
create index customer_issue_evidence_line_idx
  on dastak_v1.customer_issue_evidence (order_line_id, captured_at, id);

create table dastak_v1.returns (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  source dastak_v1.return_source not null,
  customer_issue_id uuid references dastak_v1.customer_issues(id),
  delivery_recovery_case_id uuid references dastak_v1.recovery_cases(id),
  status dastak_v1.return_status not null,
  physical_return_required boolean not null,
  approved_refund_amount_paise bigint check (
    approved_refund_amount_paise is null or approved_refund_amount_paise > 0
  ),
  refund_fault_source dastak_v1.refund_fault_source,
  delivery_recovery_fault_source dastak_v1.recovery_fault_source,
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 1000
  ),
  requested_by uuid not null references public.accounts(id),
  requested_at timestamptz not null default pg_catalog.now(),
  decided_by uuid references public.accounts(id),
  decided_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (source = 'CUSTOMER_ISSUE' and customer_issue_id is not null
      and delivery_recovery_case_id is null)
    or (source = 'DELIVERY_RECOVERY' and customer_issue_id is null
      and delivery_recovery_case_id is not null)
  ),
  check (
    (approved_refund_amount_paise is null) = (refund_fault_source is null)
  ),
  check (
    (source = 'CUSTOMER_ISSUE' and delivery_recovery_fault_source is null)
    or (source = 'DELIVERY_RECOVERY' and delivery_recovery_fault_source is not null)
  ),
  check (
    (status in ('REJECTED', 'COMPLETED') and completed_at is not null)
    or (status not in ('REJECTED', 'COMPLETED') and completed_at is null)
  )
);

create unique index returns_customer_issue_uidx
  on dastak_v1.returns (customer_issue_id)
  where customer_issue_id is not null;
create unique index returns_delivery_recovery_uidx
  on dastak_v1.returns (delivery_recovery_case_id)
  where delivery_recovery_case_id is not null;
create index returns_order_idx on dastak_v1.returns (order_id, requested_at desc, id);
create index returns_status_idx on dastak_v1.returns (status, requested_at, id);
create index returns_requested_by_idx on dastak_v1.returns (requested_by, requested_at);
create index returns_decided_by_idx on dastak_v1.returns (decided_by, decided_at);

create table dastak_v1.return_lines (
  return_id uuid not null references dastak_v1.returns(id),
  order_line_id uuid not null references dastak_v1.order_lines(id),
  quantity integer not null check (quantity > 0),
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 500
  ),
  created_at timestamptz not null default pg_catalog.now(),
  primary key (return_id, order_line_id)
);
create index return_lines_order_line_idx
  on dastak_v1.return_lines (order_line_id, return_id);

create table dastak_v1.return_packages (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references dastak_v1.returns(id),
  order_id uuid not null references dastak_v1.orders(id),
  package_number integer not null check (package_number >= 1),
  destination_branch_id uuid not null references dastak_v1.merchant_branches(id),
  source_delivery_package_id uuid references dastak_v1.packages(id),
  status dastak_v1.return_package_status not null,
  current_custody_owner_type dastak_v1.package_custody_owner_type not null,
  current_custody_owner_id uuid not null,
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  picked_up_at timestamptz,
  returned_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  unique (return_id, package_number),
  unique (id, return_id),
  check (
    (status = 'CUSTOMER_READY' and current_custody_owner_type = 'CUSTOMER'
      and picked_up_at is null and returned_at is null)
    or (status = 'RETURN_RIDER_CUSTODY'
      and current_custody_owner_type = 'RETURN_RIDER'
      and picked_up_at is not null and returned_at is null)
    or (status = 'MERCHANT_RETURN_CUSTODY'
      and current_custody_owner_type = 'MERCHANT_RETURN'
      and picked_up_at is not null and returned_at is not null)
  )
);

create unique index return_packages_source_delivery_uidx
  on dastak_v1.return_packages (source_delivery_package_id)
  where source_delivery_package_id is not null;
create index return_packages_return_status_idx
  on dastak_v1.return_packages (return_id, status, package_number);
create index return_packages_destination_idx
  on dastak_v1.return_packages (destination_branch_id, status);
create index return_packages_custody_idx
  on dastak_v1.return_packages (
    current_custody_owner_type, current_custody_owner_id, status
  );

create table dastak_v1.return_missions (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null unique references dastak_v1.returns(id),
  order_id uuid not null references dastak_v1.orders(id),
  status dastak_v1.return_mission_status not null,
  assigned_rider_id uuid references public.accounts(id),
  assigned_transport_type dastak_v1.transport_type,
  source_delivery_mission_id uuid references dastak_v1.delivery_missions(id),
  assigned_at timestamptz,
  arrived_customer_at timestamptz,
  pickup_completed_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (assigned_rider_id is null) = (assigned_transport_type is null)
  ),
  check (
    status in ('RIDER_SEARCH', 'CANCELLED')
    or (assigned_rider_id is not null and assigned_at is not null)
  ),
  check (
    (status = 'COMPLETED' and completed_at is not null)
    or (status <> 'COMPLETED' and completed_at is null)
  )
);

create unique index return_missions_active_rider_uidx
  on dastak_v1.return_missions (assigned_rider_id)
  where assigned_rider_id is not null and status not in ('COMPLETED', 'CANCELLED');
create index return_missions_order_idx
  on dastak_v1.return_missions (order_id, created_at desc, id);
create index return_missions_status_idx
  on dastak_v1.return_missions (status, created_at, id);
create index return_missions_source_delivery_idx
  on dastak_v1.return_missions (source_delivery_mission_id);

create table dastak_v1.return_stops (
  id uuid primary key default gen_random_uuid(),
  return_mission_id uuid not null references dastak_v1.return_missions(id),
  return_id uuid not null references dastak_v1.returns(id),
  branch_id uuid not null references dastak_v1.merchant_branches(id),
  stop_sequence integer not null check (stop_sequence >= 1),
  status dastak_v1.return_stop_status not null default 'PENDING',
  package_count integer not null check (package_count >= 1),
  arrived_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  unique (return_mission_id, branch_id),
  unique (return_mission_id, stop_sequence),
  unique (id, return_mission_id),
  check (
    (status = 'PENDING' and arrived_at is null and completed_at is null)
    or (status = 'ARRIVED' and arrived_at is not null and completed_at is null)
    or (status = 'COMPLETED' and completed_at is not null)
  )
);
create index return_stops_status_idx
  on dastak_v1.return_stops (return_mission_id, status, stop_sequence);
create index return_stops_branch_idx
  on dastak_v1.return_stops (branch_id, status);

create table dastak_v1.return_verifications (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references dastak_v1.returns(id),
  return_mission_id uuid not null references dastak_v1.return_missions(id),
  return_stop_id uuid references dastak_v1.return_stops(id),
  handoff_type dastak_v1.verification_handoff_type not null check (
    handoff_type in ('CUSTOMER_TO_RETURN_RIDER', 'RETURN_RIDER_TO_MERCHANT')
  ),
  status dastak_v1.verification_handoff_status not null default 'INACTIVE',
  code_version integer not null default 1 check (code_version >= 1),
  code_digest bytea not null,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  activated_at timestamptz,
  consumed_at timestamptz,
  consumed_by uuid references public.accounts(id),
  blocked_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (handoff_type = 'CUSTOMER_TO_RETURN_RIDER' and return_stop_id is null)
    or (handoff_type = 'RETURN_RIDER_TO_MERCHANT' and return_stop_id is not null)
  ),
  check (
    (status = 'INACTIVE' and activated_at is null and consumed_at is null
      and blocked_at is null)
    or (status = 'ACTIVE' and activated_at is not null and consumed_at is null
      and blocked_at is null)
    or (status = 'CONSUMED' and activated_at is not null
      and consumed_at is not null and consumed_by is not null)
    or (status = 'BLOCKED' and activated_at is not null and blocked_at is not null)
  )
);

create unique index return_verifications_pickup_uidx
  on dastak_v1.return_verifications (return_id)
  where handoff_type = 'CUSTOMER_TO_RETURN_RIDER';
create unique index return_verifications_receipt_stop_uidx
  on dastak_v1.return_verifications (return_stop_id)
  where handoff_type = 'RETURN_RIDER_TO_MERCHANT';
create index return_verifications_mission_idx
  on dastak_v1.return_verifications (return_mission_id, status, handoff_type);
create index return_verifications_actor_idx
  on dastak_v1.return_verifications (consumed_by, consumed_at);

create table dastak_v1.return_evidence (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references dastak_v1.returns(id),
  return_mission_id uuid not null references dastak_v1.return_missions(id),
  evidence_type text not null check (evidence_type = 'RETURN_PICKUP_PHOTO'),
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
create index return_evidence_return_idx
  on dastak_v1.return_evidence (return_id, captured_at, id);
create index return_evidence_mission_idx
  on dastak_v1.return_evidence (return_mission_id, captured_at, id);
create index return_evidence_actor_idx
  on dastak_v1.return_evidence (captured_by, captured_at, id);

create table dastak_v1.return_evidence_packages (
  evidence_id uuid not null references dastak_v1.return_evidence(id),
  return_package_id uuid not null,
  return_id uuid not null,
  linked_at timestamptz not null default pg_catalog.now(),
  primary key (evidence_id, return_package_id),
  foreign key (return_package_id, return_id)
    references dastak_v1.return_packages(id, return_id)
);
create index return_evidence_packages_package_idx
  on dastak_v1.return_evidence_packages (return_package_id, linked_at);

create table dastak_v1.return_custody_events (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references dastak_v1.returns(id),
  return_mission_id uuid not null references dastak_v1.return_missions(id),
  return_package_id uuid not null references dastak_v1.return_packages(id),
  verification_id uuid not null references dastak_v1.return_verifications(id),
  from_owner_type dastak_v1.package_custody_owner_type not null,
  from_owner_id uuid not null,
  to_owner_type dastak_v1.package_custody_owner_type not null,
  to_owner_id uuid not null,
  transferred_by uuid not null references public.accounts(id),
  transferred_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  unique (return_package_id, verification_id)
);
create index return_custody_events_return_idx
  on dastak_v1.return_custody_events (return_id, transferred_at, id);
create index return_custody_events_mission_idx
  on dastak_v1.return_custody_events (return_mission_id, transferred_at, id);
create index return_custody_events_verification_idx
  on dastak_v1.return_custody_events (verification_id);
create index return_custody_events_actor_idx
  on dastak_v1.return_custody_events (transferred_by, transferred_at);

create table dastak_v1.delivery_address_exceptions (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references dastak_v1.recovery_cases(id),
  order_id uuid not null references dastak_v1.orders(id),
  corrected_address jsonb not null check (
    pg_catalog.jsonb_typeof(corrected_address) = 'object'
  ),
  correction_kind text not null check (correction_kind = 'MINOR_CORRECTION'),
  authorized_by uuid not null references public.accounts(id),
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 10 and 500
  ),
  authorized_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now()
);
create index delivery_address_exceptions_case_idx
  on dastak_v1.delivery_address_exceptions (recovery_case_id, authorized_at, id);
create index delivery_address_exceptions_order_idx
  on dastak_v1.delivery_address_exceptions (order_id, authorized_at, id);
create index delivery_address_exceptions_actor_idx
  on dastak_v1.delivery_address_exceptions (authorized_by, authorized_at);

create table dastak_v1.refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references dastak_v1.orders(id),
  payment_id uuid not null references dastak_v1.payments(id),
  order_line_id uuid references dastak_v1.order_lines(id),
  recovery_case_id uuid references dastak_v1.recovery_cases(id),
  customer_issue_id uuid references dastak_v1.customer_issues(id),
  return_id uuid references dastak_v1.returns(id),
  status dastak_v1.refund_status not null default 'CREATED',
  fault_source dastak_v1.refund_fault_source not null default 'UNKNOWN',
  destination text not null default 'ORIGINAL_PAYMENT_METHOD'
    check (destination = 'ORIGINAL_PAYMENT_METHOD'),
  amount_paise bigint not null check (amount_paise > 0),
  currency_code text not null default 'INR' check (currency_code = 'INR'),
  reason text not null check (
    pg_catalog.char_length(pg_catalog.btrim(reason)) between 3 and 500
  ),
  approval_kind text not null check (
    approval_kind in ('AUTOMATIC_POLICY', 'AUTHORIZED_OPERATIONS')
  ),
  created_by uuid references public.accounts(id),
  created_at timestamptz not null default pg_catalog.now(),
  approved_by uuid references public.accounts(id),
  approved_at timestamptz,
  processing_started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  failure_code text,
  provider text not null default 'RAZORPAY' check (provider = 'RAZORPAY'),
  provider_payment_reference text not null check (
    provider_payment_reference ~ '^pay_[A-Za-z0-9]+$'
  ),
  provider_refund_reference text unique check (
    provider_refund_reference is null
    or provider_refund_reference ~ '^rfnd_[A-Za-z0-9]+$'
  ),
  provider_receipt text not null unique check (
    pg_catalog.char_length(provider_receipt) between 1 and 40
  ),
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (status = 'CREATED' and approved_at is null and processing_started_at is null
      and completed_at is null and failed_at is null)
    or (status = 'APPROVED' and approved_at is not null
      and processing_started_at is null and completed_at is null and failed_at is null)
    or (status = 'PROCESSING' and approved_at is not null
      and processing_started_at is not null and completed_at is null and failed_at is null)
    or (status = 'COMPLETED' and approved_at is not null
      and processing_started_at is not null and completed_at is not null
      and failed_at is null and provider_refund_reference is not null)
    or (status = 'FAILED' and approved_at is not null
      and processing_started_at is not null and completed_at is null
      and failed_at is not null and failure_code is not null)
  )
);

create index refunds_order_idx on dastak_v1.refunds (order_id, created_at desc, id);
create index refunds_status_idx on dastak_v1.refunds (status, created_at, id);
create index refunds_payment_idx on dastak_v1.refunds (payment_id, created_at, id);
create index refunds_line_idx on dastak_v1.refunds (order_line_id, created_at, id);
create index refunds_recovery_idx on dastak_v1.refunds (recovery_case_id, created_at, id);
create index refunds_issue_idx on dastak_v1.refunds (customer_issue_id, created_at, id);
create index refunds_return_idx on dastak_v1.refunds (return_id, created_at, id);
create index refunds_created_by_idx on dastak_v1.refunds (created_by, created_at);
create index refunds_approved_by_idx on dastak_v1.refunds (approved_by, approved_at);

create table dastak_v1.refund_provider_events (
  provider text not null default 'RAZORPAY' check (provider = 'RAZORPAY'),
  provider_event_id text not null check (
    pg_catalog.char_length(provider_event_id) between 1 and 200
  ),
  refund_id uuid not null references dastak_v1.refunds(id),
  order_id uuid not null references dastak_v1.orders(id),
  provider_payment_reference text not null,
  provider_refund_reference text not null,
  amount_paise bigint not null check (amount_paise > 0),
  currency_code text not null default 'INR' check (currency_code = 'INR'),
  occurred_at timestamptz not null,
  request_digest text not null check (request_digest ~ '^[0-9a-f]{64}$'),
  outcome text not null check (outcome in ('COMPLETED', 'DUPLICATE')),
  response_body jsonb not null check (pg_catalog.jsonb_typeof(response_body) = 'object'),
  processed_at timestamptz not null default pg_catalog.now(),
  primary key (provider, provider_event_id)
);
create index refund_provider_events_refund_idx
  on dastak_v1.refund_provider_events (refund_id, processed_at desc);
create index refund_provider_events_order_idx
  on dastak_v1.refund_provider_events (order_id, processed_at desc);
create index refund_provider_events_reference_idx
  on dastak_v1.refund_provider_events (provider_refund_reference);

create table dastak_v1.settlement_entries (
  id uuid primary key default gen_random_uuid(),
  entry_key text not null unique check (
    pg_catalog.char_length(entry_key) between 1 and 240
  ),
  subject_type dastak_v1.settlement_subject_type not null,
  subject_id uuid not null,
  order_id uuid not null references dastak_v1.orders(id),
  fulfilment_id uuid references dastak_v1.fulfilments(id),
  delivery_mission_id uuid references dastak_v1.delivery_missions(id),
  order_line_id uuid references dastak_v1.order_lines(id),
  refund_id uuid references dastak_v1.refunds(id),
  entry_type dastak_v1.settlement_entry_type not null,
  status dastak_v1.settlement_status not null default 'PENDING',
  calculation_status dastak_v1.settlement_calculation_status not null,
  gross_amount_paise bigint check (gross_amount_paise is null or gross_amount_paise >= 0),
  amount_paise bigint,
  currency_code text not null default 'INR' check (currency_code = 'INR'),
  calculation_snapshot jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(calculation_snapshot) = 'object'
  ),
  created_at timestamptz not null default pg_catalog.now(),
  eligible_at timestamptz,
  settled_at timestamptz,
  settlement_reference text,
  updated_at timestamptz not null default pg_catalog.now(),
  version bigint not null default 1 check (version > 0),
  check (
    (calculation_status = 'CALCULATED' and amount_paise is not null)
    or (calculation_status = 'SYSTEM_CONFIGURATION_REQUIRED'
      and amount_paise is null)
  ),
  check (
    (entry_type in ('DEBIT_ADJUSTMENT', 'REFUND_ADJUSTMENT')
      and (amount_paise is null or amount_paise < 0))
    or (entry_type not in ('DEBIT_ADJUSTMENT', 'REFUND_ADJUSTMENT')
      and (amount_paise is null or amount_paise >= 0))
  ),
  check (
    (status = 'PENDING' and eligible_at is null and settled_at is null)
    or (status = 'ELIGIBLE' and eligible_at is not null and settled_at is null)
    or (status = 'SETTLED' and eligible_at is not null and settled_at is not null
      and settlement_reference is not null)
  )
);

create index settlement_entries_subject_idx
  on dastak_v1.settlement_entries (subject_type, subject_id, status, created_at);
create index settlement_entries_order_idx
  on dastak_v1.settlement_entries (order_id, created_at, id);
create index settlement_entries_fulfilment_idx
  on dastak_v1.settlement_entries (fulfilment_id, status, created_at);
create index settlement_entries_mission_idx
  on dastak_v1.settlement_entries (delivery_mission_id, status, created_at);
create index settlement_entries_refund_idx
  on dastak_v1.settlement_entries (refund_id, created_at);

-- Keep every foreign-key lookup indexable under the repository-wide contract.
create index fulfilments_recovery_opportunity_fk_idx
  on dastak_v1.fulfilments (source_recovery_opportunity_id);
create index recovery_cases_order_line_fk_idx
  on dastak_v1.recovery_cases (order_line_id);
create index recovery_cases_delivery_mission_fk_idx
  on dastak_v1.recovery_cases (delivery_mission_id);
create index recovery_opportunities_order_line_fk_idx
  on dastak_v1.recovery_opportunities (order_line_id);
create index recovery_opportunities_sku_fk_idx
  on dastak_v1.recovery_opportunities (sku_id);
create index recovery_opportunities_organization_fk_idx
  on dastak_v1.recovery_opportunities (organization_id);
create index returns_customer_issue_fk_idx
  on dastak_v1.returns (customer_issue_id);
create index returns_delivery_recovery_fk_idx
  on dastak_v1.returns (delivery_recovery_case_id);
create index return_packages_order_fk_idx
  on dastak_v1.return_packages (order_id);
create index return_packages_source_delivery_fk_idx
  on dastak_v1.return_packages (source_delivery_package_id);
create index return_packages_created_by_fk_idx
  on dastak_v1.return_packages (created_by);
create index return_missions_assigned_rider_fk_idx
  on dastak_v1.return_missions (assigned_rider_id);
create index return_stops_return_fk_idx
  on dastak_v1.return_stops (return_id);
create index return_verifications_return_fk_idx
  on dastak_v1.return_verifications (return_id);
create index return_verifications_stop_fk_idx
  on dastak_v1.return_verifications (return_stop_id);
create index return_evidence_packages_composite_fk_idx
  on dastak_v1.return_evidence_packages (return_package_id, return_id);
create index settlement_entries_order_line_fk_idx
  on dastak_v1.settlement_entries (order_line_id);

create table dastak_v1.settlement_entry_history (
  id bigint generated always as identity primary key,
  settlement_entry_id uuid not null references dastak_v1.settlement_entries(id),
  from_status dastak_v1.settlement_status,
  to_status dastak_v1.settlement_status not null,
  entry_version bigint not null check (entry_version > 0),
  changed_by uuid references public.accounts(id),
  reason text not null,
  metadata jsonb not null default '{}'::jsonb check (
    pg_catalog.jsonb_typeof(metadata) = 'object'
  ),
  occurred_at timestamptz not null default pg_catalog.now(),
  unique (settlement_entry_id, entry_version)
);
create index settlement_entry_history_entry_idx
  on dastak_v1.settlement_entry_history (settlement_entry_id, occurred_at, id);
create index settlement_entry_history_actor_idx
  on dastak_v1.settlement_entry_history (changed_by, occurred_at);

insert into dastak_v1.setting_definitions (
  setting_key, value_type, description, default_value,
  validation_rules, protected, requires_explicit_value
) values
  (
    'recovery.radius_meters', 'INTEGER',
    'Maximum exact-SKU recovery search radius.', null,
    '{"minimum":1}'::jsonb, true, true
  ),
  (
    'recovery.offer_timeout_seconds', 'DURATION_SECONDS',
    'Exact-SKU recovery merchant confirmation window.', null,
    '{"minimum":1}'::jsonb, true, true
  ),
  (
    'returns.reporting_window_seconds', 'DURATION_SECONDS',
    'Maximum reporting window for delivered product issues.', null,
    '{"minimum":1}'::jsonb, true, true
  ),
  (
    'returns.pickup_photo_required', 'BOOLEAN',
    'Locked V1 return pickup evidence requirement.', 'true'::jsonb,
    '{"allowedValues":[true]}'::jsonb, true, false
  ),
  (
    'refunds.approval_limit_paise', 'INTEGER',
    'Maximum Operations-authorized refund amount without higher approval.', null,
    '{"minimum":1}'::jsonb, true, true
  ),
  (
    'settlement.merchant_commission_bps', 'INTEGER',
    'Launch merchant commission is locked at zero basis points.', null,
    '{"minimum":0,"maximum":0}'::jsonb, true, true
  );

insert into dastak_v1.permission_definitions (
  permission_key, description, sensitivity
) values
  ('platform.recovery.manage', 'Manage exact-SKU and delivery recovery.', 'HIGHLY_SENSITIVE'),
  ('platform.returns.approve', 'Approve or reject physical returns.', 'HIGHLY_SENSITIVE'),
  ('platform.refunds.approve', 'Approve original-method refunds within policy.', 'HIGHLY_SENSITIVE'),
  ('platform.refunds.process', 'Send approved refunds to the payment provider.', 'HIGHLY_SENSITIVE'),
  ('platform.settlements.manage', 'Finalize settlement eligibility and payouts.', 'HIGHLY_SENSITIVE');

insert into dastak_v1.permission_bundles (
  id, bundle_key, display_name, scope, description
) values
  (
    '10000000-0000-4000-8000-000000000008',
    'recovery_operations', 'Recovery operations', 'PLATFORM',
    'Resolve paid-order, delivery and reverse-custody exceptions.'
  ),
  (
    '10000000-0000-4000-8000-000000000009',
    'finance_operations', 'Finance operations', 'PLATFORM',
    'Approve/process refunds and manage append-only settlements.'
  );

insert into dastak_v1.permission_bundle_permissions (bundle_id, permission_key)
values
  ('10000000-0000-4000-8000-000000000008', 'platform.orders.trace'),
  ('10000000-0000-4000-8000-000000000008', 'platform.recovery.manage'),
  ('10000000-0000-4000-8000-000000000008', 'platform.returns.approve'),
  ('10000000-0000-4000-8000-000000000009', 'platform.orders.trace'),
  ('10000000-0000-4000-8000-000000000009', 'platform.refunds.approve'),
  ('10000000-0000-4000-8000-000000000009', 'platform.refunds.process'),
  ('10000000-0000-4000-8000-000000000009', 'platform.settlements.manage');

-- All Step 5 truth is command-only. Clients receive shaped projections.
alter table dastak_v1.recovery_cases enable row level security;
alter table dastak_v1.recovery_opportunities enable row level security;
alter table dastak_v1.customer_issues enable row level security;
alter table dastak_v1.customer_issue_evidence enable row level security;
alter table dastak_v1.returns enable row level security;
alter table dastak_v1.return_lines enable row level security;
alter table dastak_v1.return_packages enable row level security;
alter table dastak_v1.return_missions enable row level security;
alter table dastak_v1.return_stops enable row level security;
alter table dastak_v1.return_verifications enable row level security;
alter table dastak_v1.return_evidence enable row level security;
alter table dastak_v1.return_evidence_packages enable row level security;
alter table dastak_v1.return_custody_events enable row level security;
alter table dastak_v1.delivery_address_exceptions enable row level security;
alter table dastak_v1.refunds enable row level security;
alter table dastak_v1.refund_provider_events enable row level security;
alter table dastak_v1.settlement_entries enable row level security;
alter table dastak_v1.settlement_entry_history enable row level security;

revoke all on table dastak_v1.recovery_cases,
  dastak_v1.recovery_opportunities, dastak_v1.customer_issues,
  dastak_v1.customer_issue_evidence, dastak_v1.returns,
  dastak_v1.return_lines, dastak_v1.return_packages,
  dastak_v1.return_missions, dastak_v1.return_stops,
  dastak_v1.return_verifications, dastak_v1.return_evidence,
  dastak_v1.return_evidence_packages, dastak_v1.return_custody_events,
  dastak_v1.delivery_address_exceptions, dastak_v1.refunds,
  dastak_v1.refund_provider_events, dastak_v1.settlement_entries,
  dastak_v1.settlement_entry_history
from public, anon, authenticated;

grant select, insert, update on table dastak_v1.recovery_cases,
  dastak_v1.recovery_opportunities, dastak_v1.customer_issues,
  dastak_v1.returns, dastak_v1.return_packages,
  dastak_v1.return_missions, dastak_v1.return_stops,
  dastak_v1.return_verifications, dastak_v1.refunds,
  dastak_v1.settlement_entries
to service_role;
grant select, insert on table dastak_v1.customer_issue_evidence,
  dastak_v1.return_lines, dastak_v1.return_evidence,
  dastak_v1.return_evidence_packages, dastak_v1.return_custody_events,
  dastak_v1.delivery_address_exceptions, dastak_v1.refund_provider_events,
  dastak_v1.settlement_entry_history
to service_role;

create trigger customer_issue_evidence_immutable
before update or delete on dastak_v1.customer_issue_evidence
for each row execute function dastak_v1.reject_mutation();
create trigger return_lines_immutable
before update or delete on dastak_v1.return_lines
for each row execute function dastak_v1.reject_mutation();
create trigger return_evidence_immutable
before update or delete on dastak_v1.return_evidence
for each row execute function dastak_v1.reject_mutation();
create trigger return_evidence_packages_immutable
before update or delete on dastak_v1.return_evidence_packages
for each row execute function dastak_v1.reject_mutation();
create trigger return_custody_events_immutable
before update or delete on dastak_v1.return_custody_events
for each row execute function dastak_v1.reject_mutation();
create trigger delivery_address_exceptions_immutable
before update or delete on dastak_v1.delivery_address_exceptions
for each row execute function dastak_v1.reject_mutation();
create trigger refund_provider_events_immutable
before update or delete on dastak_v1.refund_provider_events
for each row execute function dastak_v1.reject_mutation();
create trigger settlement_entry_history_immutable
before update or delete on dastak_v1.settlement_entry_history
for each row execute function dastak_v1.reject_mutation();

create policy dastak_v1_customer_issue_evidence_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'customer-issue'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and pg_catalog.split_part(name, '/', 3)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.(jpg|jpeg|png|heic)$'
);
create policy dastak_v1_customer_issue_evidence_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'customer-issue'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and pg_catalog.split_part(name, '/', 3)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.(jpg|jpeg|png|heic)$'
);
create policy dastak_v1_return_pickup_evidence_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'return-pickup'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and pg_catalog.split_part(name, '/', 3)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.(jpg|jpeg|png|heic)$'
);
create policy dastak_v1_return_pickup_evidence_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'dastak-evidence'
  and pg_catalog.array_length(pg_catalog.string_to_array(name, '/'), 1) = 3
  and pg_catalog.split_part(name, '/', 1) = 'return-pickup'
  and pg_catalog.split_part(name, '/', 2) = (select auth.uid())::text
  and pg_catalog.split_part(name, '/', 3)
    ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.(jpg|jpeg|png|heic)$'
);

create function dastak_v1.guard_recovery_case()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.case_type is distinct from old.case_type
    or new.order_id is distinct from old.order_id
    or new.order_line_id is distinct from old.order_line_id
    or new.source_fulfilment_id is distinct from old.source_fulfilment_id
    or new.delivery_mission_id is distinct from old.delivery_mission_id
    or new.reason is distinct from old.reason
    or new.opened_by is distinct from old.opened_by
    or new.opened_at is distinct from old.opened_at then
    raise exception 'recovery case identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'recovery case version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'OPEN' and new.status in (
      'SEARCHING_EXACT_SKU', 'ACTION_REQUIRED', 'RESOLVED'
    ))
    or (old.status = 'SEARCHING_EXACT_SKU'
      and new.status in ('RECOVERED', 'RECOVERY_FAILED'))
    or (old.status = 'ACTION_REQUIRED' and new.status = 'RESOLVED')
  ) then
    raise exception 'invalid recovery transition: % -> %', old.status, new.status;
  end if;
  if old.replacement_fulfilment_id is not null
    and new.replacement_fulfilment_id is distinct from old.replacement_fulfilment_id then
    raise exception 'replacement fulfilment cannot change';
  end if;
  if old.resolved_at is not null and new.resolved_at is distinct from old.resolved_at then
    raise exception 'recovery resolution timestamp cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_recovery_opportunity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.recovery_case_id is distinct from old.recovery_case_id
    or new.order_id is distinct from old.order_id
    or new.order_line_id is distinct from old.order_line_id
    or new.sku_id is distinct from old.sku_id
    or new.organization_id is distinct from old.organization_id
    or new.branch_id is distinct from old.branch_id
    or new.requested_quantity is distinct from old.requested_quantity
    or new.started_at is distinct from old.started_at
    or new.expires_at is distinct from old.expires_at
    or new.created_at is distinct from old.created_at then
    raise exception 'recovery opportunity identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'recovery opportunity version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    old.status = 'OFFERED'
    and new.status in ('SELECTED', 'DECLINED', 'EXPIRED', 'CLOSED')
  ) then
    raise exception 'invalid recovery opportunity transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_customer_issue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.customer_id is distinct from old.customer_id
    or new.order_line_id is distinct from old.order_line_id
    or new.category is distinct from old.category
    or new.description is distinct from old.description
    or new.reported_at is distinct from old.reported_at then
    raise exception 'customer issue report cannot be rewritten';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'customer issue version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'OPEN' and new.status in ('UNDER_REVIEW', 'RESOLVED', 'REJECTED'))
    or (old.status = 'UNDER_REVIEW' and new.status in ('RESOLVED', 'REJECTED'))
  ) then
    raise exception 'invalid customer issue transition: % -> %', old.status, new.status;
  end if;
  if old.resolved_at is not null and new.resolved_at is distinct from old.resolved_at then
    raise exception 'customer issue resolution cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_return()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.source is distinct from old.source
    or new.customer_issue_id is distinct from old.customer_issue_id
    or new.delivery_recovery_case_id is distinct from old.delivery_recovery_case_id
    or new.physical_return_required is distinct from old.physical_return_required
    or new.approved_refund_amount_paise is distinct from old.approved_refund_amount_paise
    or new.refund_fault_source is distinct from old.refund_fault_source
    or new.delivery_recovery_fault_source is distinct from old.delivery_recovery_fault_source
    or new.reason is distinct from old.reason
    or new.requested_by is distinct from old.requested_by
    or new.requested_at is distinct from old.requested_at then
    raise exception 'return decision identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'return version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'REQUESTED' and new.status in ('UNDER_REVIEW', 'REJECTED', 'APPROVED'))
    or (old.status = 'UNDER_REVIEW' and new.status in ('REJECTED', 'APPROVED'))
    or (old.status = 'APPROVED' and new.status in (
      'RESOLUTION_WITHOUT_PHYSICAL_RETURN', 'RETURN_REQUIRED'
    ))
    or (old.status = 'RESOLUTION_WITHOUT_PHYSICAL_RETURN' and new.status = 'COMPLETED')
    or (old.status = 'RETURN_REQUIRED' and new.status in (
      'RIDER_SEARCH', 'IN_RIDER_CUSTODY'
    ))
    or (old.status = 'RIDER_SEARCH' and new.status = 'CUSTOMER_PICKUP')
    or (old.status = 'CUSTOMER_PICKUP' and new.status = 'IN_RIDER_CUSTODY')
    or (old.status = 'IN_RIDER_CUSTODY'
      and new.status = 'RETURNED_TO_ORIGINAL_MERCHANT')
    or (old.status = 'RETURNED_TO_ORIGINAL_MERCHANT' and new.status = 'COMPLETED')
  ) then
    raise exception 'invalid return transition: % -> %', old.status, new.status;
  end if;
  if old.decided_at is not null and new.decided_at is distinct from old.decided_at then
    raise exception 'return decision timestamp cannot change';
  end if;
  if old.completed_at is not null and new.completed_at is distinct from old.completed_at then
    raise exception 'return completion timestamp cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_return_package()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_verification_id uuid;
begin
  if new.id is distinct from old.id
    or new.return_id is distinct from old.return_id
    or new.order_id is distinct from old.order_id
    or new.package_number is distinct from old.package_number
    or new.destination_branch_id is distinct from old.destination_branch_id
    or new.source_delivery_package_id is distinct from old.source_delivery_package_id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'return package identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'return package version must increment exactly once';
  end if;
  begin
    v_verification_id := nullif(
      pg_catalog.current_setting('dastak_v1.return_verification_id', true), ''
    )::uuid;
  exception when invalid_text_representation then
    v_verification_id := null;
  end;
  if old.status = 'CUSTOMER_READY' and new.status = 'RETURN_RIDER_CUSTODY' then
    if v_verification_id is null
      or old.current_custody_owner_type <> 'CUSTOMER'
      or new.current_custody_owner_type <> 'RETURN_RIDER'
      or new.picked_up_at is null
      or not exists (
        select 1
        from dastak_v1.return_verifications verification
        join dastak_v1.return_missions mission
          on mission.id = verification.return_mission_id
        where verification.id = v_verification_id
          and verification.return_id = new.return_id
          and verification.handoff_type = 'CUSTOMER_TO_RETURN_RIDER'
          and verification.status = 'CONSUMED'
          and verification.consumed_by = new.current_custody_owner_id
          and mission.assigned_rider_id = new.current_custody_owner_id
      ) then
      raise exception 'return pickup requires consumed customer handoff verification';
    end if;
  elsif old.status = 'RETURN_RIDER_CUSTODY'
    and new.status = 'MERCHANT_RETURN_CUSTODY' then
    if v_verification_id is null
      or old.current_custody_owner_type <> 'RETURN_RIDER'
      or new.current_custody_owner_type <> 'MERCHANT_RETURN'
      or new.current_custody_owner_id <> new.destination_branch_id
      or new.returned_at is null
      or not exists (
        select 1
        from dastak_v1.return_verifications verification
        join dastak_v1.return_stops stop on stop.id = verification.return_stop_id
        join dastak_v1.return_missions mission
          on mission.id = verification.return_mission_id
        where verification.id = v_verification_id
          and verification.return_id = new.return_id
          and verification.handoff_type = 'RETURN_RIDER_TO_MERCHANT'
          and verification.status = 'CONSUMED'
          and stop.branch_id = new.destination_branch_id
          and mission.assigned_rider_id = old.current_custody_owner_id
      ) then
      raise exception 'return receipt requires consumed merchant handoff verification';
    end if;
  elsif new.status is distinct from old.status
    or new.current_custody_owner_type is distinct from old.current_custody_owner_type
    or new.current_custody_owner_id is distinct from old.current_custody_owner_id then
    raise exception 'invalid return package custody transition';
  end if;
  if old.picked_up_at is not null and new.picked_up_at is distinct from old.picked_up_at then
    raise exception 'return pickup timestamp cannot change';
  end if;
  if old.returned_at is not null and new.returned_at is distinct from old.returned_at then
    raise exception 'return receipt timestamp cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_return_mission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.return_id is distinct from old.return_id
    or new.order_id is distinct from old.order_id
    or new.source_delivery_mission_id is distinct from old.source_delivery_mission_id
    or new.created_at is distinct from old.created_at then
    raise exception 'return mission identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'return mission version must increment exactly once';
  end if;
  if old.assigned_rider_id is not null
    and new.assigned_rider_id is distinct from old.assigned_rider_id then
    raise exception 'assigned return rider cannot change after custody begins';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'RIDER_SEARCH' and new.status in ('ASSIGNED', 'CANCELLED'))
    or (old.status = 'ASSIGNED' and new.status in ('AT_CUSTOMER', 'CANCELLED'))
    or (old.status = 'AT_CUSTOMER' and new.status = 'RETURNING_TO_MERCHANTS')
    or (old.status = 'RETURNING_TO_MERCHANTS' and new.status = 'COMPLETED')
  ) then
    raise exception 'invalid return mission transition: % -> %', old.status, new.status;
  end if;
  if old.arrived_customer_at is not null
    and new.arrived_customer_at is distinct from old.arrived_customer_at then
    raise exception 'return customer arrival cannot change';
  end if;
  if old.pickup_completed_at is not null
    and new.pickup_completed_at is distinct from old.pickup_completed_at then
    raise exception 'return pickup completion cannot change';
  end if;
  if old.completed_at is not null and new.completed_at is distinct from old.completed_at then
    raise exception 'return mission completion cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_return_stop()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.return_mission_id is distinct from old.return_mission_id
    or new.return_id is distinct from old.return_id
    or new.branch_id is distinct from old.branch_id
    or new.stop_sequence is distinct from old.stop_sequence
    or new.package_count is distinct from old.package_count
    or new.created_at is distinct from old.created_at then
    raise exception 'return stop identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'return stop version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'PENDING' and new.status = 'ARRIVED')
    or (old.status = 'ARRIVED' and new.status = 'COMPLETED')
  ) then
    raise exception 'invalid return stop transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_return_verification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.return_id is distinct from old.return_id
    or new.return_mission_id is distinct from old.return_mission_id
    or new.return_stop_id is distinct from old.return_stop_id
    or new.handoff_type is distinct from old.handoff_type
    or new.code_version is distinct from old.code_version
    or new.code_digest is distinct from old.code_digest
    or new.created_at is distinct from old.created_at then
    raise exception 'return verification identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'return verification version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'INACTIVE' and new.status = 'ACTIVE')
    or (old.status = 'ACTIVE' and new.status in ('CONSUMED', 'BLOCKED'))
  ) then
    raise exception 'invalid return verification transition: % -> %', old.status, new.status;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_refund()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.order_id is distinct from old.order_id
    or new.payment_id is distinct from old.payment_id
    or new.order_line_id is distinct from old.order_line_id
    or new.recovery_case_id is distinct from old.recovery_case_id
    or new.customer_issue_id is distinct from old.customer_issue_id
    or new.return_id is distinct from old.return_id
    or new.fault_source is distinct from old.fault_source
    or new.destination is distinct from old.destination
    or new.amount_paise is distinct from old.amount_paise
    or new.currency_code is distinct from old.currency_code
    or new.reason is distinct from old.reason
    or new.approval_kind is distinct from old.approval_kind
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at
    or new.provider is distinct from old.provider
    or new.provider_payment_reference is distinct from old.provider_payment_reference
    or new.provider_receipt is distinct from old.provider_receipt then
    raise exception 'refund financial identity cannot change';
  end if;
  if new.version <> old.version + 1 then
    raise exception 'refund version must increment exactly once';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'CREATED' and new.status = 'APPROVED')
    or (old.status = 'APPROVED' and new.status = 'PROCESSING')
    or (old.status = 'PROCESSING' and new.status in ('COMPLETED', 'FAILED'))
    or (old.status = 'FAILED' and new.status = 'PROCESSING')
  ) then
    raise exception 'invalid refund transition: % -> %', old.status, new.status;
  end if;
  if old.provider_refund_reference is not null
    and new.provider_refund_reference is distinct from old.provider_refund_reference then
    raise exception 'provider refund reference cannot change';
  end if;
  if old.completed_at is not null and new.completed_at is distinct from old.completed_at then
    raise exception 'refund completion timestamp cannot change';
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.guard_settlement_entry()
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
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function dastak_v1.record_settlement_entry_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status
    or new.calculation_status is distinct from old.calculation_status then
    insert into dastak_v1.settlement_entry_history (
      settlement_entry_id, from_status, to_status, entry_version,
      changed_by, reason, metadata
    ) values (
      new.id,
      case when tg_op = 'INSERT' then null else old.status end,
      new.status,
      new.version,
      nullif(pg_catalog.current_setting('dastak_v1.settlement_actor_id', true), '')::uuid,
      coalesce(
        nullif(pg_catalog.current_setting('dastak_v1.settlement_reason', true), ''),
        case when tg_op = 'INSERT' then 'Settlement entry created.'
          else 'Settlement entry advanced.' end
      ),
      pg_catalog.jsonb_build_object(
        'entryType', new.entry_type,
        'calculationStatus', new.calculation_status,
        'amountPaise', new.amount_paise
      )
    );
  end if;
  return new;
end;
$$;

create trigger recovery_cases_guard before update on dastak_v1.recovery_cases
for each row execute function dastak_v1.guard_recovery_case();
create trigger recovery_cases_no_delete before delete on dastak_v1.recovery_cases
for each row execute function dastak_v1.reject_delete();
create trigger recovery_opportunities_guard before update on dastak_v1.recovery_opportunities
for each row execute function dastak_v1.guard_recovery_opportunity();
create trigger recovery_opportunities_no_delete before delete on dastak_v1.recovery_opportunities
for each row execute function dastak_v1.reject_delete();
create trigger customer_issues_guard before update on dastak_v1.customer_issues
for each row execute function dastak_v1.guard_customer_issue();
create trigger customer_issues_no_delete before delete on dastak_v1.customer_issues
for each row execute function dastak_v1.reject_delete();
create trigger returns_guard before update on dastak_v1.returns
for each row execute function dastak_v1.guard_return();
create trigger returns_no_delete before delete on dastak_v1.returns
for each row execute function dastak_v1.reject_delete();
create trigger return_packages_guard before update on dastak_v1.return_packages
for each row execute function dastak_v1.guard_return_package();
create trigger return_packages_no_delete before delete on dastak_v1.return_packages
for each row execute function dastak_v1.reject_delete();
create trigger return_missions_guard before update on dastak_v1.return_missions
for each row execute function dastak_v1.guard_return_mission();
create trigger return_missions_no_delete before delete on dastak_v1.return_missions
for each row execute function dastak_v1.reject_delete();
create trigger return_stops_guard before update on dastak_v1.return_stops
for each row execute function dastak_v1.guard_return_stop();
create trigger return_stops_no_delete before delete on dastak_v1.return_stops
for each row execute function dastak_v1.reject_delete();
create trigger return_verifications_guard before update on dastak_v1.return_verifications
for each row execute function dastak_v1.guard_return_verification();
create trigger return_verifications_no_delete before delete on dastak_v1.return_verifications
for each row execute function dastak_v1.reject_delete();
create trigger refunds_guard before update on dastak_v1.refunds
for each row execute function dastak_v1.guard_refund();
create trigger refunds_no_delete before delete on dastak_v1.refunds
for each row execute function dastak_v1.reject_delete();
create trigger settlement_entries_guard before update on dastak_v1.settlement_entries
for each row execute function dastak_v1.guard_settlement_entry();
create trigger settlement_entries_no_delete before delete on dastak_v1.settlement_entries
for each row execute function dastak_v1.reject_delete();
create trigger settlement_entries_history
after insert or update on dastak_v1.settlement_entries
for each row execute function dastak_v1.record_settlement_entry_history();

-- Recovery fulfilments preserve their exact source rather than rewriting the
-- original selected opportunity.
create or replace function dastak_v1.guard_fulfilment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
  if old.status = 'PREPARING' and new.status = 'RELEASED' and (
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
$$;
