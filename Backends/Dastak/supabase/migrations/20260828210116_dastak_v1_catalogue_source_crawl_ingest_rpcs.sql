create or replace function dastak_v1_api.ensure_catalogue_source_crawl_batch(p_job_id uuid,p_worker_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_job dastak_v1.catalogue_source_crawl_jobs%rowtype;
declare v_batch uuid;
begin
  select * into v_job from dastak_v1.catalogue_source_crawl_jobs where id=p_job_id for update;
  if not found then raise exception using errcode='P0002',message='catalogue source crawl job not found'; end if;
  if v_job.status<>'PROCESSING' or v_job.locked_by is distinct from p_worker_id then raise exception using errcode='55000',message='catalogue source crawl job is not owned by worker'; end if;
  if v_job.batch_id is not null then return v_job.batch_id; end if;
  insert into dastak_v1.catalogue_import_batches(source_type,source_name,source_reference,status,counts,created_by)
  values(v_job.source_type,'Bulk Feed - '||v_job.source_name,v_job.feed_url,'INGESTING','{}'::jsonb,v_job.created_by)
  returning id into v_batch;
  update dastak_v1.catalogue_source_crawl_jobs set batch_id=v_batch,updated_at=clock_timestamp() where id=p_job_id;
  return v_batch;
end $$;

create or replace function dastak_v1_api.ingest_catalogue_source_raw_items(p_batch_id uuid,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inserted integer:=0;
declare v_updated integer:=0;
declare v_item jsonb;
declare v_key text;
declare v_raw jsonb;
declare v_fingerprint text;
begin
  if jsonb_typeof(p_items)<>'array' then raise exception using errcode='22023',message='items must be an array'; end if;
  if jsonb_array_length(p_items)>5000 then raise exception using errcode='22023',message='too many source items'; end if;
  if not exists(select 1 from dastak_v1.catalogue_import_batches where id=p_batch_id) then raise exception using errcode='P0002',message='catalogue import batch not found'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_key:=nullif(trim(v_item->>'sourceKey'),'');
    v_raw:=v_item->'rawPayload';
    v_fingerprint:=nullif(v_item->>'sourceFingerprint','');
    if v_key is null or char_length(v_key)>300 or jsonb_typeof(v_raw)<>'object' then raise exception using errcode='22023',message='invalid raw source item'; end if;
    if v_fingerprint is not null and v_fingerprint !~ '^[0-9a-f]{64}$' then raise exception using errcode='22023',message='invalid source fingerprint'; end if;
    insert into dastak_v1.catalogue_import_items(batch_id,source_key,source_fingerprint,raw_payload,status,issues)
    values(p_batch_id,v_key,v_fingerprint,v_raw,'RAW','[]'::jsonb)
    on conflict (batch_id,source_key) do update
    set source_fingerprint=excluded.source_fingerprint,raw_payload=excluded.raw_payload,
        updated_at=clock_timestamp(),version=dastak_v1.catalogue_import_items.version+1
    returning (xmax=0)::int into v_inserted;
    if v_inserted=0 then v_updated:=v_updated+1; end if;
  end loop;
  update dastak_v1.catalogue_import_batches b set
    counts=jsonb_build_object(
      'rawItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id),
      'normalizedItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.normalized_payload is not null),
      'readyItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.status='READY'),
      'importedItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.status='IMPORTED')
    ),updated_at=clock_timestamp(),version=b.version+1
  where b.id=p_batch_id;
  return jsonb_build_object('batchId',p_batch_id,'totalItems',(select count(*) from dastak_v1.catalogue_import_items where batch_id=p_batch_id),'updatedItems',v_updated);
end $$;

create or replace function public.dastak_v1_ensure_catalogue_source_crawl_batch(p_job_id uuid,p_worker_id text)
returns uuid language sql security definer set search_path='' as $$select dastak_v1_api.ensure_catalogue_source_crawl_batch(p_job_id,p_worker_id);$$;
create or replace function public.dastak_v1_ingest_catalogue_source_raw_items(p_batch_id uuid,p_items jsonb)
returns jsonb language sql security definer set search_path='' as $$select dastak_v1_api.ingest_catalogue_source_raw_items(p_batch_id,p_items);$$;
revoke all on function public.dastak_v1_ensure_catalogue_source_crawl_batch(uuid,text) from public,anon,authenticated;
revoke all on function public.dastak_v1_ingest_catalogue_source_raw_items(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.dastak_v1_ensure_catalogue_source_crawl_batch(uuid,text) to service_role;
grant execute on function public.dastak_v1_ingest_catalogue_source_raw_items(uuid,jsonb) to service_role;;
