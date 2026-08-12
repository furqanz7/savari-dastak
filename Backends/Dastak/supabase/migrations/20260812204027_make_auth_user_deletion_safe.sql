-- Retain financial, fulfilment, and audit history when an Auth user is deleted.
-- Account references are anonymised; operational records must never cascade away.

-- A deleted merchant's historical store must remain available to existing orders,
-- but it can no longer be discovered or accept new work.
create or replace function private.prepare_account_for_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.merchant_stores
  set
    is_published = false,
    accepting_orders = false,
    updated_at = pg_catalog.now()
  where merchant_account_id = old.id;

  return old;
end;
$$;

revoke all on function private.prepare_account_for_deletion() from public, anon, authenticated;

drop trigger if exists accounts_prepare_for_deletion on public.accounts;
create trigger accounts_prepare_for_deletion
before delete on public.accounts
for each row execute function private.prepare_account_for_deletion();

-- Immutable records only permit the one system-generated update needed to
-- anonymise an account when its Auth user is deleted.
create or replace function private.reject_identity_scrub_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_column text := tg_argv[0];
  v_message text := coalesce(tg_argv[1], 'record is append-only');
begin
  if tg_op = 'UPDATE'
    and (pg_catalog.to_jsonb(old) ->> v_column) is not null
    and (pg_catalog.to_jsonb(new) ->> v_column) is null
    and (pg_catalog.to_jsonb(new) - v_column)
      is not distinct from (pg_catalog.to_jsonb(old) - v_column) then
    return new;
  end if;

  raise exception '%', v_message;
end;
$$;

revoke all on function private.reject_identity_scrub_mutation() from public, anon, authenticated;

create or replace function audit.reject_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and old.actor_id is not null
    and new.actor_id is null
    and (pg_catalog.to_jsonb(new) - 'actor_id')
      is not distinct from (pg_catalog.to_jsonb(old) - 'actor_id') then
    return new;
  end if;

  raise exception 'audit.events is append-only';
end;
$$;

revoke all on function audit.reject_event_mutation() from public, anon, authenticated;

drop trigger restricted_handoff_events_immutable on private.restricted_handoff_events;
create trigger restricted_handoff_events_immutable
before update or delete on private.restricted_handoff_events
for each row execute function private.reject_identity_scrub_mutation(
  'partner_account_id',
  'controlled category evidence is append-only'
);

drop trigger restricted_return_confirmations_immutable on private.restricted_return_confirmations;
create trigger restricted_return_confirmations_immutable
before update or delete on private.restricted_return_confirmations
for each row execute function private.reject_identity_scrub_mutation(
  'merchant_account_id',
  'controlled category evidence is append-only'
);

drop trigger adult_attestations_immutable on private.adult_attestations;
create trigger adult_attestations_immutable
before update or delete on private.adult_attestations
for each row execute function private.reject_identity_scrub_mutation(
  'customer_account_id',
  'controlled category evidence is append-only'
);

drop trigger prescription_evidence_immutable on private.prescription_evidence;
create trigger prescription_evidence_immutable
before update or delete on private.prescription_evidence
for each row execute function private.reject_identity_scrub_mutation(
  'customer_account_id',
  'controlled category evidence is append-only'
);

drop trigger merchant_order_refund_decisions_immutable on private.merchant_order_refund_decisions;
create trigger merchant_order_refund_decisions_immutable
before update or delete on private.merchant_order_refund_decisions
for each row execute function private.reject_identity_scrub_mutation(
  'requested_by_account_id',
  'merchant order financial ledger is append-only'
);

-- Direct account references in historical data are intentionally nullable.
alter table audit.events
  drop constraint events_actor_id_fkey;
alter table audit.events
  add constraint events_actor_id_fkey
  foreign key (actor_id) references public.accounts(id) on delete set null;

alter table private.adult_attestations
  alter column customer_account_id drop not null,
  drop constraint adult_attestations_customer_account_id_fkey;
alter table private.adult_attestations
  add constraint adult_attestations_customer_account_id_fkey
  foreign key (customer_account_id) references public.accounts(id) on delete set null;

alter table private.prescription_evidence
  alter column customer_account_id drop not null,
  drop constraint prescription_evidence_customer_account_id_fkey;
alter table private.prescription_evidence
  add constraint prescription_evidence_customer_account_id_fkey
  foreign key (customer_account_id) references public.accounts(id) on delete set null;

alter table private.controlled_category_policies
  alter column created_by drop not null,
  drop constraint controlled_category_policies_created_by_fkey;
alter table private.controlled_category_policies
  add constraint controlled_category_policies_created_by_fkey
  foreign key (created_by) references public.accounts(id) on delete set null;

alter table private.controlled_store_compliance
  alter column reviewed_by drop not null,
  drop constraint controlled_store_compliance_reviewed_by_fkey;
alter table private.controlled_store_compliance
  add constraint controlled_store_compliance_reviewed_by_fkey
  foreign key (reviewed_by) references public.accounts(id) on delete set null;

alter table private.delivery_partner_applications
  alter column reviewed_by drop not null,
  drop constraint delivery_partner_applications_reviewed_by_fkey;
alter table private.delivery_partner_applications
  add constraint delivery_partner_applications_reviewed_by_fkey
  foreign key (reviewed_by) references public.accounts(id) on delete set null;

alter table private.merchant_applications
  alter column reviewed_by drop not null,
  drop constraint merchant_applications_reviewed_by_fkey;
alter table private.merchant_applications
  add constraint merchant_applications_reviewed_by_fkey
  foreign key (reviewed_by) references public.accounts(id) on delete set null;

alter table private.merchant_order_quotes
  alter column customer_account_id drop not null,
  drop constraint merchant_order_quotes_customer_account_id_fkey;
alter table private.merchant_order_quotes
  add constraint merchant_order_quotes_customer_account_id_fkey
  foreign key (customer_account_id) references public.accounts(id) on delete set null;

alter table private.merchant_order_refund_decisions
  alter column requested_by_account_id drop not null,
  drop constraint merchant_order_refund_decisions_requested_by_account_id_fkey;
alter table private.merchant_order_refund_decisions
  add constraint merchant_order_refund_decisions_requested_by_account_id_fkey
  foreign key (requested_by_account_id) references public.accounts(id) on delete set null;

alter table private.merchant_orders
  alter column customer_account_id drop not null,
  drop constraint merchant_orders_customer_account_id_fkey;
alter table private.merchant_orders
  add constraint merchant_orders_customer_account_id_fkey
  foreign key (customer_account_id) references public.accounts(id) on delete set null;

alter table private.merchant_stores
  alter column merchant_account_id drop not null,
  drop constraint merchant_stores_merchant_account_id_fkey;
alter table private.merchant_stores
  add constraint merchant_stores_merchant_account_id_fkey
  foreign key (merchant_account_id) references public.accounts(id) on delete set null;

alter table private.parcel_deliveries
  alter column customer_account_id drop not null,
  alter column recipient_account_id drop not null,
  drop constraint parcel_deliveries_customer_account_id_fkey,
  drop constraint parcel_deliveries_recipient_account_id_fkey;
alter table private.parcel_deliveries
  add constraint parcel_deliveries_customer_account_id_fkey
  foreign key (customer_account_id) references public.accounts(id) on delete set null,
  add constraint parcel_deliveries_recipient_account_id_fkey
  foreign key (recipient_account_id) references public.accounts(id) on delete set null;

alter table private.parcel_quotes
  alter column customer_account_id drop not null,
  drop constraint parcel_quotes_customer_account_id_fkey;
alter table private.parcel_quotes
  add constraint parcel_quotes_customer_account_id_fkey
  foreign key (customer_account_id) references public.accounts(id) on delete set null;

alter table private.parcel_rate_cards
  alter column created_by drop not null,
  drop constraint parcel_rate_cards_created_by_fkey;
alter table private.parcel_rate_cards
  add constraint parcel_rate_cards_created_by_fkey
  foreign key (created_by) references public.accounts(id) on delete set null;

alter table private.restricted_exclusion_zones
  alter column created_by drop not null,
  drop constraint restricted_exclusion_zones_created_by_fkey;
alter table private.restricted_exclusion_zones
  add constraint restricted_exclusion_zones_created_by_fkey
  foreign key (created_by) references public.accounts(id) on delete set null;

alter table private.restricted_handoff_events
  alter column partner_account_id drop not null,
  drop constraint restricted_handoff_events_partner_account_id_fkey;
alter table private.restricted_handoff_events
  add constraint restricted_handoff_events_partner_account_id_fkey
  foreign key (partner_account_id) references public.accounts(id) on delete set null;

alter table private.restricted_return_confirmations
  alter column merchant_account_id drop not null,
  drop constraint restricted_return_confirmations_merchant_account_id_fkey;
alter table private.restricted_return_confirmations
  add constraint restricted_return_confirmations_merchant_account_id_fkey
  foreign key (merchant_account_id) references public.accounts(id) on delete set null;

alter table private.safety_cases
  alter column reporter_account_id drop not null,
  drop constraint safety_cases_reporter_account_id_fkey;
alter table private.safety_cases
  add constraint safety_cases_reporter_account_id_fkey
  foreign key (reporter_account_id) references public.accounts(id) on delete set null;

-- Assignment history remains valid even after the former partner profile is removed.
alter table private.delivery_assignment_attempts
  alter column partner_account_id drop not null,
  drop constraint delivery_assignment_attempts_partner_account_id_fkey;
alter table private.delivery_assignment_attempts
  add constraint delivery_assignment_attempts_partner_account_id_fkey
  foreign key (partner_account_id) references public.accounts(id) on delete set null;

alter table private.parcel_assignment_attempts
  alter column partner_account_id drop not null,
  drop constraint parcel_assignment_attempts_partner_account_id_fkey;
alter table private.parcel_assignment_attempts
  add constraint parcel_assignment_attempts_partner_account_id_fkey
  foreign key (partner_account_id) references public.accounts(id) on delete set null;
