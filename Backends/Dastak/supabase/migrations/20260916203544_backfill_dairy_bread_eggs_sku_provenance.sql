-- Backfill the source-provenance records required by catalogue readiness.
-- The Dairy, Bread & Eggs seed migration created verified images and active
-- SKUs, but omitted the catalogue_import_items link used by the admin gate.
do $$
declare
  v_actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b';
  v_batch uuid;
  v_sku record;
begin
  select id into v_batch
  from dastak_v1.catalogue_import_batches
  where source_reference='dastak://catalogue/dairy-bread-eggs/starter-2026-09-16'
  order by created_at desc
  limit 1;

  if v_batch is null then
    v_batch := gen_random_uuid();
    insert into dastak_v1.catalogue_import_batches (
      id, source_type, source_name, source_reference, status, counts,
      created_by, completed_at
    ) values (
      v_batch, 'OWNER_CURATED', 'Dairy, Bread & Eggs starter SKU catalogue',
      'dastak://catalogue/dairy-bread-eggs/starter-2026-09-16', 'COMPLETED',
      jsonb_build_object('categoryType', 'dairy-bread-eggs'), v_actor, now()
    );
  end if;

  for v_sku in
    select s.id, s.slug, s.canonical_name, s.pack_size, s.selling_price_paise,
           s.image_key, sc.slug as subcategory_slug
    from dastak_v1.skus s
    join dastak_v1.subcategories sc on sc.id=s.subcategory_id
    join dastak_v1.categories c on c.id=sc.category_id
    join dastak_v1.category_types ct on ct.id=c.category_type_id
    where ct.slug='dairy-bread-eggs'
      and not exists (
        select 1 from dastak_v1.catalogue_import_items i
        where i.canonical_sku_id=s.id
      )
    order by s.slug
  loop
    insert into dastak_v1.catalogue_import_items (
      batch_id, source_key, raw_payload, normalized_payload, status,
      canonical_sku_id
    ) values (
      v_batch,
      'dairy-bread-eggs/' || v_sku.slug,
      jsonb_build_object(
        'subcategorySlug', v_sku.subcategory_slug,
        'name', v_sku.canonical_name,
        'packSize', v_sku.pack_size,
        'pricePaise', v_sku.selling_price_paise,
        'imageKey', v_sku.image_key
      ),
      jsonb_build_object(
        'subcategorySlug', v_sku.subcategory_slug,
        'name', v_sku.canonical_name,
        'packSize', v_sku.pack_size,
        'pricePaise', v_sku.selling_price_paise,
        'imageKey', v_sku.image_key,
        'normalizationMethod', 'OWNER_CURATED_DAIRY_BREAD_EGGS_V1'
      ),
      'IMPORTED', v_sku.id
    )
    on conflict (batch_id, source_key) do update set
      raw_payload=excluded.raw_payload,
      normalized_payload=excluded.normalized_payload,
      status='IMPORTED',
      canonical_sku_id=excluded.canonical_sku_id,
      updated_at=now(),
      version=dastak_v1.catalogue_import_items.version+1;
  end loop;
end;
$$;
