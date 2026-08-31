create table if not exists dastak_v1.catalogue_source_crawl_jobs (
  id uuid primary key default gen_random_uuid(),
  source_name text not null check (char_length(trim(source_name)) between 1 and 160),
  source_type text not null check (source_type in ('MANUFACTURER','BRAND','DISTRIBUTOR','PUBLIC_REFERENCE','OTHER')),
  feed_url text not null check (feed_url ~ '^https://[^[:space:]]+$' and char_length(feed_url) <= 2000),
  parser_type text not null check (parser_type in ('SHOPIFY_PRODUCTS_JSON')),
  batch_id uuid references dastak_v1.catalogue_import_batches(id) on delete set null,
  status text not null default 'PENDING' check (status in ('PENDING','PROCESSING','RETRY','COMPLETED','FAILED','CANCELLED')),
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 3 check (max_attempts between 1 and 10),
  next_attempt_at timestamptz not null default now(),
  locked_by text,
  locked_at timestamptz,
  result_counts jsonb not null default '{}'::jsonb check (jsonb_typeof(result_counts)='object'),
  last_error text,
  created_by uuid references public.accounts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(feed_url)
);
create index if not exists catalogue_source_crawl_jobs_claim_idx
  on dastak_v1.catalogue_source_crawl_jobs(status,next_attempt_at,created_at)
  where status in ('PENDING','RETRY');
alter table dastak_v1.catalogue_source_crawl_jobs enable row level security;

create or replace function dastak_v1_api.claim_catalogue_source_crawl_jobs(p_worker_id text,p_limit integer default 3)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if p_worker_id is null or char_length(trim(p_worker_id))<1 then raise exception using errcode='22023',message='worker id required'; end if;
  with picked as (
    select j.id from dastak_v1.catalogue_source_crawl_jobs j
    where j.status in ('PENDING','RETRY') and j.next_attempt_at<=clock_timestamp() and j.attempts<j.max_attempts
    order by j.created_at,j.id for update skip locked
    limit least(greatest(coalesce(p_limit,3),1),10)
  ), claimed as (
    update dastak_v1.catalogue_source_crawl_jobs j
    set status='PROCESSING',attempts=j.attempts+1,locked_by=p_worker_id,locked_at=clock_timestamp(),updated_at=clock_timestamp()
    from picked where j.id=picked.id returning j.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'jobId',c.id,'sourceName',c.source_name,'sourceType',c.source_type,'feedUrl',c.feed_url,
    'parserType',c.parser_type,'batchId',c.batch_id,'attempt',c.attempts,'maxAttempts',c.max_attempts,'createdBy',c.created_by
  ) order by c.created_at,c.id),'[]'::jsonb) into v_result from claimed c;
  return v_result;
end $$;

create or replace function dastak_v1_api.complete_catalogue_source_crawl_job(
  p_job_id uuid,p_worker_id text,p_succeeded boolean,p_batch_id uuid default null,p_counts jsonb default '{}'::jsonb,p_error text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job dastak_v1.catalogue_source_crawl_jobs%rowtype;
declare v_terminal boolean;
begin
  select * into v_job from dastak_v1.catalogue_source_crawl_jobs where id=p_job_id for update;
  if not found then raise exception using errcode='P0002',message='catalogue source crawl job not found'; end if;
  if v_job.status<>'PROCESSING' or v_job.locked_by is distinct from p_worker_id then raise exception using errcode='55000',message='catalogue source crawl job is not owned by worker'; end if;
  if p_succeeded then
    update dastak_v1.catalogue_source_crawl_jobs set status='COMPLETED',batch_id=coalesce(p_batch_id,batch_id),result_counts=coalesce(p_counts,'{}'::jsonb),completed_at=clock_timestamp(),updated_at=clock_timestamp(),locked_by=null,locked_at=null,last_error=null where id=p_job_id;
  else
    v_terminal:=v_job.attempts>=v_job.max_attempts;
    update dastak_v1.catalogue_source_crawl_jobs
    set status=case when v_terminal then 'FAILED' else 'RETRY' end,
        next_attempt_at=case when v_terminal then next_attempt_at else clock_timestamp()+make_interval(mins=>least(30,greatest(1,attempts*attempts))) end,
        last_error=left(coalesce(p_error,'source crawl failed'),1000),updated_at=clock_timestamp(),locked_by=null,locked_at=null
    where id=p_job_id;
  end if;
  return jsonb_build_object('jobId',p_job_id,'status',(select status from dastak_v1.catalogue_source_crawl_jobs where id=p_job_id));
end $$;

create or replace function public.dastak_v1_claim_catalogue_source_crawl_jobs(p_worker_id text,p_limit integer default 3)
returns jsonb language sql security definer set search_path='' as $$select dastak_v1_api.claim_catalogue_source_crawl_jobs(p_worker_id,p_limit);$$;
create or replace function public.dastak_v1_complete_catalogue_source_crawl_job(p_job_id uuid,p_worker_id text,p_succeeded boolean,p_batch_id uuid default null,p_counts jsonb default '{}'::jsonb,p_error text default null)
returns jsonb language sql security definer set search_path='' as $$select dastak_v1_api.complete_catalogue_source_crawl_job(p_job_id,p_worker_id,p_succeeded,p_batch_id,p_counts,p_error);$$;
revoke all on function public.dastak_v1_claim_catalogue_source_crawl_jobs(text,integer) from public,anon,authenticated;
revoke all on function public.dastak_v1_complete_catalogue_source_crawl_job(uuid,text,boolean,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.dastak_v1_claim_catalogue_source_crawl_jobs(text,integer) to service_role;
grant execute on function public.dastak_v1_complete_catalogue_source_crawl_job(uuid,text,boolean,uuid,jsonb,text) to service_role;;
