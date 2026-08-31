create table if not exists dastak_v1.catalogue_commercial_observations (
  id uuid primary key default gen_random_uuid(),
  import_item_id uuid references dastak_v1.catalogue_import_items(id) on delete cascade,
  sku_id uuid references dastak_v1.skus(id) on delete set null,
  source_type text not null,
  source_name text not null check (char_length(trim(source_name)) between 1 and 160),
  source_url text not null check (source_url ~ '^https://[^[:space:]]+$' and char_length(source_url) <= 2000),
  observed_mrp_paise bigint check (observed_mrp_paise is null or observed_mrp_paise >= 0),
  observed_selling_price_paise bigint check (observed_selling_price_paise is null or observed_selling_price_paise >= 0),
  currency_code text not null default 'INR' check (currency_code ~ '^[A-Z]{3}$'),
  availability text check (availability is null or availability in ('IN_STOCK','OUT_OF_STOCK','SOLD_OUT','UNKNOWN')),
  observed_at timestamptz not null,
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  created_by uuid references public.accounts(id),
  created_at timestamptz not null default now(),
  check (import_item_id is not null or sku_id is not null),
  check (observed_mrp_paise is not null or observed_selling_price_paise is not null or availability is not null)
);
create index if not exists catalogue_commercial_observations_item_idx
  on dastak_v1.catalogue_commercial_observations(import_item_id,observed_at desc);
create index if not exists catalogue_commercial_observations_sku_idx
  on dastak_v1.catalogue_commercial_observations(sku_id,observed_at desc);
create unique index if not exists catalogue_commercial_observations_dedupe_uidx
  on dastak_v1.catalogue_commercial_observations(
    coalesce(import_item_id,'00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(sku_id,'00000000-0000-0000-0000-000000000000'::uuid),
    source_url,observed_at
  );
alter table dastak_v1.catalogue_commercial_observations enable row level security;;
