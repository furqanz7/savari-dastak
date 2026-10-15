-- Replace the renamed destination's underlying taxonomy, rather than exposing
-- the old Puja categories beneath its new customer-facing label.
do $$
declare
  v_old_type uuid;
  v_new_type uuid;
  v_actor uuid;
  v_version integer;
  v_archived_skus integer;
begin
  select id, created_by into strict v_old_type, v_actor
  from dastak_v1.category_types where slug = 'puja-festive' for update;
  select version into strict v_version
  from dastak_v1.catalogue_browse_versions where state = 'ACTIVE';
  if not exists (select 1 from dastak_v1.catalogue_browse_nodes
      where version=v_version and node_key='pooja-store'
        and kind='DESTINATION' and label='Janamaz and Tasbih') then
    raise exception 'Expected renamed Janamaz and Tasbih destination';
  end if;
  if exists (select 1 from dastak_v1.catalogue_browse_nodes
      where version=v_version and parent_key='pooja-store') then
    raise exception 'Destination already has rails; review before replacement';
  end if;
  if exists (select 1 from dastak_v1.category_types where slug='prayer-essentials') then
    raise exception 'Prayer essentials type already exists; review before replacement';
  end if;

  -- Archive any old SKU before retiring its parents. INACTIVE SKUs are excluded
  -- from sale; the existing trigger clears merchant selections. Retain identities
  -- needed by historical orders. The live preflight found zero old SKUs.
  insert into dastak_v1.audit_events(actor_id,action,resource_type,resource_id,metadata)
  select v_actor,'CATALOGUE_SKU_ARCHIVED','catalogue_sku',s.id,
    jsonb_build_object('name',s.canonical_name,'reason','User requested removal of all former Pooja Store products')
  from dastak_v1.skus s
  join dastak_v1.subcategories sc on sc.id=s.subcategory_id
  join dastak_v1.categories c on c.id=sc.category_id
  where c.category_type_id=v_old_type and s.status<>'INACTIVE';

  update dastak_v1.skus s set status='INACTIVE',updated_at=now(),version=s.version+1
  from dastak_v1.subcategories sc join dastak_v1.categories c on c.id=sc.category_id
  where s.subcategory_id=sc.id and c.category_type_id=v_old_type and s.status<>'INACTIVE';
  get diagnostics v_archived_skus = row_count;

  delete from dastak_v1.merchant_sku_selections m
  using dastak_v1.skus s,dastak_v1.subcategories sc,dastak_v1.categories c
  where m.sku_id=s.id and s.subcategory_id=sc.id and sc.category_id=c.id
    and c.category_type_id=v_old_type;

  update dastak_v1.subcategories sc
  set status='INACTIVE',image_key=null,updated_at=now(),version=sc.version+1
  from dastak_v1.categories c where sc.category_id=c.id and c.category_type_id=v_old_type;
  update dastak_v1.categories set status='INACTIVE',image_key=null,updated_at=now(),version=version+1
  where category_type_id=v_old_type;
  update dastak_v1.category_types set status='INACTIVE',image_key=null,updated_at=now(),version=version+1
  where id=v_old_type;

  insert into dastak_v1.category_types(name,slug,status,sort_order,created_by)
  select 'Janamaz and Tasbih','prayer-essentials','ACTIVE',sort_order,v_actor
  from dastak_v1.category_types where id=v_old_type returning id into v_new_type;

  insert into dastak_v1.categories(category_type_id,name,slug,status,sort_order,created_by)
  select v_new_type,name,slug,'ACTIVE',sort_order,v_actor from (values
    ('Janamaz','janamaz',10),('Tasbih','tasbih',20),('Ittar','ittar',30),
    ('Quran Stands','quran-stands',40),('Salah Caps','salah-caps',50),
    ('Prayer Clothing','prayer-clothing',60),('Miswak','miswak',70),
    ('Qibla Compasses','qibla-compasses',80),('Prayer Accessories','prayer-accessories',90)
  ) as categories(name,slug,sort_order);

  insert into dastak_v1.subcategories(category_id,name,slug,status,sort_order,created_by)
  select c.id,seed.name,seed.slug,'ACTIVE',seed.sort_order,v_actor
  from (values
    ('janamaz','Standard Janamaz','standard-janamaz',10),
    ('janamaz','Padded Janamaz','padded-janamaz',20),
    ('janamaz','Travel Janamaz','travel-janamaz',30),
    ('janamaz','Children''s Janamaz','childrens-janamaz',40),
    ('tasbih','33-Bead Tasbih','33-bead-tasbih',10),
    ('tasbih','99-Bead Tasbih','99-bead-tasbih',20),
    ('tasbih','Digital Tasbih','digital-tasbih',30),
    ('tasbih','Finger Counters','finger-counters',40),
    ('ittar','Oud Ittar','oud-ittar',10),
    ('ittar','Musk Ittar','musk-ittar',20),
    ('ittar','Floral Ittar','floral-ittar',30),
    ('ittar','Sandalwood Ittar','sandalwood-ittar',40),
    ('ittar','Ittar Gift Sets','ittar-gift-sets',50),
    ('quran-stands','Wooden Quran Stands','wooden-quran-stands',10),
    ('quran-stands','Foldable Quran Stands','foldable-quran-stands',20),
    ('quran-stands','Adjustable Quran Stands','adjustable-quran-stands',30),
    ('salah-caps','Cotton Salah Caps','cotton-salah-caps',10),
    ('salah-caps','Crochet Salah Caps','crochet-salah-caps',20),
    ('salah-caps','Embroidered Salah Caps','embroidered-salah-caps',30),
    ('salah-caps','Children''s Salah Caps','childrens-salah-caps',40),
    ('prayer-clothing','Prayer Dresses','prayer-dresses',10),
    ('prayer-clothing','Prayer Hijabs and Khimars','prayer-hijabs-khimars',20),
    ('prayer-clothing','Children''s Prayer Sets','childrens-prayer-sets',30),
    ('miswak','Natural Miswak','natural-miswak',10),
    ('miswak','Miswak Holders','miswak-holders',20),
    ('qibla-compasses','Pocket Qibla Compasses','pocket-qibla-compasses',10),
    ('qibla-compasses','Digital Qibla Compasses','digital-qibla-compasses',20),
    ('prayer-accessories','Janamaz Bags','janamaz-bags',10),
    ('prayer-accessories','Tasbih Pouches','tasbih-pouches',20),
    ('prayer-accessories','Prayer Gift Sets','prayer-gift-sets',30)
  ) as seed(category_slug,name,slug,sort_order)
  join dastak_v1.categories c on c.category_type_id=v_new_type and c.slug=seed.category_slug;

  -- Preserve the installed clients' destination key, but replace every old source.
  delete from dastak_v1.catalogue_browse_sources
  where version=v_version and node_key='pooja-store';
  insert into dastak_v1.catalogue_browse_sources(version,node_key,source_order,type_slug)
  values(v_version,'pooja-store',10,'prayer-essentials');

  insert into dastak_v1.catalogue_browse_nodes(version,node_key,parent_key,kind,label,sort_order)
  select v_version,c.slug,'pooja-store','RAIL',c.name,c.sort_order
  from dastak_v1.categories c where c.category_type_id=v_new_type;
  insert into dastak_v1.catalogue_browse_sources(version,node_key,source_order,type_slug,category_slug)
  select v_version,c.slug,10,'prayer-essentials',c.slug
  from dastak_v1.categories c where c.category_type_id=v_new_type;

  if (select count(*) from dastak_v1.categories where category_type_id=v_new_type and status='ACTIVE')<>9
    or (select count(*) from dastak_v1.subcategories sc join dastak_v1.categories c on c.id=sc.category_id
        where c.category_type_id=v_new_type and sc.status='ACTIVE')<>30 then
    raise exception 'Prayer essentials taxonomy is incomplete';
  end if;
  if exists (select 1 from dastak_v1.skus s join dastak_v1.subcategories sc on sc.id=s.subcategory_id
      join dastak_v1.categories c on c.id=sc.category_id
      where c.category_type_id=v_old_type and s.status<>'INACTIVE') then
    raise exception 'Former Pooja Store products remain enabled';
  end if;
  insert into dastak_v1.audit_events(actor_id,action,resource_type,resource_id,metadata)
  values(v_actor,'CATALOGUE_PRAYER_ESSENTIALS_REPLACED','category_type',v_new_type,
    jsonb_build_object('previousTypeId',v_old_type,'categories',9,'subcategories',30,
      'archivedSkus',v_archived_skus,'reason','User requested replacing Pooja Store taxonomy and removing its products'));
end;
$$;
