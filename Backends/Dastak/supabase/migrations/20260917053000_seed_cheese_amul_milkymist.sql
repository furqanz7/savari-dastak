-- Owner-curated branded Cheese range. Exact pack sizes remain separate purchasable SKUs.
do $$
declare
  a constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b'; b uuid; c uuid; s uuid; batch uuid := gen_random_uuid(); r record;
begin
  insert into dastak_v1.catalogue_import_batches(id,source_type,source_name,source_reference,status,counts,created_by,completed_at) values(batch,'OWNER_CURATED','Amul & Milky Mist cheese range','dastak://catalogue/dairy-bread-eggs/cheese-brands-2026-09-17','COMPLETED',jsonb_build_object('brands',2,'skus',24),a,now());
  for r in select * from (values
    ('Amul','amul','cream-cheese','Amul Cream Cheese','amul-cream-cheese-180-g-e0dc24c9','180 g','165','amul'),
    ('Amul','amul','cheese-blocks','Amul Processed Cheese Block','amul-processed-cheese-block-200-g-f9e336ee','200 g','125','amul'),
    ('Amul','amul','cheese-blocks','Amul Processed Cheese Block','amul-processed-cheese-block-500-g-fd249407','500 g','295','amul'),
    ('Amul','amul','cheese-blocks','Amul Processed Cheese Block','amul-processed-cheese-block-1-kg-02e45397','1 kg','560','amul'),
    ('Amul','amul','cheese-slices','Amul Processed Cheese Slices','amul-processed-cheese-slices-100-g-a8deb40e','100 g','85','amul'),
    ('Amul','amul','cheese-slices','Amul Processed Cheese Slices','amul-processed-cheese-slices-200-g-cfa51c3a','200 g','165','amul'),
    ('Amul','amul','cheese-slices','Amul Processed Cheese Slices','amul-processed-cheese-slices-400-g-8e69990f','400 g','320','amul'),
    ('Amul','amul','cheese-slices','Amul Processed Cheese Slices','amul-processed-cheese-slices-750-g-7a55f61a','750 g','575','amul'),
    ('Milky Mist','milky-mist','cheese-slices','Milky Mist Cheese Slices','milky-mist-cheese-slices-100','100 g','95','milkymist'),
    ('Milky Mist','milky-mist','cheese-slices','Milky Mist Cheese Slices','milky-mist-cheese-slices-200','200 g','185','milkymist'),
    ('Milky Mist','milky-mist','cheese-slices','Milky Mist Cheese Slices','milky-mist-cheese-slices-480','480 g','420','milkymist'),
    ('Milky Mist','milky-mist','cheese-slices','Milky Mist Cheese Slices','milky-mist-cheese-slices-765','765 g','650','milkymist'),
    ('Milky Mist','milky-mist','cheese-blocks','Milky Mist Cheese Block','milky-mist-cheese-block-200','200 g','185','milkymist'),
    ('Milky Mist','milky-mist','cheese-blocks','Milky Mist Cheese Block','milky-mist-cheese-block-500','500 g','440','milkymist'),
    ('Milky Mist','milky-mist','cheese-blocks','Milky Mist Cheese Block','milky-mist-cheese-block-1kg','1 kg','820','milkymist'),
    ('Milky Mist','milky-mist','cheese-cubes','Milky Mist Cheese Cubes','milky-mist-cheese-cubes-120','120 g','120','milkymist'),
    ('Milky Mist','milky-mist','cheese-cubes','Milky Mist Cheese Cubes','milky-mist-cheese-cubes-200','200 g','190','milkymist'),
    ('Milky Mist','milky-mist','cheese-cubes','Milky Mist Cheese Cubes','milky-mist-cheese-cubes-600','600 g','520','milkymist'),
    ('Milky Mist','milky-mist','cream-cheese','Milky Mist Cream Cheese','milky-mist-cream-cheese-200','200 g','190','milkymist'),
    ('Milky Mist','milky-mist','cream-cheese','Milky Mist Cream Cheese','milky-mist-cream-cheese-400','400 g','350','milkymist'),
    ('Milky Mist','milky-mist','cream-cheese','Milky Mist Cream Cheese','milky-mist-cream-cheese-1kg','1 kg','780','milkymist'),
    ('Milky Mist','milky-mist','cheese-spread','Milky Mist Cheese Spread','milky-mist-cheese-spread-200','200 g','160','milkymist'),
    ('Milky Mist','milky-mist','cheese-blocks','Milky Mist Natural Cheddar Cheese','milky-mist-cheddar-cheese-200','200 g','210','milkymist'),
    ('Milky Mist','milky-mist','cheese-blocks','Milky Mist Natural Cheddar Cheese','milky-mist-cheddar-cheese-1kg','1 kg','900','milkymist')
  ) x(brand,brand_slug,subcat,name,slug,pack,price,prefix) loop
    insert into dastak_v1.brands(name,slug,status,created_by) values(r.brand,r.brand_slug,'ACTIVE',a) on conflict(slug) do update set status='ACTIVE',updated_at=now();
    select id into b from dastak_v1.brands where slug=r.brand_slug;
    select sc.id into c from dastak_v1.subcategories sc join dastak_v1.categories ca on ca.id=sc.category_id join dastak_v1.category_types ct on ct.id=ca.category_type_id where ct.slug='dairy-bread-eggs' and sc.slug=r.subcat;
    if c is null then raise exception 'missing cheese subcategory %',r.subcat; end if;
    insert into dastak_v1.skus(subcategory_id,brand_id,canonical_name,slug,pack_size,description,image_key,list_price_paise,selling_price_paise,currency_code,tax_rate_bps,logistics_attributes,status,created_by,product_kind,quantity_value,quantity_unit,country_of_origin_code,diet_type,qa_status)
    values(c,b,r.name,r.slug,r.pack,'Branded '||r.name||' for Dastak delivery.','canonical/staging/cheese-brands/'||r.prefix||'-'||r.slug||'.'||case when r.prefix='amul' then 'png' else 'jpg' end,(r.price::numeric*100)::bigint,(r.price::numeric*100)::bigint,'INR',0,jsonb_build_object('temperatureClass','CHILLED'),'DRAFT',a,'PACKAGED',regexp_replace(r.pack,'[^0-9.]','','g')::numeric,case when r.pack like '%kg' then 'kg' else 'g' end,'IN','VEG','PENDING')
    on conflict(slug) do update set subcategory_id=excluded.subcategory_id,brand_id=excluded.brand_id,canonical_name=excluded.canonical_name,pack_size=excluded.pack_size,image_key=excluded.image_key,list_price_paise=excluded.list_price_paise,selling_price_paise=excluded.selling_price_paise,updated_at=now(),version=dastak_v1.skus.version+1 returning id into s;
    insert into dastak_v1.sku_images(sku_id,image_key,role,sort_order,source_type,source_reference,mime_type,status,created_by,verified_by,verified_at,rights_status,rights_reference,rights_verified_by,rights_verified_at) values(s,'canonical/staging/cheese-brands/'||r.prefix||'-'||r.slug||'.'||case when r.prefix='amul' then 'png' else 'jpg' end,'PRIMARY',0,'OWNER_CAPTURE','owner-curated branded Cheese artwork sourced from manufacturer product listing',case when r.prefix='amul' then 'image/png' else 'image/jpeg' end,'VERIFIED',a,a,now(),'CLEARED','owner-authorised catalogue artwork',a,now()) on conflict(sku_id) where role='PRIMARY' do update set image_key=excluded.image_key,status='VERIFIED',verified_by=a,verified_at=now(),rights_status='CLEARED',rights_verified_by=a,rights_verified_at=now(),version=dastak_v1.sku_images.version+1;
    update dastak_v1.skus set status='ACTIVE',qa_status='VERIFIED',qa_verified_by=a,qa_verified_at=now(),updated_at=now(),version=version+1 where id=s;
  end loop;
end; $$;
