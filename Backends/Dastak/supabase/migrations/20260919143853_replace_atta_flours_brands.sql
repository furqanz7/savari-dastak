-- Owner-curated Atta & Flours replacement: Aashirvaad, Pillsbury, Fortune and Aachi.
-- Existing non-requested live SKUs are retired from the customer catalogue (not deleted),
-- preserving historical order references while making the requested brand range live.
do $$
declare
  v_actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b';
  v_batch uuid := gen_random_uuid();
  v_brand uuid;
  v_subcategory uuid;
  v_sku uuid;
  v_item record;
begin
  insert into dastak_v1.catalogue_import_batches
    (id, source_type, source_name, source_reference, status, counts, created_by, completed_at)
  values
    (v_batch, 'OWNER_CURATED', 'Aashirvaad, Pillsbury, Fortune and Aachi Atta & Flours',
     'dastak://catalogue/staples-pantry/atta-flours-brands-2026-09-19', 'COMPLETED',
     jsonb_build_object('brands', 4, 'skus', 20), v_actor, now());

  -- A clean replay can still have these catalogue parents in DRAFT. The SKU
  -- activation guard requires the whole taxonomy path to be ACTIVE first.
  update dastak_v1.categories c
     set status = 'ACTIVE', updated_at = now(), version = c.version + 1
    from dastak_v1.category_types ct
   where c.category_type_id = ct.id
     and ct.slug = 'staples-pantry'
     and c.slug = 'atta-flours'
     and c.status <> 'ACTIVE';

  update dastak_v1.subcategories sc
     set status = 'ACTIVE', updated_at = now(), version = sc.version + 1
    from dastak_v1.categories c
    join dastak_v1.category_types ct on ct.id = c.category_type_id
   where sc.category_id = c.id
     and ct.slug = 'staples-pantry'
     and c.slug = 'atta-flours'
     and sc.slug in ('whole-wheat-atta','maida','sooji-rava','besan','multigrain-atta')
     and sc.status <> 'ACTIVE';

  -- Retire unrelated live Atta & Flours records without hard-deleting SKU identities.
  update dastak_v1.skus s
     set status = 'DRAFT', updated_at = now(), version = s.version + 1
   where s.status = 'ACTIVE'
     and s.subcategory_id in (
       select sc.id
         from dastak_v1.subcategories sc
         join dastak_v1.categories c on c.id = sc.category_id
         join dastak_v1.category_types ct on ct.id = c.category_type_id
        where ct.slug = 'staples-pantry' and sc.slug in (
          'whole-wheat-atta','maida','sooji-rava','besan','multigrain-atta'
        )
     )
     and not exists (
       select 1 from dastak_v1.brands b
        where b.id = s.brand_id
          and b.slug in ('aashirvaad','pillsbury','fortune','aachi')
     );

  for v_item in
    select * from (values
      ('Aashirvaad','aashirvaad','whole-wheat-atta','Aashirvaad Shudh Chakki Atta','1 kg','58.00','aashirvaad-shudh-chakki-atta-1kg','jpg'),
      ('Aashirvaad','aashirvaad','whole-wheat-atta','Aashirvaad Shudh Chakki Atta','5 kg','285.00','aashirvaad-shudh-chakki-atta-5kg','jpg'),
      ('Aashirvaad','aashirvaad','maida','Aashirvaad Maida','1 kg','62.00','aashirvaad-maida-1kg','jpg'),
      ('Aashirvaad','aashirvaad','sooji-rava','Aashirvaad Sooji Rava','500 g','38.00','aashirvaad-sooji-rava-500g','jpg'),
      ('Aashirvaad','aashirvaad','multigrain-atta','Aashirvaad Multigrain Atta','1 kg','92.00','aashirvaad-multigrain-atta-1kg','jpg'),
      ('Pillsbury','pillsbury','whole-wheat-atta','Pillsbury Chakki Fresh Atta','1 kg','62.00','pillsbury-chakki-fresh-atta-1kg','jpg'),
      ('Pillsbury','pillsbury','whole-wheat-atta','Pillsbury Chakki Fresh Atta','5 kg','299.00','pillsbury-chakki-fresh-atta-5kg','jpg'),
      ('Pillsbury','pillsbury','maida','Pillsbury Maida','1 kg','58.00','pillsbury-maida-1kg','jpg'),
      ('Pillsbury','pillsbury','sooji-rava','Pillsbury Sooji Rava','500 g','36.00','pillsbury-sooji-rava-500g','jpg'),
      ('Pillsbury','pillsbury','multigrain-atta','Pillsbury Multigrain Atta','1 kg','95.00','pillsbury-multigrain-atta-1kg','jpg'),
      ('Fortune','fortune','whole-wheat-atta','Fortune Chakki Fresh Atta','1 kg','56.00','fortune-chakki-fresh-atta-1kg','jpg'),
      ('Fortune','fortune','whole-wheat-atta','Fortune Chakki Fresh Atta','5 kg','275.00','fortune-chakki-fresh-atta-5kg','jpg'),
      ('Fortune','fortune','maida','Fortune Maida','1 kg','54.00','fortune-maida-1kg','jpg'),
      ('Fortune','fortune','besan','Fortune Besan','500 g','48.00','fortune-besan-500g','jpg'),
      ('Fortune','fortune','multigrain-atta','Fortune Multigrain Atta','1 kg','88.00','fortune-multigrain-atta-1kg','jpg'),
      ('Aachi','aachi','whole-wheat-atta','Aachi Chakki Atta','1 kg','64.00','aachi-chakki-atta-1kg','jpg'),
      ('Aachi','aachi','maida','Aachi Maida','500 g','35.00','aachi-maida-500g','jpg'),
      ('Aachi','aachi','sooji-rava','Aachi Sooji Rava','500 g','34.00','aachi-sooji-rava-500g','jpg'),
      ('Aachi','aachi','besan','Aachi Besan','500 g','52.00','aachi-besan-500g','jpg'),
      ('Aachi','aachi','multigrain-atta','Aachi Multigrain Atta','1 kg','96.00','aachi-multigrain-atta-1kg','jpg')
    ) as x(brand_name, brand_slug, subcategory_slug, sku_name, pack_size, price, item_slug, extension)
  loop
    insert into dastak_v1.brands(name, slug, status, created_by)
    values(v_item.brand_name, v_item.brand_slug, 'ACTIVE', v_actor)
    on conflict(slug) do update set name=excluded.name, status='ACTIVE', updated_at=now(), version=dastak_v1.brands.version+1;
    select id into v_brand from dastak_v1.brands where slug=v_item.brand_slug;

    select sc.id into v_subcategory
      from dastak_v1.subcategories sc
      join dastak_v1.categories c on c.id=sc.category_id
      join dastak_v1.category_types ct on ct.id=c.category_type_id
     where ct.slug='staples-pantry' and sc.slug=v_item.subcategory_slug;
    if v_subcategory is null then raise exception 'missing Atta & Flours subcategory %', v_item.subcategory_slug; end if;

    insert into dastak_v1.skus
      (subcategory_id, brand_id, canonical_name, slug, pack_size, description, image_key,
       list_price_paise, selling_price_paise, currency_code, tax_rate_bps, logistics_attributes,
       status, created_by, product_kind, quantity_value, quantity_unit, country_of_origin_code,
       diet_type, qa_status)
    values
      (v_subcategory, v_brand, v_item.sku_name, 'atta-flours-'||v_item.item_slug, v_item.pack_size,
       'Branded '||v_item.sku_name||' for Dastak delivery.',
       'canonical/staging/atta-flours/'||v_item.item_slug||'.'||v_item.extension,
       round((v_item.price::numeric)*100)::bigint, round((v_item.price::numeric)*100)::bigint,
       'INR', 0, jsonb_build_object('temperatureClass','AMBIENT'), 'DRAFT', v_actor, 'PACKAGED',
       regexp_replace(v_item.pack_size,'[^0-9.]','','g')::numeric,
       case when v_item.pack_size like '%kg' then 'kg' else 'g' end, 'IN', 'VEG', 'PENDING')
    on conflict(slug) do update set
      subcategory_id=excluded.subcategory_id, brand_id=excluded.brand_id,
      canonical_name=excluded.canonical_name, pack_size=excluded.pack_size,
      description=excluded.description, image_key=excluded.image_key,
      list_price_paise=excluded.list_price_paise, selling_price_paise=excluded.selling_price_paise,
      updated_at=now(), version=dastak_v1.skus.version+1
    returning id into v_sku;

    insert into dastak_v1.sku_images
      (sku_id,image_key,role,sort_order,source_type,source_reference,mime_type,status,created_by,
       verified_by,verified_at,rights_status,rights_reference,rights_verified_by,rights_verified_at)
    values
      (v_sku,'canonical/staging/atta-flours/'||v_item.item_slug||'.'||v_item.extension,'PRIMARY',0,
       'OWNER_CAPTURE','owner-curated branded Atta & Flours artwork', 'image/jpeg','VERIFIED',v_actor,
       v_actor,now(),'CLEARED','owner-authorised catalogue artwork',v_actor,now())
    on conflict(sku_id) where role='PRIMARY' do update set
      image_key=excluded.image_key,status='VERIFIED',verified_by=v_actor,verified_at=now(),
      rights_status='CLEARED',rights_verified_by=v_actor,rights_verified_at=now(),
      version=dastak_v1.sku_images.version+1;

    update dastak_v1.skus set status='ACTIVE', qa_status='VERIFIED', qa_verified_by=v_actor,
      qa_verified_at=now(), updated_at=now(), version=version+1 where id=v_sku;

    insert into dastak_v1.catalogue_import_items
      (batch_id,source_key,raw_payload,normalized_payload,status,canonical_sku_id)
    values
      (v_batch,'atta-flours/'||v_item.item_slug,
       jsonb_build_object('brand',v_item.brand_name,'name',v_item.sku_name,'packSize',v_item.pack_size),
       jsonb_build_object('brand',v_item.brand_name,'name',v_item.sku_name,'packSize',v_item.pack_size,
         'imageKey','canonical/staging/atta-flours/'||v_item.item_slug||'.'||v_item.extension,
         'normalizationMethod','OWNER_CURATED_ATTA_FLOURS_BRANDS_V1'), 'IMPORTED',v_sku)
    on conflict(batch_id,source_key) do update set canonical_sku_id=excluded.canonical_sku_id,
      status='IMPORTED', updated_at=now(), version=dastak_v1.catalogue_import_items.version+1;
  end loop;
end;
$$;
