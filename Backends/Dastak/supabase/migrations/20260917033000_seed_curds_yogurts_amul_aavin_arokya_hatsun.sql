-- Owner-curated Curd & Yogurt range. Each pack is an exact SKU; the customer
-- presentation groups same-brand/variant pack sizes using the web family key.
do $$
declare
  v_actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b';
  v_batch uuid := gen_random_uuid();
  v_brand uuid;
  v_subcategory uuid;
  v_sku uuid;
  v_item record;
begin
  insert into dastak_v1.catalogue_import_batches (id, source_type, source_name, source_reference, status, counts, created_by, completed_at)
  values (v_batch, 'OWNER_CURATED', 'Amul, Aavin, Arokya & Hatsun curd and yogurt range',
    'dastak://catalogue/dairy-bread-eggs/curd-yogurt-brands-2026-09-17', 'COMPLETED',
    jsonb_build_object('brands', 4, 'skus', 8), v_actor, now());

  for v_item in select * from (values
    ('Amul','amul','curd','Amul Masti Dahi','400 g','55.00','canonical/staging/curd-yogurt-brands/amul-masti-400.webp','image/webp'),
    ('Amul','amul','set-curd','Amul Masti Dahi Family Pack','1 kg','105.00','canonical/staging/curd-yogurt-brands/amul-masti-1kg.webp','image/webp'),
    ('Aavin','aavin','curd','Aavin Curd Pouch','500 g','30.00','canonical/staging/curd-yogurt-brands/aavin-curd-500.png','image/png'),
    ('Aavin','aavin','set-curd','Aavin Thick Curd','1 kg','58.00','canonical/staging/curd-yogurt-brands/aavin-curd-1kg.png','image/png'),
    ('Arokya','arokya','curd','Arokya Fresh Curd','500 g','38.00','canonical/staging/curd-yogurt-brands/arokya-curd-500.webp','image/webp'),
    ('Arokya','arokya','set-curd','Arokya Fresh Curd Family Pack','1 kg','72.00','canonical/staging/curd-yogurt-brands/arokya-curd-1kg.webp','image/webp'),
    ('Hatsun','hatsun','curd','Hatsun Curd','400 g','50.00','canonical/staging/curd-yogurt-brands/hatsun-curd-400.png','image/png'),
    ('Hatsun','hatsun','set-curd','Hatsun Curd Family Pack','1 kg','110.00','canonical/staging/curd-yogurt-brands/hatsun-curd-1kg.png','image/png')
  ) as x(brand_name,brand_slug,subcategory_slug,sku_name,pack_size,price,image_key,mime_type)
  loop
    insert into dastak_v1.brands (name, slug, status, created_by)
      values (v_item.brand_name, v_item.brand_slug, 'ACTIVE', v_actor)
      on conflict (slug) do update set name=excluded.name, status='ACTIVE', updated_at=now(), version=dastak_v1.brands.version+1;
    select id into v_brand from dastak_v1.brands where slug=v_item.brand_slug;
    select sc.id into v_subcategory from dastak_v1.subcategories sc
      join dastak_v1.categories c on c.id=sc.category_id
      join dastak_v1.category_types ct on ct.id=c.category_type_id
      where ct.slug='dairy-bread-eggs' and sc.slug=v_item.subcategory_slug;
    if v_subcategory is null then raise exception 'missing curd/yogurt subcategory %', v_item.subcategory_slug; end if;

    insert into dastak_v1.skus (
      subcategory_id, brand_id, canonical_name, slug, pack_size, description, image_key,
      list_price_paise, selling_price_paise, currency_code, tax_rate_bps, logistics_attributes,
      status, created_by, product_kind, quantity_value, quantity_unit, country_of_origin_code, diet_type, qa_status
    ) values (
      v_subcategory, v_brand, v_item.sku_name,
      'dairy-' || v_item.brand_slug || '-' || regexp_replace(lower(v_item.sku_name), '[^a-z0-9]+', '-', 'g'),
      v_item.pack_size, 'Branded ' || v_item.sku_name || ' for Dastak delivery.', v_item.image_key,
      round((v_item.price::numeric)*100)::bigint, round((v_item.price::numeric)*100)::bigint, 'INR', 0,
      jsonb_build_object('weightGrams', case when v_item.pack_size='1 kg' then 1000 else 400 end, 'temperatureClass','CHILLED'),
      'DRAFT', v_actor, 'PACKAGED', case when v_item.pack_size='1 kg' then 1 else regexp_replace(v_item.pack_size, '[^0-9]', '', 'g')::numeric end, case when v_item.pack_size='1 kg' then 'kg' else 'g' end,
      'IN', 'VEG', 'PENDING'
    ) on conflict (slug) do update set brand_id=excluded.brand_id, subcategory_id=excluded.subcategory_id,
      image_key=excluded.image_key, pack_size=excluded.pack_size, list_price_paise=excluded.list_price_paise,
      selling_price_paise=excluded.selling_price_paise, status='ACTIVE', qa_status='VERIFIED', updated_at=now(), version=dastak_v1.skus.version+1
      returning id into v_sku;

    insert into dastak_v1.sku_images (
      sku_id, image_key, role, sort_order, source_type, source_reference, mime_type,
      status, created_by, verified_by, verified_at, rights_status, rights_reference,
      rights_verified_by, rights_verified_at
    ) values (
      v_sku, v_item.image_key, 'PRIMARY', 0, 'OWNER_CAPTURE',
      'owner-curated branded Curd & Yogurt artwork sourced from retailer/manufacturer product listing', v_item.mime_type,
      'VERIFIED', v_actor, v_actor, now(), 'CLEARED', 'owner-authorised catalogue artwork', v_actor, now()
    ) on conflict (sku_id) where role='PRIMARY' do update set image_key=excluded.image_key,
      mime_type=excluded.mime_type, status='VERIFIED', verified_by=v_actor, verified_at=now(), rights_status='CLEARED',
      rights_verified_by=v_actor, rights_verified_at=now(), version=dastak_v1.sku_images.version+1;

    update dastak_v1.skus set status='ACTIVE', qa_status='VERIFIED', qa_verified_by=v_actor,
      qa_verified_at=now(), updated_at=now(), version=version+1 where id=v_sku;

    insert into dastak_v1.catalogue_import_items (batch_id, source_key, raw_payload, normalized_payload, status, canonical_sku_id)
    values (v_batch, 'curd-yogurt-brands/' || v_item.brand_slug || '/' || v_sku::text,
      jsonb_build_object('brand',v_item.brand_name,'name',v_item.sku_name,'packSize',v_item.pack_size,'imageKey',v_item.image_key),
      jsonb_build_object('brand',v_item.brand_name,'name',v_item.sku_name,'packSize',v_item.pack_size,'imageKey',v_item.image_key,'normalizationMethod','OWNER_CURATED_CURD_YOGURT_V1'),
      'IMPORTED', v_sku)
    on conflict (batch_id, source_key) do update set canonical_sku_id=excluded.canonical_sku_id, status='IMPORTED', updated_at=now(), version=dastak_v1.catalogue_import_items.version+1;
  end loop;
end;
$$;
