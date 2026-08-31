alter table dastak_v1.catalogue_source_crawl_jobs
  drop constraint catalogue_source_crawl_jobs_parser_type_check;

alter table dastak_v1.catalogue_source_crawl_jobs
  add constraint catalogue_source_crawl_jobs_parser_type_check
  check (parser_type = any(array['SHOPIFY_PRODUCTS_JSON'::text,'OPENFOODFACTS_V2_SEARCH'::text]));;
