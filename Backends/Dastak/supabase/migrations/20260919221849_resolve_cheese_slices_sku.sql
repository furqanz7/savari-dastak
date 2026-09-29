-- Resolve the exact SKU requested by the operator without bypassing V1's
-- historical-integrity guard.  A referenced SKU is archived and removed from
-- merchant selections; an unreferenced SKU is permanently deleted.
do $$
declare
  v_sku_id constant uuid := '42685289-b287-4c86-ba66-d375f7ef7ca6';
  v_name text;
  v_refs bigint;
begin
  select canonical_name
    into v_name
    from dastak_v1.skus
   where id = v_sku_id
   for update;

  if v_name is null then
    raise notice 'SKU % is already absent; no action required', v_sku_id;
    return;
  end if;

  select count(*)
    into v_refs
    from (
      select 1 from dastak_v1.order_lines where sku_id = v_sku_id
      union all select 1 from dastak_v1.merchant_stock_reservations where sku_id = v_sku_id
      union all select 1 from dastak_v1.merchant_sku_selections where sku_id = v_sku_id
      union all select 1 from dastak_v1.merchant_opportunity_lines where sku_id = v_sku_id
      union all select 1 from dastak_v1.recovery_opportunities where sku_id = v_sku_id
    ) refs;

  if v_refs = 0 then
    delete from dastak_v1.skus where id = v_sku_id;
    insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
    values (
      '7105206a-6fec-45c9-8c00-3dfd5178fc1b',
      'CATALOGUE_SKU_DELETED',
      'catalogue_sku',
      v_sku_id,
      jsonb_build_object('name', v_name, 'reason', 'operator requested exact SKU removal')
    );
    raise notice 'Permanently deleted SKU % (%)', v_name, v_sku_id;
  else
    update dastak_v1.skus
       set status = 'INACTIVE', updated_at = now(), version = version + 1
     where id = v_sku_id;
    delete from dastak_v1.merchant_sku_selections where sku_id = v_sku_id;
    insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
    values (
      '7105206a-6fec-45c9-8c00-3dfd5178fc1b',
      'CATALOGUE_SKU_ARCHIVED',
      'catalogue_sku',
      v_sku_id,
      jsonb_build_object('name', v_name, 'references', v_refs, 'reason', 'operator requested exact SKU removal')
    );
    raise notice 'Archived referenced SKU % (%) with % references', v_name, v_sku_id, v_refs;
  end if;
end
$$;
