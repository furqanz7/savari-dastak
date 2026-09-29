-- Remove only the two operator-identified Pani Puri Kit SKUs. This is
-- idempotent so a direct catalogue correction can later enter migration
-- history without deleting any replacement products.
begin;

do $$
declare
  v_found integer;
  v_references bigint;
  v_deleted integer;
begin
  perform s.id
    from dastak_v1.skus s
   where s.id in (
     '5e968e4d-2812-4d3a-a10e-ec17d6a87905',
     'bc70f474-87e2-4618-9a9b-96b84799e660'
   )
   for update;

  select count(*) into v_found
    from dastak_v1.skus s
   where s.id in (
     '5e968e4d-2812-4d3a-a10e-ec17d6a87905',
     'bc70f474-87e2-4618-9a9b-96b84799e660'
   )
     and ((s.id = '5e968e4d-2812-4d3a-a10e-ec17d6a87905'
       and s.slug = 'aachi-pani-puri-kit-133-g-5e968e4d'
       and s.canonical_name = 'Aachi Pani Puri Kit 133 g')
       or (s.id = 'bc70f474-87e2-4618-9a9b-96b84799e660'
       and s.slug = 'aachi-pani-puri-kit-266-g-bc70f474'
       and s.canonical_name = 'Aachi Pani Puri Kit 266 g'));

  if v_found = 0 then
    if exists (
      select 1 from dastak_v1.skus
       where id in (
         '5e968e4d-2812-4d3a-a10e-ec17d6a87905',
         'bc70f474-87e2-4618-9a9b-96b84799e660'
       )
    ) then
      raise exception 'Pani Puri Kit SKU identity changed; refusing deletion';
    end if;
    return;
  end if;

  if v_found <> 2 then
    raise exception 'Expected exactly two Pani Puri Kit SKUs, found %', v_found;
  end if;

  select sum(refs.n) into v_references
    from (
      select count(*) as n from dastak_v1.order_lines
       where sku_id in ('5e968e4d-2812-4d3a-a10e-ec17d6a87905','bc70f474-87e2-4618-9a9b-96b84799e660')
      union all select count(*) from dastak_v1.merchant_stock_reservations
       where sku_id in ('5e968e4d-2812-4d3a-a10e-ec17d6a87905','bc70f474-87e2-4618-9a9b-96b84799e660')
      union all select count(*) from dastak_v1.merchant_sku_selections
       where sku_id in ('5e968e4d-2812-4d3a-a10e-ec17d6a87905','bc70f474-87e2-4618-9a9b-96b84799e660')
      union all select count(*) from dastak_v1.merchant_opportunity_lines
       where sku_id in ('5e968e4d-2812-4d3a-a10e-ec17d6a87905','bc70f474-87e2-4618-9a9b-96b84799e660')
      union all select count(*) from dastak_v1.recovery_opportunities
       where sku_id in ('5e968e4d-2812-4d3a-a10e-ec17d6a87905','bc70f474-87e2-4618-9a9b-96b84799e660')
    ) refs;

  if v_references <> 0 then
    raise exception 'Pani Puri Kit SKUs gained % transactional reference(s); refusing deletion', v_references;
  end if;

  insert into dastak_v1.audit_events
    (actor_id, action, resource_type, resource_id, metadata)
  select null, 'CATALOGUE_SKU_DELETED', 'catalogue_sku', s.id,
         jsonb_build_object(
           'name', s.canonical_name,
           'slug', s.slug,
           'reason', 'operator requested removal of two Pani Puri Kit SKUs'
         )
    from dastak_v1.skus s
   where s.id in (
     '5e968e4d-2812-4d3a-a10e-ec17d6a87905',
     'bc70f474-87e2-4618-9a9b-96b84799e660'
   );

  delete from dastak_v1.skus s
   where s.id in (
     '5e968e4d-2812-4d3a-a10e-ec17d6a87905',
     'bc70f474-87e2-4618-9a9b-96b84799e660'
   );
  get diagnostics v_deleted = row_count;
  if v_deleted <> 2 then
    raise exception 'Expected to delete exactly two Pani Puri Kit SKUs, deleted %', v_deleted;
  end if;
end
$$;

commit;
