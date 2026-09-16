-- Owner-curated Butter & Margarine range for Amul and Milky Mist.
do $$
declare
  v_actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b'; v_batch uuid := gen_random_uuid();
  v_brand uuid; v_subcategory uuid; v_sku uuid; v_item record;
begin
  insert into dastak_v1.catalogue_import_batches (id, source_type, source_name, source_reference, status, counts, created_by, completed_at)
  values (v_batch,'OWNER_CURATED','Amul & Milky Mist butter range','dastak://catalogue/dairy-bread-eggs/butter-margarine-brands-2026-09-17','COMPLETED',jsonb_build_object('brands',2,'skus',12),v_actor,now());
  for v_item in select * from (values
    ('Amul','amul','salted-butter','Amul Pasteurised Butter','dairy-amul-amul-pasteurised-butter','100 g','58.00','canonical/staging/butter-margarine-brands/amul-pasteurised-butter-100.jpg','image/png'),
    ('Amul','amul','unsalted-butter','Amul Safed Makkhan','amul-safed-makkhan-100-g-fe66bde6','100 g','60.00','canonical/staging/butter-margarine-brands/amul-safed-makkhan-100.jpg','image/png'),
    ('Amul','amul','unsalted-butter','Amul Safed Makkhan','amul-safed-makkhan-200-g-afdd4039','200 g','120.00','canonical/staging/butter-margarine-brands/amul-safed-makkhan-200.jpg','image/png'),
    ('Amul','amul','unsalted-butter','Amul Safed Makkhan','amul-safed-makkhan-500-g-2f5eee78','500 g','285.00','canonical/staging/butter-margarine-brands/amul-safed-makkhan-500.jpg','image/png'),
    ('Milky Mist','milky-mist','unsalted-butter','Milky Mist Cooking Butter','milky-mist-cooking-butter-100','100 g','62.00','canonical/staging/butter-margarine-brands/milkymist-cooking-butter-100.jpg','image/jpeg'),
    ('Milky Mist','milky-mist','unsalted-butter','Milky Mist Cooking Butter','milky-mist-cooking-butter-200','200 g','120.00','canonical/staging/butter-margarine-brands/milkymist-cooking-butter-200.jpg','image/jpeg'),
    ('Milky Mist','milky-mist','unsalted-butter','Milky Mist Cooking Butter','milky-mist-cooking-butter-500','500 g','285.00','canonical/staging/butter-margarine-brands/milkymist-cooking-butter-500.jpg','image/jpeg'),
    ('Milky Mist','milky-mist','salted-butter','Milky Mist Table Butter','milky-mist-table-butter-100','100 g','65.00','canonical/staging/butter-margarine-brands/milkymist-table-butter-100.jpg','image/jpeg'),
    ('Milky Mist','milky-mist','salted-butter','Milky Mist Table Butter','milky-mist-table-butter-200','200 g','125.00','canonical/staging/butter-margarine-brands/milkymist-table-butter-200.jpg','image/jpeg'),
    ('Milky Mist','milky-mist','salted-butter','Milky Mist Table Butter','milky-mist-table-butter-500','500 g','295.00','canonical/staging/butter-margarine-brands/milkymist-table-butter-500.jpg','image/jpeg'),
    ('Milky Mist','milky-mist','salted-butter','Milky Mist Butter Chiplet','milky-mist-butter-chiplet-100','100 g','70.00','canonical/staging/butter-margarine-brands/milkymist-butter-chiplet-100.jpg','image/jpeg'),
    ('Milky Mist','milky-mist','salted-butter','Milky Mist Butter Chiplet','milky-mist-butter-chiplet-1kg','1 kg','560.00','canonical/staging/butter-margarine-brands/milkymist-butter-chiplet-1kg.jpg','image/jpeg')
  ) as x(brand_name,brand_slug,subcategory_slug,sku_name,sku_slug,pack_size,price,image_key,mime_type)
  loop
    insert into dastak_v1.brands(name,slug,status,created_by) values(v_item.brand_name,v_item.brand_slug,'ACTIVE',v_actor)
      on conflict(slug) do update set name=excluded.name,status='ACTIVE',updated_at=now(),version=dastak_v1.brands.version+1;
    select id into v_brand from dastak_v1.brands where slug=v_item.brand_slug;
    select sc.id into v_subcategory from dastak_v1.subcategories sc join dastak_v1.categories c on c.id=sc.category_id join dastak_v1.category_types ct on ct.id=c.category_type_id where ct.slug='dairy-bread-eggs' and sc.slug=v_item.subcategory_slug;
    if v_subcategory is null then raise exception 'missing butter subcategory %',v_item.subcategory_slug; end if;
    insert into dastak_v1.skus(subcategory_id,brand_id,canonical_name,slug,pack_size,description,image_key,list_price_paise,selling_price_paise,currency_code,tax_rate_bps,logistics_attributes,status,created_by,product_kind,quantity_value,quantity_unit,country_of_origin_code,diet_type,qa_status)
    values(v_subcategory,v_brand,v_item.sku_name,v_item.sku_slug,v_item.pack_size,'Branded '||v_item.sku_name||' for Dastak delivery.',v_item.image_key,round((v_item.price::numeric)*100)::bigint,round((v_item.price::numeric)*100)::bigint,'INR',0,jsonb_build_object('temperatureClass','CHILLED'),'DRAFT',v_actor,'PACKAGED',regexp_replace(v_item.pack_size,'[^0-9.]','','g')::numeric,case when v_item.pack_size like '%kg' then 'kg' else 'g' end,'IN','VEG','PENDING')
    on conflict(slug) do update set brand_id=excluded.brand_id,subcategory_id=excluded.subcategory_id,canonical_name=excluded.canonical_name,image_key=excluded.image_key,pack_size=excluded.pack_size,list_price_paise=excluded.list_price_paise,selling_price_paise=excluded.selling_price_paise,updated_at=now(),version=dastak_v1.skus.version+1 returning id into v_sku;
    insert into dastak_v1.sku_images(sku_id,image_key,role,sort_order,source_type,source_reference,mime_type,status,created_by,verified_by,verified_at,rights_status,rights_reference,rights_verified_by,rights_verified_at)
    values(v_sku,v_item.image_key,'PRIMARY',0,'OWNER_CAPTURE','owner-curated branded Butter & Margarine artwork sourced from retailer/manufacturer product listing',v_item.mime_type,'VERIFIED',v_actor,v_actor,now(),'CLEARED','owner-authorised catalogue artwork',v_actor,now())
    on conflict(sku_id) where role='PRIMARY' do update set image_key=excluded.image_key,mime_type=excluded.mime_type,status='VERIFIED',verified_by=v_actor,verified_at=now(),rights_status='CLEARED',rights_verified_by=v_actor,rights_verified_at=now(),version=dastak_v1.sku_images.version+1;
    update dastak_v1.skus set status='ACTIVE',qa_status='VERIFIED',qa_verified_by=v_actor,qa_verified_at=now(),updated_at=now(),version=version+1 where id=v_sku;
    insert into dastak_v1.catalogue_import_items(batch_id,source_key,raw_payload,normalized_payload,status,canonical_sku_id) values(v_batch,'butter-margarine-brands/'||v_item.brand_slug||'/'||v_item.sku_slug,jsonb_build_object('brand',v_item.brand_name,'name',v_item.sku_name,'packSize',v_item.pack_size,'imageKey',v_item.image_key),jsonb_build_object('brand',v_item.brand_name,'name',v_item.sku_name,'packSize',v_item.pack_size,'imageKey',v_item.image_key,'normalizationMethod','OWNER_CURATED_BUTTER_MARGARINE_V1'),'IMPORTED',v_sku) on conflict(batch_id,source_key) do update set canonical_sku_id=excluded.canonical_sku_id,status='IMPORTED',updated_at=now(),version=dastak_v1.catalogue_import_items.version+1;
  end loop;
end;
$$;
