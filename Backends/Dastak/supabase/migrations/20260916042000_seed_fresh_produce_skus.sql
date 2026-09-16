-- Seed one catalogue SKU for every Fresh Produce subcategory.
-- These are owner-curated draft records: they provide the complete SKU
-- catalogue without claiming image/rights or QA verification prematurely.
do $$
declare
  v_actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b';
  v_batch uuid := gen_random_uuid();
  v_sku record;
  v_name text;
  v_slug text;
  v_pack text;
  v_price bigint;
begin
  insert into dastak_v1.catalogue_import_batches (
    id, source_type, source_name, source_reference, status, counts, created_by, completed_at
  ) values (
    v_batch, 'OWNER_CURATED', 'Fresh Produce starter SKU catalogue',
    'dastak://catalogue/fresh-produce/starter-2026-09-16', 'COMPLETED',
    jsonb_build_object('categoryType', 'fresh-produce', 'subcategories', 54, 'skus', 54),
    v_actor, now()
  );

  for v_sku in
    select sc.id, sc.slug, sc.name, sc.sort_order
    from dastak_v1.subcategories sc
    join dastak_v1.categories c on c.id = sc.category_id
    join dastak_v1.category_types ct on ct.id = c.category_type_id
    where ct.slug = 'fresh-produce'
    order by sc.slug
  loop
    v_slug := 'fresh-produce-' || v_sku.slug;
    v_name := v_sku.name || ' selection';
    v_pack := case
      when v_sku.slug in ('banana','apple','citrus-fruits','grapes','pomegranate','papaya','pineapple','guava','sapota-chikoo','berries','imported-fruits','mangoes','watermelon','muskmelon','jackfruit','custard-apple','indian-seasonal-fruits','avocado','broccoli','zucchini','lettuce','celery','imported-vegetables','microgreens') then '1 kg'
      when v_sku.slug in ('loose-flowers','garlands','banana-leaves','betel-leaves','puja-leaves') then '1 pack'
      when v_sku.slug in ('cut-fruits','cut-vegetables','mixed-fruit-packs','sprouts','salad-mixes') then '250 g'
      else '500 g'
    end;
    v_price := case
      when v_sku.slug in ('berries','imported-fruits','avocado','microgreens','loose-flowers','garlands') then 29900
      when v_sku.slug in ('pomegranate','pineapple','mangoes','jackfruit','custard-apple','imported-vegetables','salad-mixes') then 14900
      else 7900
    end;

    insert into dastak_v1.skus (
      subcategory_id, canonical_name, slug, pack_size, description,
      list_price_paise, selling_price_paise, currency_code, tax_rate_bps,
      logistics_attributes, status, created_by, product_kind, quantity_value,
      quantity_unit, country_of_origin_code, diet_type, qa_status
    ) values (
      v_sku.id, v_name, v_slug, v_pack,
      'Fresh ' || lower(v_sku.name) || ', curated for Dastak grocery delivery.',
      v_price, v_price, 'INR', 0,
      jsonb_build_object('weightGrams', case when v_pack like '%kg' then 1000 else 500 end, 'temperatureClass', 'AMBIENT'),
      'DRAFT', v_actor, 'FRESH',
      case when v_pack like '%kg' then 1 else 0.5 end,
      case when v_pack like '%kg' then 'kg' else 'pack' end,
      'IN', 'VEG', 'PENDING'
    )
    on conflict (slug) do nothing;

    insert into dastak_v1.catalogue_import_items (
      batch_id, source_key, raw_payload, normalized_payload, status, canonical_sku_id
    )
    select v_batch, v_slug,
      jsonb_build_object('subcategorySlug', v_sku.slug, 'name', v_name, 'packSize', v_pack, 'pricePaise', v_price),
      jsonb_build_object('subcategorySlug', v_sku.slug, 'name', v_name, 'packSize', v_pack, 'pricePaise', v_price),
      'IMPORTED', s.id
    from dastak_v1.skus s
    where s.slug = v_slug
    on conflict (batch_id, source_key) do nothing;
  end loop;
end;
$$;
