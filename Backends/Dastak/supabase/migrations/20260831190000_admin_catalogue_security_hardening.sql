-- Close security and query-planning gaps introduced by the later catalogue
-- ingestion migrations. Raw catalogue source tables remain private; Admin
-- access continues through audited, permission-checked API functions.

alter table dastak_v1.catalogue_source_brand_aliases
  enable row level security;
alter table dastak_v1.catalogue_source_taxonomy_rules
  enable row level security;

revoke all on table dastak_v1.catalogue_source_brand_aliases
  from public, anon, authenticated;
revoke all on table dastak_v1.catalogue_source_taxonomy_rules
  from public, anon, authenticated;

create index if not exists catalogue_asset_jobs_created_by_idx
  on dastak_v1.catalogue_asset_ingestion_jobs(created_by);
create index if not exists catalogue_asset_jobs_import_item_idx
  on dastak_v1.catalogue_asset_ingestion_jobs(import_item_id);
create index if not exists catalogue_asset_jobs_sku_idx
  on dastak_v1.catalogue_asset_ingestion_jobs(sku_id);

create index if not exists catalogue_observations_created_by_idx
  on dastak_v1.catalogue_commercial_observations(created_by);
create index if not exists catalogue_import_batches_created_by_idx
  on dastak_v1.catalogue_import_batches(created_by);

create index if not exists catalogue_item_assets_created_by_idx
  on dastak_v1.catalogue_import_item_assets(created_by);
create index if not exists catalogue_item_assets_rights_actor_idx
  on dastak_v1.catalogue_import_item_assets(rights_verified_by);
create index if not exists catalogue_item_assets_verified_by_idx
  on dastak_v1.catalogue_import_item_assets(verified_by);

create index if not exists catalogue_item_ids_created_by_idx
  on dastak_v1.catalogue_import_item_identifiers(created_by);
create index if not exists catalogue_import_items_canonical_sku_fk_idx
  on dastak_v1.catalogue_import_items(canonical_sku_id);

create index if not exists catalogue_brand_aliases_created_by_idx
  on dastak_v1.catalogue_source_brand_aliases(created_by);
create index if not exists catalogue_crawl_jobs_batch_idx
  on dastak_v1.catalogue_source_crawl_jobs(batch_id);
create index if not exists catalogue_crawl_jobs_created_by_idx
  on dastak_v1.catalogue_source_crawl_jobs(created_by);
create index if not exists catalogue_taxonomy_rules_created_by_idx
  on dastak_v1.catalogue_source_taxonomy_rules(created_by);

create index if not exists sku_identifiers_created_by_idx
  on dastak_v1.sku_identifiers(created_by);
create index if not exists sku_images_created_by_idx
  on dastak_v1.sku_images(created_by);
create index if not exists sku_images_rights_actor_idx
  on dastak_v1.sku_images(rights_verified_by);
create index if not exists sku_images_verified_by_idx
  on dastak_v1.sku_images(verified_by);
create index if not exists sku_search_aliases_created_by_idx
  on dastak_v1.sku_search_aliases(created_by);
create index if not exists skus_qa_verified_by_idx
  on dastak_v1.skus(qa_verified_by);

comment on table dastak_v1.catalogue_source_brand_aliases is
  'Private normalization rules. Admin access is available only through permission-checked catalogue APIs.';
comment on table dastak_v1.catalogue_source_taxonomy_rules is
  'Private taxonomy normalization rules. Admin access is available only through permission-checked catalogue APIs.';
