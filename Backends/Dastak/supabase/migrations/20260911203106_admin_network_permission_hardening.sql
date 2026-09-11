-- The Admin network directory exposes identity and sign-in metadata. Order
-- tracing is intentionally shared with recovery, finance and support roles,
-- so it must not authorize this projection.

insert into dastak_v1.permission_definitions (
  permission_key,
  description,
  sensitivity
) values (
  'platform.network.read',
  'Read the Admin identity and marketplace network directory.',
  'HIGHLY_SENSITIVE'
);

insert into dastak_v1.permission_bundle_permissions (
  bundle_id,
  permission_key
)
select bundle.id, 'platform.network.read'
from dastak_v1.permission_bundles bundle
where bundle.scope = 'PLATFORM'
  and bundle.active
  and bundle.bundle_key in ('platform_super_admin', 'executive_admin')
on conflict (bundle_id, permission_key) do nothing;

create or replace function dastak_v1_api.admin_network_page(
  p_actor_id uuid,
  p_query text default null,
  p_persona text default null,
  p_state text default null,
  p_limit integer default 50,
  p_after_updated_at timestamptz default null,
  p_after_account_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
    p_actor_id, 'platform.network.read'
  );
  if dastak_v1_api.admin_role_for_actor(p_actor_id) is null then
    raise exception using
      errcode = '42501',
      message = 'active Admin assignment required';
  end if;

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
$$;

revoke all on function dastak_v1_api.admin_network_page(
  uuid,text,text,text,integer,timestamptz,uuid
) from public, anon;
grant execute on function dastak_v1_api.admin_network_page(
  uuid,text,text,text,integer,timestamptz,uuid
) to authenticated, service_role;

revoke all on function public.dastak_v1_admin_network_page(
  text,text,text,integer,timestamptz,uuid
) from public, anon;
grant execute on function public.dastak_v1_admin_network_page(
  text,text,text,integer,timestamptz,uuid
) to authenticated, service_role;

comment on function dastak_v1_api.admin_network_page(
  uuid,text,text,text,integer,timestamptz,uuid
) is 'Returns the identity directory only to an active assigned Admin holding platform.network.read.';

comment on function public.dastak_v1_admin_network_page(
  text,text,text,integer,timestamptz,uuid
) is 'Authenticated active-Admin projection for the identity and marketplace network directory.';
