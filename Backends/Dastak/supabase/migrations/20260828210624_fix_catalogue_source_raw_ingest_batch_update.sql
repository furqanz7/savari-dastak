create or replace function dastak_v1_api.ingest_catalogue_source_raw_items(p_batch_id uuid,p_items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inserted integer:=0;
declare v_updated integer:=0;
declare v_item jsonb;
declare v_key text;
declare v_raw jsonb;
declare v_fingerprint text;
declare v_was_insert boolean;
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

    v_was_insert:=not exists(select 1 from dastak_v1.catalogue_import_items where batch_id=p_batch_id and source_key=v_key);
    insert into dastak_v1.catalogue_import_items(batch_id,source_key,source_fingerprint,raw_payload,status,issues)
    values(p_batch_id,v_key,v_fingerprint,v_raw,'RAW','[]'::jsonb)
    on conflict (batch_id,source_key) do update
    set source_fingerprint=excluded.source_fingerprint,
        raw_payload=excluded.raw_payload,
        updated_at=clock_timestamp(),
        version=dastak_v1.catalogue_import_items.version+1;

    if v_was_insert then v_inserted:=v_inserted+1; else v_updated:=v_updated+1; end if;
  end loop;

  update dastak_v1.catalogue_import_batches b set
    counts=jsonb_build_object(
      'rawItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id),
      'normalizedItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.normalized_payload is not null),
      'readyItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.status='READY'),
      'importedItems',(select count(*) from dastak_v1.catalogue_import_items i where i.batch_id=b.id and i.status='IMPORTED')
    ),
    version=b.version+1
  where b.id=p_batch_id;

  return jsonb_build_object(
    'batchId',p_batch_id,
    'totalItems',(select count(*) from dastak_v1.catalogue_import_items where batch_id=p_batch_id),
    'insertedItems',v_inserted,
    'updatedItems',v_updated
  );
end $$;;
