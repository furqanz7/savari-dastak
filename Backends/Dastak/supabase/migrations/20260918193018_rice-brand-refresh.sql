-- Owner-curated Rice refresh: live Daawat, India Gate and Kohinoor basmati range.
-- Existing Aachi and Tata catalogue records are intentionally left unchanged.
do $$
declare
  v_actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b';
  v_batch uuid := gen_random_uuid();
  v_brand uuid; v_subcategory uuid; v_sku uuid; v_item record;
begin
  insert into dastak_v1.catalogue_import_batches
    (id,source_type,source_name,source_reference,status,counts,created_by,completed_at)
  values
    (v_batch,'OWNER_CURATED','Daawat, India Gate and Kohinoor basmati rice range',
     'dastak://catalogue/staples-pantry/basmati-rice-brands-2026-09-19','COMPLETED',
     jsonb_build_object('brands',3,'skus',6),v_actor,now());

  -- Keep the requested brands live and remove unrelated active basmati listings
  -- from the customer catalogue without deleting their historical records.
  update dastak_v1.skus s set status='DRAFT', updated_at=now(), version=s.version+1
  where s.subcategory_id in (select sc.id from dastak_v1.subcategories sc where sc.slug='basmati-rice')
    and s.brand_id in (select b.id from dastak_v1.brands b)
    and exists (select 1 from dastak_v1.brands b where b.id=s.brand_id
      and b.name not in ('Aachi','Tata','Tata Salt','Tata Sampann','Daawat','India Gate','Kohinoor'))
    and s.status='ACTIVE';

  for v_item in select * from (values
    ('Daawat','daawat','Daawat Traditional Basmati Rice','1 kg','239.00','canonical/rice/daawat-traditional-basmati-1kg.jpg','image/jpeg'),
    ('Daawat','daawat','Daawat Traditional Basmati Rice','5 kg','999.00','canonical/rice/daawat-traditional-basmati-5kg.jpg','image/jpeg'),
    ('India Gate','india-gate','India Gate Classic Basmati Rice','1 kg','225.00','canonical/rice/india-gate-classic-basmati-1kg.jpg','image/jpeg'),
    ('India Gate','india-gate','India Gate Classic Basmati Rice','5 kg','999.00','canonical/rice/india-gate-classic-basmati-5kg.jpg','image/jpeg'),
    ('Kohinoor','kohinoor','Kohinoor Traditional Authentic Basmati Rice','1 kg','220.00','canonical/rice/kohinoor-traditional-basmati-1kg.png','image/png'),
    ('Kohinoor','kohinoor','Kohinoor Traditional Authentic Basmati Rice','5 kg','950.00','canonical/rice/kohinoor-traditional-basmati-5kg.png','image/png')
  ) as x(brand_name,brand_slug,sku_name,pack_size,price,image_key,mime_type)
  loop
    insert into dastak_v1.brands(name,slug,status,created_by)
    values(v_item.brand_name,v_item.brand_slug,'ACTIVE',v_actor)
    on conflict(slug) do update set name=excluded.name,status='ACTIVE',updated_at=now(),version=dastak_v1.brands.version+1;
    select id into v_brand from dastak_v1.brands where slug=v_item.brand_slug;
    select sc.id into v_subcategory
    from dastak_v1.subcategories sc
    join dastak_v1.categories c on c.id=sc.category_id
    join dastak_v1.category_types ct on ct.id=c.category_type_id
    where ct.slug='staples-pantry' and sc.slug='basmati-rice';
    if v_subcategory is null then raise exception 'missing Staples & Pantry Basmati Rice subcategory'; end if;

    insert into dastak_v1.skus
      (subcategory_id,brand_id,canonical_name,slug,pack_size,description,image_key,
       list_price_paise,selling_price_paise,currency_code,tax_rate_bps,logistics_attributes,
       status,created_by,product_kind,quantity_value,quantity_unit,country_of_origin_code,diet_type,qa_status)
    values
      (v_subcategory,v_brand,v_item.sku_name,
       regexp_replace(lower(v_item.brand_slug||'-'||v_item.sku_name||'-'||v_item.pack_size),'[^a-z0-9]+','-','g'),
       v_item.pack_size,'Branded basmati rice for Dastak delivery.',v_item.image_key,
       round((v_item.price::numeric*1.08)*100)::bigint,round(v_item.price::numeric*100)::bigint,
       'INR',0,jsonb_build_object('temperatureClass','AMBIENT'),'DRAFT',v_actor,'PACKAGED',
       regexp_replace(v_item.pack_size,'[^0-9.]','','g')::numeric,'kg','IN','VEG','PENDING')
    on conflict(slug) do update set
      brand_id=excluded.brand_id,subcategory_id=excluded.subcategory_id,canonical_name=excluded.canonical_name,
      pack_size=excluded.pack_size,description=excluded.description,image_key=excluded.image_key,
      list_price_paise=excluded.list_price_paise,selling_price_paise=excluded.selling_price_paise,
      updated_at=now(),version=dastak_v1.skus.version+1
    returning id into v_sku;

    insert into dastak_v1.sku_images
      (sku_id,image_key,role,sort_order,source_type,source_reference,mime_type,status,created_by,
       verified_by,verified_at,rights_status,rights_reference,rights_verified_by,rights_verified_at)
    values
      (v_sku,v_item.image_key,'PRIMARY',0,'OWNER_CAPTURE',
       'Owner-curated branded rice artwork sourced from a product listing',v_item.mime_type,'VERIFIED',
       v_actor,v_actor,now(),'CLEARED','owner-authorised catalogue artwork',v_actor,now())
    on conflict(sku_id) where role='PRIMARY' do update set
      image_key=excluded.image_key,mime_type=excluded.mime_type,status='VERIFIED',verified_by=v_actor,
      verified_at=now(),rights_status='CLEARED',rights_verified_by=v_actor,rights_verified_at=now(),
      version=dastak_v1.sku_images.version+1;

    update dastak_v1.skus set status='ACTIVE',qa_status='VERIFIED',qa_verified_by=v_actor,
      qa_verified_at=now(),updated_at=now(),version=version+1 where id=v_sku;

    insert into dastak_v1.catalogue_import_items
      (batch_id,source_key,raw_payload,normalized_payload,status,canonical_sku_id)
    values
      (v_batch,'rice-brands/'||v_item.brand_slug||'/'||v_item.pack_size,
       jsonb_build_object('brand',v_item.brand_name,'name',v_item.sku_name,'packSize',v_item.pack_size),
       jsonb_build_object('brand',v_item.brand_name,'name',v_item.sku_name,'packSize',v_item.pack_size,
         'imageKey',v_item.image_key,'normalizationMethod','OWNER_CURATED_RICE_BRANDS_V1'),
       'IMPORTED',v_sku)
    on conflict(batch_id,source_key) do update set canonical_sku_id=excluded.canonical_sku_id,
      status='IMPORTED',updated_at=now(),version=dastak_v1.catalogue_import_items.version+1;
  end loop;
end;
$$;
