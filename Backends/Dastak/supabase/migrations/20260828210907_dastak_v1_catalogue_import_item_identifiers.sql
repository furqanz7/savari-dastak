create table if not exists dastak_v1.catalogue_import_item_identifiers (
  id uuid primary key default gen_random_uuid(),
  import_item_id uuid not null references dastak_v1.catalogue_import_items(id) on delete cascade,
  identifier_type text not null check (identifier_type in ('EAN13','GTIN','UPC','MANUFACTURER_SKU','SHOPIFY_PRODUCT_ID','SHOPIFY_VARIANT_ID')),
  identifier_value text not null check (char_length(trim(identifier_value)) between 1 and 128),
  normalized_value text not null check (char_length(trim(normalized_value)) between 1 and 128),
  is_primary boolean not null default false,
  source_type text not null,
  source_reference text,
  verification_status text not null default 'SOURCE_VERIFIED' check (verification_status in ('SOURCE_VERIFIED','MANUALLY_VERIFIED','REJECTED')),
  created_by uuid references public.accounts(id),
  created_at timestamptz not null default now(),
  unique(import_item_id,identifier_type,normalized_value)
);
create index if not exists catalogue_import_item_identifiers_value_idx
  on dastak_v1.catalogue_import_item_identifiers(identifier_type,normalized_value);
alter table dastak_v1.catalogue_import_item_identifiers enable row level security;;
