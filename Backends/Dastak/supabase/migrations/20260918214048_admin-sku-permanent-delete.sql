-- Permanent SKU deletion is allowed only when the SKU has never entered an
-- order/inventory workflow. Historical or operational references remain
-- archive-only so they cannot be orphaned.
create or replace function dastak_v1_api.admin_catalogue_sku_delete(
  p_actor_id uuid,
  p_sku_id uuid,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_name text;
  v_refs bigint;
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id, 'platform.catalogue.manage');
  if p_sku_id is null or p_idempotency_key is null or char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode='22023', message='invalid SKU deletion request';
  end if;
  select canonical_name into v_name from dastak_v1.skus where id=p_sku_id for update;
  if v_name is null then raise exception using errcode='P0002', message='SKU not found'; end if;
  select count(*) into v_refs from (
    select 1 from dastak_v1.order_lines where sku_id=p_sku_id
    union all select 1 from dastak_v1.merchant_stock_reservations where sku_id=p_sku_id
    union all select 1 from dastak_v1.merchant_sku_selections where sku_id=p_sku_id
    union all select 1 from dastak_v1.merchant_opportunity_lines where sku_id=p_sku_id
    union all select 1 from dastak_v1.recovery_opportunities where sku_id=p_sku_id
  ) refs;
  if v_refs > 0 then
    raise exception using errcode='23503', message='SKU has historical or operational references and can only be archived';
  end if;
  delete from dastak_v1.skus where id=p_sku_id;
  insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
  values (p_actor_id, 'CATALOGUE_SKU_DELETED', 'catalogue_sku', p_sku_id,
    jsonb_build_object('idempotencyKey',p_idempotency_key,'name',v_name));
  return jsonb_build_object('deleted',true,'id',p_sku_id,'name',v_name);
end;
$$;

create or replace function public.dastak_v1_admin_catalogue_sku_delete(
  p_sku_id uuid, p_idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select dastak_v1_api.admin_catalogue_sku_delete(auth.uid(),p_sku_id,p_idempotency_key)
$$;
revoke all on function public.dastak_v1_admin_catalogue_sku_delete(uuid,text) from public,anon,authenticated;
grant execute on function public.dastak_v1_admin_catalogue_sku_delete(uuid,text) to authenticated;
