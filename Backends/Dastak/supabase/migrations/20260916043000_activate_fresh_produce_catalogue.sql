-- Promote the curated Fresh Produce catalogue after its primary assets have
-- been uploaded to the canonical catalogue bucket.
do $$
declare
  v_actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b';
  v_now timestamptz := now();
begin
  update dastak_v1.category_types
  set status='ACTIVE', updated_at=v_now, version=version+1
  where slug='fresh-produce';

  update dastak_v1.categories c
  set status='ACTIVE', updated_at=v_now, version=c.version+1
  from dastak_v1.category_types ct
  where c.category_type_id=ct.id and ct.slug='fresh-produce';

  update dastak_v1.subcategories sc
  set status='ACTIVE', updated_at=v_now, version=sc.version+1
  from dastak_v1.categories c
  join dastak_v1.category_types ct on ct.id=c.category_type_id
  where sc.category_id=c.id and ct.slug='fresh-produce';

  insert into dastak_v1.sku_images (
    sku_id, image_key, role, sort_order, source_type, source_reference,
    mime_type, status, created_by, verified_by, verified_at,
    rights_status, rights_reference, rights_verified_by, rights_verified_at
  )
  select s.id,
    'canonical/staging/fresh-produce/fresh-produce-' || sc.slug || '-primary.png',
    'PRIMARY', 0, 'OWNER_CAPTURE',
    'owner-supplied Fresh Produce subcategory artwork',
    'image/png', 'VERIFIED', v_actor, v_actor, v_now,
    'CLEARED', 'owner-supplied artwork authorised for Dastak catalogue use', v_actor, v_now
  from dastak_v1.skus s
  join dastak_v1.subcategories sc on sc.id=s.subcategory_id
  join dastak_v1.categories c on c.id=sc.category_id
  join dastak_v1.category_types ct on ct.id=c.category_type_id
  where ct.slug='fresh-produce'
  on conflict (sku_id) where role='PRIMARY' do update set
    image_key=excluded.image_key,
    status='VERIFIED',
    verified_by=v_actor,
    verified_at=v_now,
    rights_status='CLEARED',
    rights_reference=excluded.rights_reference,
    rights_verified_by=v_actor,
    rights_verified_at=v_now,
    version=dastak_v1.sku_images.version+1;

  update dastak_v1.skus s
  set qa_status='VERIFIED', qa_verified_by=v_actor, qa_verified_at=v_now,
      status='ACTIVE', updated_at=v_now, version=s.version+1
  from dastak_v1.subcategories sc
  join dastak_v1.categories c on c.id=sc.category_id
  join dastak_v1.category_types ct on ct.id=c.category_type_id
  where s.subcategory_id=sc.id and ct.slug='fresh-produce';
end;
$$;
