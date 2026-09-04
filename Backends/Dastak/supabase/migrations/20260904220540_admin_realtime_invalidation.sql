-- Admin Realtime is an authenticated invalidation channel. Payloads contain
-- workspace names only; clients always reload authoritative data through the
-- existing Admin APIs.

create or replace function dastak_v1_api.is_active_admin_actor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from dastak_v1.admin_role_assignments assignment
    join public.accounts account
      on account.id = assignment.account_id
      and account.account_state = 'ACTIVE'
    join auth.users auth_user
      on auth_user.id = assignment.account_id
      and pg_catalog.lower(auth_user.email) = assignment.email_normalized
    join private.account_memberships membership
      on membership.account_id = assignment.account_id
      and membership.role = 'owner'
      and membership.approved_at is not null
      and (
        membership.suspended_until is null
        or membership.suspended_until <= pg_catalog.now()
      )
    where assignment.account_id = auth.uid()
  );
$$;

revoke all on function dastak_v1_api.is_active_admin_actor()
  from public, anon, authenticated, service_role;
grant execute on function dastak_v1_api.is_active_admin_actor()
  to authenticated;

drop policy if exists "dastak_admin_control_events" on realtime.messages;
create policy "dastak_admin_control_events"
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (select realtime.topic()) = 'admin-control'
  and (select dastak_v1_api.is_active_admin_actor())
);

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

  if pg_catalog.coalesce(pg_catalog.cardinality(v_workspaces), 0) = 0 then
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

revoke all on function private.send_admin_change(text[], uuid)
  from public, anon, authenticated, service_role;

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

  v_entity_id := pg_catalog.coalesce(
    pg_catalog.nullif(v_row ->> 'id', '')::uuid,
    pg_catalog.nullif(v_row ->> 'account_id', '')::uuid,
    pg_catalog.nullif(v_row ->> 'order_id', '')::uuid
  );

  perform private.send_admin_change(tg_argv, v_entity_id);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.broadcast_admin_change()
  from public, anon, authenticated, service_role;

-- Approvals and order operations are the time-critical Admin surfaces.
drop trigger if exists zzz_admin_merchant_applications_realtime
  on private.merchant_applications;
create trigger zzz_admin_merchant_applications_realtime
after insert or update or delete on private.merchant_applications
for each row execute function private.broadcast_admin_change(
  'merchantApprovals', 'commandCenter', 'network'
);

drop trigger if exists zzz_admin_delivery_applications_realtime
  on private.delivery_partner_applications;
create trigger zzz_admin_delivery_applications_realtime
after insert or update or delete on private.delivery_partner_applications
for each row execute function private.broadcast_admin_change(
  'deliveryApprovals', 'commandCenter', 'network'
);

drop trigger if exists zzz_admin_orders_realtime on dastak_v1.orders;
create trigger zzz_admin_orders_realtime
after insert or update or delete on dastak_v1.orders
for each row execute function private.broadcast_admin_change(
  'operations', 'liveOrders', 'commandCenter'
);

drop trigger if exists zzz_admin_fulfilments_realtime on dastak_v1.fulfilments;
create trigger zzz_admin_fulfilments_realtime
after insert or update or delete on dastak_v1.fulfilments
for each row execute function private.broadcast_admin_change(
  'operations', 'liveOrders', 'commandCenter'
);

drop trigger if exists zzz_admin_delivery_missions_realtime
  on dastak_v1.delivery_missions;
create trigger zzz_admin_delivery_missions_realtime
after insert or update or delete on dastak_v1.delivery_missions
for each row execute function private.broadcast_admin_change(
  'operations', 'liveOrders', 'commandCenter', 'operationalSafety'
);

drop trigger if exists zzz_admin_launch_commitments_realtime
  on dastak_v1.launch_payment_commitments;
create trigger zzz_admin_launch_commitments_realtime
after insert or update or delete on dastak_v1.launch_payment_commitments
for each row execute function private.broadcast_admin_change(
  'operations', 'liveOrders', 'commandCenter'
);

drop trigger if exists zzz_admin_launch_collection_realtime
  on dastak_v1.launch_payment_collection_attempts;
create trigger zzz_admin_launch_collection_realtime
after insert or update or delete on dastak_v1.launch_payment_collection_attempts
for each row execute function private.broadcast_admin_change(
  'operations', 'liveOrders', 'commandCenter'
);

-- The remaining signals keep each independent workspace current without
-- coupling a visible refresh to unrelated requests.
drop trigger if exists zzz_admin_role_assignments_realtime
  on dastak_v1.admin_role_assignments;
create trigger zzz_admin_role_assignments_realtime
after insert or update or delete on dastak_v1.admin_role_assignments
for each row execute function private.broadcast_admin_change(
  'adminAccess', 'commandCenter', 'network'
);

drop trigger if exists zzz_admin_accounts_realtime on public.accounts;
create trigger zzz_admin_accounts_realtime
after insert or update or delete on public.accounts
for each row execute function private.broadcast_admin_change(
  'commandCenter', 'network'
);

drop trigger if exists zzz_admin_personas_realtime on private.account_personas;
create trigger zzz_admin_personas_realtime
after insert or update or delete on private.account_personas
for each row execute function private.broadcast_admin_change(
  'commandCenter', 'network'
);

drop trigger if exists zzz_admin_availability_insert_delete_realtime
  on private.delivery_partner_availability;
create trigger zzz_admin_availability_insert_delete_realtime
after insert or delete on private.delivery_partner_availability
for each row execute function private.broadcast_admin_change(
  'commandCenter', 'network'
);

drop trigger if exists zzz_admin_availability_status_realtime
  on private.delivery_partner_availability;
create trigger zzz_admin_availability_status_realtime
after update of status, available_until on private.delivery_partner_availability
for each row
when (
  old.status is distinct from new.status
  or old.available_until is distinct from new.available_until
)
execute function private.broadcast_admin_change('commandCenter', 'network');

drop trigger if exists zzz_admin_operational_pause_realtime
  on dastak_v1.operational_pause_controls;
create trigger zzz_admin_operational_pause_realtime
after insert or update or delete on dastak_v1.operational_pause_controls
for each row execute function private.broadcast_admin_change(
  'operationalSafety', 'commandCenter'
);

drop trigger if exists zzz_admin_invariant_incidents_realtime
  on dastak_v1.invariant_incidents;
create trigger zzz_admin_invariant_incidents_realtime
after insert or update or delete on dastak_v1.invariant_incidents
for each row execute function private.broadcast_admin_change(
  'systemHealth', 'commandCenter'
);

drop trigger if exists zzz_admin_royalty_withdrawals_realtime
  on dastak_v1.royalty_withdrawals;
create trigger zzz_admin_royalty_withdrawals_realtime
after insert or update or delete on dastak_v1.royalty_withdrawals
for each row execute function private.broadcast_admin_change(
  'royaltyPayouts', 'liveOrders'
);

drop trigger if exists zzz_admin_category_types_realtime
  on dastak_v1.category_types;
create trigger zzz_admin_category_types_realtime
after insert or update or delete on dastak_v1.category_types
for each row execute function private.broadcast_admin_change('catalogue');

drop trigger if exists zzz_admin_categories_realtime on dastak_v1.categories;
create trigger zzz_admin_categories_realtime
after insert or update or delete on dastak_v1.categories
for each row execute function private.broadcast_admin_change('catalogue');

drop trigger if exists zzz_admin_subcategories_realtime on dastak_v1.subcategories;
create trigger zzz_admin_subcategories_realtime
after insert or update or delete on dastak_v1.subcategories
for each row execute function private.broadcast_admin_change('catalogue');

drop trigger if exists zzz_admin_brands_realtime on dastak_v1.brands;
create trigger zzz_admin_brands_realtime
after insert or update or delete on dastak_v1.brands
for each row execute function private.broadcast_admin_change('catalogue');

drop trigger if exists zzz_admin_skus_realtime on dastak_v1.skus;
create trigger zzz_admin_skus_realtime
after insert or update or delete on dastak_v1.skus
for each row execute function private.broadcast_admin_change(
  'catalogue', 'commandCenter'
);

drop trigger if exists zzz_admin_sku_images_realtime on dastak_v1.sku_images;
create trigger zzz_admin_sku_images_realtime
after insert or update or delete on dastak_v1.sku_images
for each row execute function private.broadcast_admin_change('catalogue');

comment on function dastak_v1_api.is_active_admin_actor() is
  'Returns whether the authenticated caller holds an active Dastak Admin assignment.';
comment on function private.send_admin_change(text[], uuid) is
  'Sends private, non-sensitive Admin workspace invalidation signals.';
