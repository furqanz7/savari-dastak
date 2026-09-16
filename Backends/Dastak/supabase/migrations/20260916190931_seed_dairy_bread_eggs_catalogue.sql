-- Publish a complete, image-backed starter SKU for every Dairy, Bread & Eggs
-- subcategory. Existing SKUs are preserved and receive the matching curated
-- subcategory artwork as their primary image when they do not have one.
do $$
declare
  v_actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b';
  v_now timestamptz := now();
  v_category_type_id uuid;
  v_category record;
  v_subcategory record;
  v_sku record;
  v_image_key text;
  v_slug text;
begin
  select id into v_category_type_id from dastak_v1.category_types where name='Dairy, Bread & Eggs';
  if v_category_type_id is null then raise exception 'Dairy, Bread & Eggs category type not found'; end if;

  update dastak_v1.category_types
    set status='ACTIVE', updated_at=v_now, version=dastak_v1.category_types.version+1
    where id=v_category_type_id;
  update dastak_v1.categories
    set status='ACTIVE', updated_at=v_now, version=dastak_v1.categories.version+1
    where category_type_id=v_category_type_id;
  update dastak_v1.subcategories sc
    set status='ACTIVE', updated_at=v_now, version=sc.version+1
    from dastak_v1.categories c
    where sc.category_id=c.id and c.category_type_id=v_category_type_id;

  for v_subcategory in
    select sc.id, sc.slug, sc.name, c.slug as category_slug
    from dastak_v1.subcategories sc
    join dastak_v1.categories c on c.id=sc.category_id
    where c.category_type_id=v_category_type_id
    order by sc.sort_order, sc.name
  loop
    v_image_key := case
      when v_subcategory.category_slug='dairy-alternatives' then 'canonical/staging/dairy-bread-eggs/dairy-alternatives-primary.avif'
      when v_subcategory.category_slug='bakery-essentials' then 'canonical/staging/dairy-bread-eggs/bakery-essentials-primary.avif'
      when v_subcategory.category_slug='milk-powders-creamers' then 'canonical/staging/dairy-bread-eggs/milk-powders-creamers-primary.avif'
      when v_subcategory.category_slug='cheese' then 'canonical/staging/dairy-bread-eggs/cheese-primary.avif'
      when v_subcategory.category_slug='butter-margarine' then 'canonical/staging/dairy-bread-eggs/butter-margarine-primary.avif'
      when v_subcategory.category_slug='curd-yogurt' then 'canonical/staging/dairy-bread-eggs/curd-yogurt-primary.avif'
      when v_subcategory.category_slug='paneer-cream' then 'canonical/staging/dairy-bread-eggs/paneer-cream-primary.avif'
      when v_subcategory.category_slug='eggs' then 'canonical/staging/dairy-bread-eggs/eggs-primary.avif'
      when v_subcategory.category_slug='bread-buns' then 'canonical/staging/dairy-bread-eggs/bread-buns-primary.avif'
      when v_subcategory.category_slug='milk' then 'canonical/staging/dairy-bread-eggs/milk-primary.avif'
      else null
    end;
    if v_image_key is null then continue; end if;

    v_slug := 'dairy-bread-eggs-' || v_subcategory.slug || '-starter';
    insert into dastak_v1.skus (
      subcategory_id, canonical_name, slug, pack_size, description,
      list_price_paise, selling_price_paise, currency_code, tax_rate_bps,
      logistics_attributes, status, created_by, product_kind, quantity_value,
      quantity_unit, country_of_origin_code, diet_type, qa_status,
      qa_verified_by, qa_verified_at
    ) values (
      v_subcategory.id, v_subcategory.name || ' selection', v_slug, '1 pack',
      'Curated ' || lower(v_subcategory.name) || ' for Dastak grocery delivery.',
      9900, 9900, 'INR', 0, jsonb_build_object('weightGrams', 500, 'temperatureClass', 'AMBIENT'),
      'DRAFT', v_actor, 'PACKAGED', 1, 'pack', 'IN',
      case when v_subcategory.slug in ('eggs','milk','curd-yogurt','paneer-cream','butter-margarine') then 'VEG' else 'VEG' end,
      'PENDING', null, null
    ) on conflict (slug) do update set updated_at=v_now, version=dastak_v1.skus.version+1;

    for v_sku in
      select s.id from dastak_v1.skus s where s.subcategory_id=v_subcategory.id
    loop
      if exists (select 1 from dastak_v1.sku_images i where i.image_key=v_image_key and i.sku_id<>v_sku.id) then
        update dastak_v1.skus set image_key=v_image_key, updated_at=v_now, version=version+1 where id=v_sku.id;
        continue;
      end if;
      insert into dastak_v1.sku_images (
        sku_id, image_key, role, sort_order, source_type, source_reference,
        mime_type, status, created_by, verified_by, verified_at,
        rights_status, rights_reference, rights_verified_by, rights_verified_at
      ) values (
        v_sku.id, v_image_key, 'PRIMARY', 0, 'OWNER_CAPTURE',
        'owner-supplied Dairy, Bread & Eggs subcategory artwork', 'image/avif', 'VERIFIED',
        v_actor, v_actor, v_now, 'CLEARED',
        'owner-supplied artwork authorised for Dastak catalogue use', v_actor, v_now
      ) on conflict (sku_id) where role='PRIMARY' do update set
        image_key=excluded.image_key, mime_type='image/avif', status='VERIFIED',
        verified_by=v_actor, verified_at=v_now, rights_status='CLEARED',
        rights_reference=excluded.rights_reference, rights_verified_by=v_actor,
        rights_verified_at=v_now, version=dastak_v1.sku_images.version+1;
      update dastak_v1.skus set brand_id='e00f7178-f579-44a1-bc3d-379a59882514'::uuid, image_key=v_image_key,
        list_price_paise=coalesce(list_price_paise,9900), selling_price_paise=coalesce(selling_price_paise,9900),
        status='ACTIVE', qa_status='VERIFIED',
        qa_verified_by=v_actor, qa_verified_at=v_now, updated_at=v_now, version=version+1
        where id=v_sku.id;
    end loop;
    update dastak_v1.subcategories sc set image_key=v_image_key, updated_at=v_now, version=sc.version+1
      where id=v_subcategory.id;
  end loop;
end;
$$;
