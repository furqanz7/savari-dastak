create table if not exists dastak_v1.catalogue_source_brand_aliases (
  id uuid primary key default gen_random_uuid(),
  source_host text not null check (source_host ~ '^[a-z0-9.-]+$' and char_length(source_host) <= 255),
  source_vendor text not null check (char_length(trim(source_vendor)) between 1 and 200),
  vendor_key text not null check (char_length(trim(vendor_key)) between 1 and 200),
  brand_id uuid not null references dastak_v1.brands(id),
  confidence smallint not null default 100 check (confidence between 0 and 100),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','DISABLED')),
  notes text,
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_host,vendor_key)
);

create index if not exists catalogue_source_brand_aliases_brand_idx
  on dastak_v1.catalogue_source_brand_aliases(brand_id,status);

create table if not exists dastak_v1.catalogue_source_taxonomy_rules (
  id uuid primary key default gen_random_uuid(),
  source_host text not null check (source_host ~ '^[a-z0-9.-]+$' and char_length(source_host) <= 255),
  source_product_type text not null check (char_length(trim(source_product_type)) between 1 and 200),
  product_type_key text not null check (char_length(trim(product_type_key)) between 1 and 200),
  subcategory_id uuid not null references dastak_v1.subcategories(id),
  confidence smallint not null default 100 check (confidence between 0 and 100),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','DISABLED')),
  notes text,
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_host,product_type_key)
);

create index if not exists catalogue_source_taxonomy_rules_subcategory_idx
  on dastak_v1.catalogue_source_taxonomy_rules(subcategory_id,status);

revoke all on dastak_v1.catalogue_source_brand_aliases from anon, authenticated;
revoke all on dastak_v1.catalogue_source_taxonomy_rules from anon, authenticated;;
