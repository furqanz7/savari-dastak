-- The catalogue Edge Function calls these trusted wrappers with the service
-- client so it can write the governed object bytes. Preserve the authenticated
-- merchant actor for the authorization checks inside the API functions.
create or replace function public.dastak_v1_prepare_governed_media(
  p_actor_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_expected_media_version bigint,
  p_mime_type text,
  p_byte_size bigint,
  p_source_reference text,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  return dastak_v1_api.prepare_governed_media_upload(
    p_actor_id,
    p_entity_type,
    p_entity_id,
    p_expected_media_version,
    p_mime_type,
    p_byte_size,
    p_source_reference,
    p_reason,
    p_idempotency_key
  );
end;
$$;

create or replace function public.dastak_v1_finalize_governed_media(
  p_actor_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_asset_id uuid,
  p_expected_media_version bigint,
  p_checksum_sha256 text,
  p_mime_type text,
  p_byte_size bigint,
  p_width_pixels integer,
  p_height_pixels integer,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  return dastak_v1_api.finalize_governed_media_upload(
    p_actor_id,
    p_entity_type,
    p_entity_id,
    p_asset_id,
    p_expected_media_version,
    p_checksum_sha256,
    p_mime_type,
    p_byte_size,
    p_width_pixels,
    p_height_pixels,
    p_reason,
    p_idempotency_key
  );
end;
$$;
