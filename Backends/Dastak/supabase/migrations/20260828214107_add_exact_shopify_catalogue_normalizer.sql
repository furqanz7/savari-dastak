create or replace function dastak_v1_api.normalize_shopify_items_by_exact_rules(p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  r record;
  v_variant_measure text[];
  v_title_measure text[];
  v_pack_match text[];
  v_measure text[];
  v_qty numeric;
  v_unit text;
  v_unit_display text;
  v_pack_count integer;
  v_pack_size text;
  v_variant text;
  v_canonical text;
  v_price bigint;
  v_crossed bigint;
  v_issues jsonb;
  v_normalized integer := 0;
  v_asset_jobs integer := 0;
begin
  if p_limit < 1 or p_limit > 1000 then
    raise exception using errcode='22023',message='p_limit must be between 1 and 1000';
  end if;

  for r in
    select
      i.id as item_id,i.batch_id,i.source_key,i.raw_payload,i.issues,
      lower(regexp_replace(i.raw_payload->>'sourceUrl','^https://([^/?#]+).*$','\1')) as source_host,
      i.raw_payload->>'productTitle' as product_title,
      i.raw_payload->>'variantTitle' as variant_title,
      i.raw_payload->>'productType' as product_type,
      i.raw_payload->>'vendor' as source_vendor,
      nullif(i.raw_payload->>'sku','') as manufacturer_sku,
      nullif(i.raw_payload->>'featuredImage','') as featured_image,
      nullif(i.raw_payload->>'productPage','') as product_page,
      i.raw_payload->>'productId' as shopify_product_id,
      i.raw_payload->>'variantId' as shopify_variant_id,
      i.raw_payload->>'price' as source_price,
      i.raw_payload->>'compareAtPrice' as source_crossed_price,
      i.raw_payload->>'available' as source_available,
      i.raw_payload->>'sourceObservedAt' as source_observed_at,
      ba.id as brand_alias_id,ba.brand_id,
      br.name as brand_name,br.slug as brand_slug,
      tr.id as taxonomy_rule_id,tr.subcategory_id,
      sc.slug as subcategory_slug,c.slug as category_slug,ct.slug as category_type_slug,
      ib.created_by as actor_id
    from dastak_v1.catalogue_import_items i
    join dastak_v1.catalogue_import_batches ib on ib.id=i.batch_id
    join dastak_v1.catalogue_source_brand_aliases ba
      on ba.status='ACTIVE' and ba.confidence=100
     and ba.source_host=lower(regexp_replace(i.raw_payload->>'sourceUrl','^https://([^/?#]+).*$','\1'))
     and ba.vendor_key=lower(trim(coalesce(i.raw_payload->>'vendor','')))
    join dastak_v1.brands br on br.id=ba.brand_id
    join dastak_v1.catalogue_source_taxonomy_rules tr
      on tr.status='ACTIVE' and tr.confidence=100
     and tr.source_host=ba.source_host
     and tr.product_type_key=lower(trim(coalesce(i.raw_payload->>'productType','')))
    join dastak_v1.subcategories sc on sc.id=tr.subcategory_id
    join dastak_v1.categories c on c.id=sc.category_id
    join dastak_v1.category_types ct on ct.id=c.category_type_id
    where i.status='RAW'
      and i.raw_payload->>'source'='SHOPIFY_OFFICIAL_FEED'
      and nullif(trim(coalesce(i.raw_payload->>'productTitle','')),'') is not null
      and coalesce(i.raw_payload->>'productTitle','') !~* '(combo|assorted|trial pack|free gift|merchandise|insurance)'
      and coalesce(i.raw_payload->>'price','') ~ '^[0-9]+(?:\.[0-9]{1,2})?$'
      and (i.raw_payload->>'price')::numeric > 0
    order by i.created_at,i.id
    limit p_limit
  loop
    v_variant_measure := regexp_match(trim(coalesce(r.variant_title,'')),'^([0-9]+(?:\.[0-9]+)?)\s*(g|gm|gms|kg|ml|l|ltr|litre|litres)$','i');
    v_pack_match := regexp_match(trim(coalesce(r.variant_title,'')),'^pack\s+of\s+([1-9][0-9]*)$','i');
    if coalesce(r.product_title,'') ~* 'pack\s+of\s+[0-9]+(?:\.[0-9]+)?\s*(g|gm|gms|kg|ml|l|ltr|litre|litres)' then
      v_title_measure := null;
    else
      v_title_measure := regexp_match(trim(coalesce(r.product_title,'')),'([0-9]+(?:\.[0-9]+)?)\s*(g|gm|gms|kg|ml|l|ltr|litre|litres)\)?\s*$','i');
    end if;

    v_measure := coalesce(v_variant_measure,v_title_measure);
    if v_measure is null then continue; end if;

    if v_variant_measure is not null then
      v_pack_count := 1;
    elsif v_pack_match is not null and v_title_measure is not null then
      v_pack_count := (v_pack_match[1])::integer;
    elsif lower(trim(coalesce(r.variant_title,'')))='default title' and v_title_measure is not null then
      v_pack_count := 1;
    else
      continue;
    end if;
    if v_pack_count < 1 or v_pack_count > 24 then continue; end if;

    v_qty := (v_measure[1])::numeric;
    v_unit := lower(v_measure[2]);
    if v_unit in ('g','gm','gms') then v_unit := 'G'; v_unit_display := 'g';
    elsif v_unit='kg' then v_unit := 'KG'; v_unit_display := 'kg';
    elsif v_unit='ml' then v_unit := 'ML'; v_unit_display := 'mL';
    elsif v_unit in ('l','ltr','litre','litres') then v_unit := 'L'; v_unit_display := 'L';
    else continue;
    end if;

    if v_qty <= 0 then continue; end if;
    if (v_unit='G' and v_qty>5000) or (v_unit='KG' and v_qty>5) or
       (v_unit='ML' and v_qty>5000) or (v_unit='L' and v_qty>5) then
      continue;
    end if;

    v_pack_size := trim(to_char(v_qty,'FM999999990.###')) || ' ' || v_unit_display;
    if v_pack_count > 1 then v_pack_size := v_pack_size || ' × ' || v_pack_count::text; end if;

    v_variant := trim(r.product_title);
    if lower(v_variant) like lower(r.brand_name) || ' %' then
      v_variant := trim(substr(v_variant,char_length(r.brand_name)+1));
    end if;
    if v_variant='' then v_variant:=trim(r.product_title); end if;

    v_canonical := case when lower(trim(r.product_title)) like lower(r.brand_name) || '%'
                        then trim(r.product_title)
                        else r.brand_name || ' ' || trim(r.product_title) end;
    if v_canonical !~* '[0-9]+(?:\.[0-9]+)?\s*(g|gm|gms|kg|ml|l|ltr|litre|litres)' then
      v_canonical := v_canonical || ' ' || v_pack_size;
    elsif v_pack_count > 1 and v_canonical !~* '(pack\s+of\s+' || v_pack_count::text || '|×\s*' || v_pack_count::text || ')' then
      v_canonical := v_canonical || ' × ' || v_pack_count::text;
    end if;

    v_price := round((r.source_price)::numeric*100)::bigint;
    v_crossed := case when coalesce(r.source_crossed_price,'') ~ '^[0-9]+(?:\.[0-9]{1,2})?$' and (r.source_crossed_price)::numeric>0
                      then round((r.source_crossed_price)::numeric*100)::bigint else null end;

    v_issues := coalesce(r.issues,'[]'::jsonb)
      || jsonb_build_array('DASTAK_SELLING_PRICE_PENDING','GTIN_UNVERIFIED',case when r.featured_image is null then 'IMAGE_SOURCE_PENDING' else 'IMAGE_STORAGE_PENDING' end);

    update dastak_v1.catalogue_import_items
    set normalized_payload=jsonb_strip_nulls(jsonb_build_object(
          'canonicalName',v_canonical,
          'variant',v_variant,
          'brand',r.brand_name,
          'brandSlug',r.brand_slug,
          'productKind','PACKAGED',
          'quantityValue',v_qty,
          'quantityUnit',v_unit,
          'packCount',v_pack_count,
          'packSize',v_pack_size,
          'categoryTypeSlug',r.category_type_slug,
          'categorySlug',r.category_slug,
          'subcategorySlug',r.subcategory_slug,
          'manufacturerSku',r.manufacturer_sku,
          'shopifyProductId',case when r.shopify_product_id ~ '^[0-9]+$' then r.shopify_product_id::numeric else null end,
          'shopifyVariantId',case when r.shopify_variant_id ~ '^[0-9]+$' then r.shopify_variant_id::numeric else null end,
          'sourceCurrentPricePaise',v_price,
          'sourceCrossedPricePaise',v_crossed,
          'normalizationMethod','SHOPIFY_EXACT_RULE_V1',
          'brandAliasId',r.brand_alias_id,
          'taxonomyRuleId',r.taxonomy_rule_id
        )),
        issues=v_issues,
        status='NORMALIZED',updated_at=clock_timestamp(),version=version+1
    where id=r.item_id and status='RAW';
    if not found then continue; end if;
    v_normalized:=v_normalized+1;

    if r.manufacturer_sku is not null then
      insert into dastak_v1.catalogue_import_item_identifiers(import_item_id,identifier_type,identifier_value,normalized_value,is_primary,source_type,source_reference,verification_status,created_by)
      values(r.item_id,'MANUFACTURER_SKU',r.manufacturer_sku,upper(r.manufacturer_sku),true,'BRAND',r.product_page,'SOURCE_VERIFIED',r.actor_id)
      on conflict (import_item_id,identifier_type,normalized_value) do update set source_reference=excluded.source_reference,verification_status='SOURCE_VERIFIED';
    end if;
    if r.shopify_product_id ~ '^[0-9]+$' then
      insert into dastak_v1.catalogue_import_item_identifiers(import_item_id,identifier_type,identifier_value,normalized_value,is_primary,source_type,source_reference,verification_status,created_by)
      values(r.item_id,'SHOPIFY_PRODUCT_ID',r.shopify_product_id,r.shopify_product_id,false,'BRAND',r.product_page,'SOURCE_VERIFIED',r.actor_id)
      on conflict (import_item_id,identifier_type,normalized_value) do update set source_reference=excluded.source_reference,verification_status='SOURCE_VERIFIED';
    end if;
    if r.shopify_variant_id ~ '^[0-9]+$' then
      insert into dastak_v1.catalogue_import_item_identifiers(import_item_id,identifier_type,identifier_value,normalized_value,is_primary,source_type,source_reference,verification_status,created_by)
      values(r.item_id,'SHOPIFY_VARIANT_ID',r.shopify_variant_id,r.shopify_variant_id,false,'BRAND',r.product_page,'SOURCE_VERIFIED',r.actor_id)
      on conflict (import_item_id,identifier_type,normalized_value) do update set source_reference=excluded.source_reference,verification_status='SOURCE_VERIFIED';
    end if;

    insert into dastak_v1.catalogue_commercial_observations(import_item_id,sku_id,source_type,source_name,source_url,observed_mrp_paise,observed_selling_price_paise,currency_code,availability,observed_at,evidence,created_by)
    values(r.item_id,null,'BRAND','Official Shopify feed - '||r.source_host,coalesce(r.product_page,r.raw_payload->>'sourceUrl'),v_crossed,v_price,'INR',
           case when lower(coalesce(r.source_available,'false'))='true' then 'IN_STOCK' else 'SOLD_OUT' end,
           case when coalesce(r.source_observed_at,'')<>'' then r.source_observed_at::timestamptz else clock_timestamp() end,
           jsonb_build_object('normalizationMethod','SHOPIFY_EXACT_RULE_V1','brandAliasId',r.brand_alias_id,'taxonomyRuleId',r.taxonomy_rule_id),r.actor_id);

    if r.featured_image is not null and r.shopify_product_id ~ '^[0-9]+$' and r.shopify_variant_id ~ '^[0-9]+$' then
      insert into dastak_v1.catalogue_asset_ingestion_jobs(import_item_id,source_url,object_path,asset_role,source_type,status,attempts,max_attempts,next_attempt_at,created_by,created_at,updated_at)
      values(r.item_id,r.featured_image,'canonical/staging/auto/'||r.brand_slug||'/'||r.shopify_product_id||'-'||r.shopify_variant_id||'-primary.webp','PRIMARY','BRAND','PENDING',0,5,clock_timestamp(),r.actor_id,clock_timestamp(),clock_timestamp())
      on conflict (object_path) do nothing;
      if found then v_asset_jobs:=v_asset_jobs+1; end if;
    end if;
  end loop;

  update dastak_v1.catalogue_import_batches b
  set counts=jsonb_build_object(
        'rawItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id),
        'normalizedItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.normalized_payload is not null),
        'readyItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.status='READY'),
        'importedItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.status='IMPORTED')
      ),version=b.version+1
  where exists(select 1 from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.normalized_payload->>'normalizationMethod'='SHOPIFY_EXACT_RULE_V1');

  return jsonb_build_object('normalized',v_normalized,'assetJobsQueued',v_asset_jobs,'method','SHOPIFY_EXACT_RULE_V1');
end
$function$;

revoke all on function dastak_v1_api.normalize_shopify_items_by_exact_rules(integer) from public,anon,authenticated;
grant execute on function dastak_v1_api.normalize_shopify_items_by_exact_rules(integer) to service_role;;
