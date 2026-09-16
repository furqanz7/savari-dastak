-- Menu item rows have a versioned-row trigger. Finalizing governed dish media
-- must advance both the media version and the menu item version in one update.
create or replace function dastak_v1_api.finalize_governed_media_upload(
  p_actor uuid,
  p_type text,
  p_id uuid,
  p_asset uuid,
  p_expected bigint,
  p_checksum text,
  p_mime text,
  p_bytes bigint,
  p_width integer,
  p_height integer,
  p_reason text,
  p_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_entity jsonb;
  v_media dastak_v1.governed_entity_media%rowtype;
  v_previous uuid;
  v_hash bytea;
  v_old dastak_v1.idempotency_records%rowtype;
  v_result jsonb;
begin
  if p_checksum !~ '^[0-9a-f]{64}$'
     or p_width not between 1 and 12000
     or p_height not between 1 and 12000
     or char_length(trim(coalesce(p_reason, ''))) not between 3 and 500 then
    raise exception using errcode = '22023', message = 'valid governed media finalization required';
  end if;
  v_hash := dastak_v1_api.request_hash(jsonb_build_object(
    'type', p_type, 'id', p_id, 'asset', p_asset, 'expected', p_expected,
    'checksum', p_checksum, 'mime', p_mime, 'bytes', p_bytes,
    'width', p_width, 'height', p_height, 'reason', trim(p_reason)
  ));
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text || ':finalizeGovernedMedia:' || trim(p_key), 0));
  select * into v_old from dastak_v1.idempotency_records
    where actor_id = p_actor and command_name = 'finalizeGovernedMedia' and idempotency_key = trim(p_key);
  if found then
    if v_old.request_hash = v_hash then return v_old.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('dastak:governed-media:' || p_type || ':' || p_id, 0));
  v_entity := dastak_v1_api.assert_governed_media_actor(p_actor, p_type, p_id);
  if (v_entity ->> 'mediaVersion')::bigint <> p_expected then
    raise exception using errcode = '40001', message = 'stale governed media version';
  end if;
  select * into v_media from dastak_v1.governed_entity_media
    where id = p_asset and entity_type = p_type and entity_id = p_id and status = 'PENDING_UPLOAD' for update;
  if not found then raise exception using errcode = 'P0002', message = 'governed media asset not found for entity'; end if;
  if v_media.mime_type <> p_mime or v_media.byte_size <> p_bytes then
    raise exception using errcode = '22023', message = 'stored media does not match prepared intent';
  end if;
  select id into v_previous from dastak_v1.governed_entity_media
    where entity_type = p_type and entity_id = p_id and status = 'ACTIVE' for update;
  update dastak_v1.governed_entity_media set status = 'REPLACED', version = version + 1 where id = v_previous;
  update dastak_v1.governed_entity_media
    set status = 'ACTIVE', checksum_sha256 = p_checksum, width_pixels = p_width,
        height_pixels = p_height, finalized_at = now(), version = version + 1
    where id = p_asset returning * into v_media;
  if p_type = 'CATEGORY_TYPE' then
    update dastak_v1.category_types set image_key = v_media.image_key, media_version = media_version + 1, updated_at = now() where id = p_id;
  elsif p_type = 'CATEGORY' then
    update dastak_v1.categories set image_key = v_media.image_key, media_version = media_version + 1, updated_at = now() where id = p_id;
  elsif p_type = 'SUBCATEGORY' then
    update dastak_v1.subcategories set image_key = v_media.image_key, media_version = media_version + 1, updated_at = now() where id = p_id;
  elsif p_type = 'RESTAURANT_BRANCH_BANNER' then
    update dastak_v1.merchant_branches set banner_image_key = v_media.image_key, media_version = media_version + 1, updated_at = now() where id = p_id;
  else
    update dastak_v1.restaurant_menu_items
      set image_key = v_media.image_key, media_version = media_version + 1,
          version = version + 1, updated_at = now()
      where id = p_id;
  end if;
  insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
    values (p_actor, 'GOVERNED_MEDIA_REPLACED', lower(p_type), p_id,
      jsonb_build_object('assetId', p_asset, 'previousAssetId', v_previous,
        'entityType', p_type, 'fromVersion', p_expected, 'version', p_expected + 1,
        'reason', trim(p_reason)));
  v_result := jsonb_build_object('entityType', p_type, 'entityId', p_id,
    'assetId', p_asset, 'imageKey', v_media.image_key, 'mediaVersion', p_expected + 1);
  insert into dastak_v1.idempotency_records(actor_id, command_name, idempotency_key,
    request_hash, response_body, response_status, resource_id)
    values (p_actor, 'finalizeGovernedMedia', trim(p_key), v_hash, v_result, 200, p_id);
  perform private.send_admin_change(array['catalogue', 'auditHistory'], p_id);
  return v_result;
end;
$$;
