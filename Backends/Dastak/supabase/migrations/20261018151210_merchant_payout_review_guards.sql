-- Additive Merchant-only controls. Existing Customer/Delivery/Web operations
-- and financial posting functions remain unchanged. Edge derives p_account_id
-- from its verified bearer; these wrappers are service-role-only.
create function dastak_v1_api.merchant_royalty_controls_snapshot(p_actor_id uuid)
returns table(response_body jsonb,response_status integer)
language plpgsql stable security definer set search_path='' as $$
declare v_body jsonb; v_status integer;
begin
  select r.response_body,r.response_status into v_body,v_status
    from dastak_v1_api.get_royalty_snapshot(p_actor_id,'MERCHANT') r;
  if v_status=200 then
    v_body := pg_catalog.jsonb_set(v_body,'{subjects}',coalesce((
      select pg_catalog.jsonb_agg(s.value || pg_catalog.jsonb_build_object(
        'canManagePayouts',dastak_v1_api.actor_can_manage_royalty_subject(
          p_actor_id,'MERCHANT_ORGANIZATION',(s.value->>'subjectId')::uuid,true)) order by s.ordinality)
      from pg_catalog.jsonb_array_elements(v_body->'subjects') with ordinality s(value,ordinality)
    ),'[]'::jsonb));
  end if;
  return query select v_body,v_status;
end $$;

create function dastak_v1_api.request_merchant_royalty_withdrawal_checked(
  p_actor_id uuid,p_organization_id uuid,p_amount_paise bigint,p_idempotency_key text,
  p_destination_id uuid,p_destination_version bigint
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_destination dastak_v1.royalty_payout_destinations%rowtype;
begin
  if not dastak_v1_api.actor_can_manage_royalty_subject(
      p_actor_id,'MERCHANT_ORGANIZATION',p_organization_id,true) then
    raise exception using errcode='42501',message='Royalty withdrawal permission required';
  end if;
  if p_destination_id is null or p_destination_version is null or p_destination_version<1 then
    raise exception using errcode='22023',message='Reviewed payout destination required';
  end if;
  -- Take the same destination lock as registration, then the same royalty
  -- lock as the existing request. Hold both through validation/reservation.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak-v1-payout-destination:MERCHANT_ORGANIZATION:'||p_organization_id::text,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak-v1-royalty:MERCHANT_ORGANIZATION:'||p_organization_id::text,0));
  -- An already-reserved request must replay its original receipt/destination,
  -- even if the active destination has subsequently changed.
  if exists(select 1 from dastak_v1.royalty_withdrawals w where
      w.subject_type='MERCHANT_ORGANIZATION' and w.subject_id=p_organization_id
      and w.idempotency_key=p_idempotency_key) then
    return dastak_v1_api.request_royalty_withdrawal(
      p_actor_id,'MERCHANT_ORGANIZATION',p_organization_id,p_amount_paise,p_idempotency_key);
  end if;
  select * into v_destination from dastak_v1.royalty_payout_destinations d
    where d.subject_type='MERCHANT_ORGANIZATION' and d.subject_id=p_organization_id and d.status='ACTIVE'
    for share;
  if not found or v_destination.id<>p_destination_id or v_destination.version<>p_destination_version then
    raise exception using errcode='40001',message='REVIEWED_PAYOUT_DESTINATION_CHANGED';
  end if;
  return dastak_v1_api.request_royalty_withdrawal(
    p_actor_id,'MERCHANT_ORGANIZATION',p_organization_id,p_amount_paise,p_idempotency_key);
end $$;

create function public.dastak_v1_merchant_royalty_controls_snapshot(p_account_id uuid)
returns table(response_body jsonb,response_status integer) language sql stable security invoker set search_path='' as $$
  select * from dastak_v1_api.merchant_royalty_controls_snapshot(p_account_id);
$$;
create function public.dastak_v1_request_merchant_royalty_withdrawal_checked(
  p_account_id uuid,p_organization_id uuid,p_amount_paise bigint,p_idempotency_key text,p_destination_id uuid,p_destination_version bigint
) returns jsonb language sql security invoker set search_path='' as $$
  select dastak_v1_api.request_merchant_royalty_withdrawal_checked(
    p_account_id,p_organization_id,p_amount_paise,p_idempotency_key,p_destination_id,p_destination_version);
$$;
revoke all on function dastak_v1_api.merchant_royalty_controls_snapshot(uuid),
  dastak_v1_api.request_merchant_royalty_withdrawal_checked(uuid,uuid,bigint,text,uuid,bigint),
  public.dastak_v1_merchant_royalty_controls_snapshot(uuid),
  public.dastak_v1_request_merchant_royalty_withdrawal_checked(uuid,uuid,bigint,text,uuid,bigint) from public,anon,authenticated,service_role;
grant execute on function dastak_v1_api.merchant_royalty_controls_snapshot(uuid),
  dastak_v1_api.request_merchant_royalty_withdrawal_checked(uuid,uuid,bigint,text,uuid,bigint),
  public.dastak_v1_merchant_royalty_controls_snapshot(uuid),
  public.dastak_v1_request_merchant_royalty_withdrawal_checked(uuid,uuid,bigint,text,uuid,bigint) to service_role;
notify pgrst,'reload schema';
