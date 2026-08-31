create table if not exists dastak_v1.catalogue_import_item_assets (
  id uuid primary key default gen_random_uuid(),
  import_item_id uuid not null references dastak_v1.catalogue_import_items(id) on delete cascade,
  image_key text not null,
  role text not null default 'PRIMARY' check (role in ('PRIMARY','GALLERY')),
  sort_order integer not null default 0 check (sort_order >= 0),
  source_type text not null,
  source_reference text,
  checksum_sha256 text not null check (checksum_sha256 ~ '^[0-9a-f]{64}$'),
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/webp')),
  byte_size bigint not null check (byte_size > 0 and byte_size <= 8388608),
  status text not null default 'PENDING' check (status in ('PENDING','VERIFIED','REJECTED')),
  created_by uuid references public.accounts(id),
  created_at timestamptz not null default now(),
  verified_by uuid references public.accounts(id),
  verified_at timestamptz,
  unique (image_key)
);

create unique index if not exists catalogue_import_item_assets_primary_uidx
  on dastak_v1.catalogue_import_item_assets(import_item_id)
  where role='PRIMARY' and status <> 'REJECTED';
create index if not exists catalogue_import_item_assets_item_idx
  on dastak_v1.catalogue_import_item_assets(import_item_id, role, sort_order);

create table if not exists dastak_v1.catalogue_asset_ingestion_jobs (
  id uuid primary key default gen_random_uuid(),
  import_item_id uuid references dastak_v1.catalogue_import_items(id) on delete cascade,
  sku_id uuid references dastak_v1.skus(id) on delete set null,
  source_url text not null check (source_url ~ '^https://[^[:space:]]+$' and char_length(source_url) <= 2000),
  object_path text not null check (object_path ~ '^canonical/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$' and char_length(object_path) <= 500),
  asset_role text not null default 'PRIMARY' check (asset_role in ('PRIMARY','GALLERY')),
  source_type text not null,
  status text not null default 'PENDING' check (status in ('PENDING','PROCESSING','RETRY','COMPLETED','FAILED','CANCELLED')),
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  next_attempt_at timestamptz not null default now(),
  locked_by text,
  locked_at timestamptz,
  last_error text,
  created_by uuid references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  check (import_item_id is not null or sku_id is not null),
  unique (object_path)
);
create index if not exists catalogue_asset_jobs_claim_idx
  on dastak_v1.catalogue_asset_ingestion_jobs(status,next_attempt_at,created_at)
  where status in ('PENDING','RETRY');

alter table dastak_v1.catalogue_import_item_assets enable row level security;
alter table dastak_v1.catalogue_asset_ingestion_jobs enable row level security;

create or replace function dastak_v1_api.claim_catalogue_asset_jobs(
  p_worker_id text,
  p_limit integer default 20
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if p_worker_id is null or char_length(trim(p_worker_id)) < 1 then
    raise exception using errcode='22023', message='worker id is required';
  end if;
  with picked as (
    select j.id
    from dastak_v1.catalogue_asset_ingestion_jobs j
    where j.status in ('PENDING','RETRY')
      and j.next_attempt_at <= pg_catalog.clock_timestamp()
      and j.attempts < j.max_attempts
    order by j.created_at,j.id
    for update skip locked
    limit least(greatest(coalesce(p_limit,20),1),100)
  ), claimed as (
    update dastak_v1.catalogue_asset_ingestion_jobs j
    set status='PROCESSING',
        attempts=j.attempts+1,
        locked_by=p_worker_id,
        locked_at=pg_catalog.clock_timestamp(),
        updated_at=pg_catalog.clock_timestamp()
    from picked
    where j.id=picked.id
    returning j.*
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'jobId',c.id,
    'importItemId',c.import_item_id,
    'skuId',c.sku_id,
    'sourceUrl',c.source_url,
    'objectPath',c.object_path,
    'assetRole',c.asset_role,
    'sourceType',c.source_type,
    'attempt',c.attempts,
    'maxAttempts',c.max_attempts,
    'createdBy',c.created_by
  ) order by c.created_at,c.id),'[]'::jsonb) into v_result
  from claimed c;
  return v_result;
end $$;

create or replace function dastak_v1_api.complete_catalogue_asset_job(
  p_job_id uuid,
  p_worker_id text,
  p_succeeded boolean,
  p_image_key text default null,
  p_checksum_sha256 text default null,
  p_mime_type text default null,
  p_byte_size bigint default null,
  p_source_reference text default null,
  p_error text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_job dastak_v1.catalogue_asset_ingestion_jobs%rowtype;
declare v_terminal boolean;
begin
  select * into v_job from dastak_v1.catalogue_asset_ingestion_jobs where id=p_job_id for update;
  if not found then raise exception using errcode='P0002', message='catalogue asset job not found'; end if;
  if v_job.status <> 'PROCESSING' or v_job.locked_by is distinct from p_worker_id then
    raise exception using errcode='55000', message='catalogue asset job is not owned by worker';
  end if;

  if p_succeeded then
    if p_image_key is null or p_checksum_sha256 !~ '^[0-9a-f]{64}$'
       or p_mime_type not in ('image/jpeg','image/png','image/webp')
       or p_byte_size is null or p_byte_size <= 0 or p_byte_size > 8388608 then
      raise exception using errcode='22023', message='successful asset completion metadata is invalid';
    end if;

    if v_job.import_item_id is not null then
      insert into dastak_v1.catalogue_import_item_assets(
        import_item_id,image_key,role,source_type,source_reference,checksum_sha256,mime_type,byte_size,status,created_by
      ) values (
        v_job.import_item_id,p_image_key,v_job.asset_role,v_job.source_type,p_source_reference,p_checksum_sha256,p_mime_type,p_byte_size,'PENDING',v_job.created_by
      )
      on conflict (image_key) do nothing;
    end if;

    if v_job.sku_id is not null then
      insert into dastak_v1.sku_images(
        sku_id,image_key,role,sort_order,source_type,source_reference,checksum_sha256,mime_type,status,created_by
      ) values (
        v_job.sku_id,p_image_key,v_job.asset_role,0,v_job.source_type,p_source_reference,p_checksum_sha256,p_mime_type,'PENDING',v_job.created_by
      )
      on conflict do nothing;
    end if;

    update dastak_v1.catalogue_asset_ingestion_jobs
    set status='COMPLETED', completed_at=pg_catalog.clock_timestamp(), updated_at=pg_catalog.clock_timestamp(),
        locked_by=null, locked_at=null, last_error=null
    where id=p_job_id;
  else
    v_terminal := v_job.attempts >= v_job.max_attempts;
    update dastak_v1.catalogue_asset_ingestion_jobs
    set status=case when v_terminal then 'FAILED' else 'RETRY' end,
        next_attempt_at=case when v_terminal then next_attempt_at else pg_catalog.clock_timestamp() + make_interval(mins => least(60, greatest(1, attempts*attempts))) end,
        last_error=left(coalesce(p_error,'asset ingestion failed'),1000),
        updated_at=pg_catalog.clock_timestamp(), locked_by=null, locked_at=null
    where id=p_job_id;
  end if;

  return pg_catalog.jsonb_build_object('jobId',p_job_id,'status',(select status from dastak_v1.catalogue_asset_ingestion_jobs where id=p_job_id));
end $$;

create or replace function public.dastak_v1_claim_catalogue_asset_jobs(p_worker_id text,p_limit integer default 20)
returns jsonb language sql security definer set search_path='' as $$
  select dastak_v1_api.claim_catalogue_asset_jobs(p_worker_id,p_limit);
$$;
create or replace function public.dastak_v1_complete_catalogue_asset_job(
  p_job_id uuid,p_worker_id text,p_succeeded boolean,p_image_key text default null,p_checksum_sha256 text default null,
  p_mime_type text default null,p_byte_size bigint default null,p_source_reference text default null,p_error text default null
) returns jsonb language sql security definer set search_path='' as $$
  select dastak_v1_api.complete_catalogue_asset_job(p_job_id,p_worker_id,p_succeeded,p_image_key,p_checksum_sha256,p_mime_type,p_byte_size,p_source_reference,p_error);
$$;

revoke all on function public.dastak_v1_claim_catalogue_asset_jobs(text,integer) from public,anon,authenticated;
revoke all on function public.dastak_v1_complete_catalogue_asset_job(uuid,text,boolean,text,text,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.dastak_v1_claim_catalogue_asset_jobs(text,integer) to service_role;
grant execute on function public.dastak_v1_complete_catalogue_asset_job(uuid,text,boolean,text,text,text,bigint,text,text) to service_role;;
