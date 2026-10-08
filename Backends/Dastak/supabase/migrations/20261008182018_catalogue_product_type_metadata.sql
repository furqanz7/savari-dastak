-- Dedicated classification in the existing shared attribute contract. No SKU
-- classification/backfill, identity, stock, price, permission or status changes.
alter table dastak_v1.skus add constraint skus_product_type_valid check (
  not (attribute_data ? 'productType')
  or pg_catalog.jsonb_typeof(attribute_data->'productType') = 'null'
  or (
    pg_catalog.jsonb_typeof(attribute_data->'productType') = 'string'
    and pg_catalog.char_length(pg_catalog.btrim(attribute_data->>'productType')) between 1 and 100
    and (attribute_data->>'productType') !~ '[[:cntrl:]]'
  )
) not valid;
alter table dastak_v1.skus validate constraint skus_product_type_valid;

-- Preserve the deployed branch/actor guards, filters, pagination, stock fields
-- and grants exactly. Add only this public product fact, not arbitrary attributes.
do $projection$
declare
  original text;
  marker constant text := '''variant'', sku.variant_name,';
  addition constant text := '''variant'', sku.variant_name,
        ''attributes'', pg_catalog.jsonb_build_object(''productType'', sku.attribute_data->''productType''),';
begin
  original := pg_catalog.pg_get_functiondef('dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer)'::regprocedure);
  if (pg_catalog.length(original) - pg_catalog.length(pg_catalog.replace(original, marker, ''))) / pg_catalog.length(marker) <> 1
    or pg_catalog.strpos(original, '''attributes''') > 0 then
    raise exception 'Merchant catalogue projection has drifted; review before migration';
  end if;
  execute pg_catalog.replace(original, marker, addition);
end;
$projection$;
