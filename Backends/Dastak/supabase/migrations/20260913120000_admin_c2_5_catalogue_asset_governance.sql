-- Admin C2.5: governed, SKU-bound catalogue assets. Storage bytes continue to
-- move through the existing dastak-catalogue bucket and Edge service boundary;
-- Postgres remains authoritative for association, primary state and audit.

alter table dastak_v1.skus
  add column if not exists asset_version bigint not null default 1
    check (asset_version > 0);

create index if not exists sku_images_sku_version_idx
  on dastak_v1.sku_images(sku_id, version, id);

create or replace function dastak_v1_api.assert_catalogue_asset_governor(
  p_actor_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_actor_id is null
    or not dastak_v1_api.actor_has_platform_permission(
      p_actor_id, 'platform.catalogue.assets.manage'
    ) then
    raise exception using errcode = '42501', message = 'platform permission required';
  end if;
end;
$$;

revoke all on function dastak_v1_api.assert_catalogue_asset_governor(uuid)
  from public, anon, authenticated;
grant execute on function dastak_v1_api.assert_catalogue_asset_governor(uuid)
  to service_role;

create or replace function dastak_v1_api.catalogue_asset_json(
  p_asset dastak_v1.sku_images
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', p_asset.id,
    'skuId', p_asset.sku_id,
    'imageKey', p_asset.image_key,
    'role', p_asset.role,
    'sortOrder', p_asset.sort_order,
    'sourceType', p_asset.source_type,
    'hasSourceReference', p_asset.source_reference is not null,
    'checksumSha256', p_asset.checksum_sha256,
    'widthPixels', p_asset.width_pixels,
    'heightPixels', p_asset.height_pixels,
    'mimeType', p_asset.mime_type,
    'status', p_asset.status,
    'rightsStatus', p_asset.rights_status,
    'version', p_asset.version,
    'createdAt', p_asset.created_at,
    'verifiedAt', p_asset.verified_at,
    'storageManaged', p_asset.image_key ~ '^canonical/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$',
    'canRemove', p_asset.role <> 'PRIMARY'
      and p_asset.image_key ~ '^canonical/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$'
  )
$$;

revoke all on function dastak_v1_api.catalogue_asset_json(dastak_v1.sku_images)
  from public, anon, authenticated, service_role;

create or replace function dastak_v1_api.admin_catalogue_sku_assets(
  p_actor_id uuid,
  p_sku_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sku dastak_v1.skus%rowtype;
  v_assets jsonb;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor_id);
  perform dastak_v1_api.assert_platform_permission(
    p_actor_id, 'platform.catalogue.assets.manage'
  );
  if p_sku_id is null then
    raise exception using errcode = '22023', message = 'catalogue SKU is required';
  end if;

  select sku.* into v_sku
  from dastak_v1.skus sku
  where sku.id = p_sku_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'catalogue SKU not found';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      dastak_v1_api.catalogue_asset_json(asset)
      order by case asset.role when 'PRIMARY' then 0 else 1 end,
               asset.sort_order, asset.created_at, asset.id
    ),
    '[]'::jsonb
  ) into v_assets
  from dastak_v1.sku_images asset
  where asset.sku_id = p_sku_id;

  return pg_catalog.jsonb_build_object(
    'sku', pg_catalog.jsonb_build_object(
      'id', v_sku.id,
      'name', v_sku.canonical_name,
      'variant', v_sku.variant_name,
      'packSize', v_sku.pack_size,
      'slug', v_sku.slug,
      'status', v_sku.status,
      'assetVersion', v_sku.asset_version
    ),
    'assets', v_assets
  );
end;
$$;

create or replace function dastak_v1_api.prepare_catalogue_asset_upload(
  p_actor_id uuid,
  p_sku_id uuid,
  p_expected_asset_version bigint,
  p_mime_type text,
  p_byte_size bigint,
  p_source_type text,
  p_source_reference text,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'prepareCatalogueAssetUpload';
  v_sku dastak_v1.skus%rowtype;
  v_asset dastak_v1.sku_images%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
  v_extension text;
  v_sort_order integer;
begin
  perform dastak_v1_api.assert_catalogue_asset_governor(p_actor_id);
  if p_sku_id is null
    or p_expected_asset_version is null or p_expected_asset_version < 1
    or p_mime_type not in ('image/jpeg', 'image/png', 'image/webp')
    or p_byte_size is null or p_byte_size < 1 or p_byte_size > 5242880
    or p_source_type not in (
      'MANUFACTURER', 'BRAND', 'AUTHORIZED_RETAILER', 'DISTRIBUTOR',
      'OWNER_CAPTURE', 'COMMODITY_STOCK', 'OTHER'
    )
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_source_reference, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid catalogue asset upload intent required';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'skuId', p_sku_id,
    'expectedAssetVersion', p_expected_asset_version,
    'mimeType', p_mime_type,
    'byteSize', p_byte_size,
    'sourceType', p_source_type,
    'sourceReference', pg_catalog.btrim(p_source_reference),
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key), 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak:catalogue-asset-sku:' || p_sku_id::text, 0
  ));
  select sku.* into v_sku
  from dastak_v1.skus sku
  where sku.id = p_sku_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'catalogue SKU not found';
  end if;
  if v_sku.asset_version <> p_expected_asset_version then
    raise exception using errcode = '40001', message = 'stale catalogue asset version';
  end if;

  v_extension := case p_mime_type
    when 'image/png' then 'png'
    when 'image/webp' then 'webp'
    else 'jpg'
  end;
  select least(coalesce(pg_catalog.max(asset.sort_order), -1) + 1, 1000)
  into v_sort_order
  from dastak_v1.sku_images asset
  where asset.sku_id = p_sku_id and asset.role = 'GALLERY';

  v_asset.id := extensions.gen_random_uuid();
  insert into dastak_v1.sku_images(
    id, sku_id, image_key, role, sort_order, source_type,
    source_reference, mime_type, status, rights_status, created_by
  ) values (
    v_asset.id,
    p_sku_id,
    'canonical/admin/' || p_sku_id::text || '/' || v_asset.id::text || '.' || v_extension,
    'GALLERY', v_sort_order, p_source_type,
    pg_catalog.btrim(p_source_reference), p_mime_type, 'PENDING', 'UNKNOWN', p_actor_id
  ) returning * into v_asset;

  update dastak_v1.skus sku
  set asset_version = sku.asset_version + 1,
      updated_at = pg_catalog.now()
  where sku.id = p_sku_id
  returning sku.* into v_sku;

  insert into dastak_v1.audit_events(
    actor_id, action, resource_type, resource_id, metadata
  ) values (
    p_actor_id, 'CATALOGUE_ASSET_UPLOAD_PREPARED', 'catalogue_sku', p_sku_id,
    pg_catalog.jsonb_build_object(
      'skuId', p_sku_id,
      'assetId', v_asset.id,
      'reason', pg_catalog.btrim(p_reason),
      'fromStatus', 'NOT_REGISTERED',
      'toStatus', 'PENDING',
      'scope', p_source_type,
      'outcome', 'Prepared governed asset ' || v_asset.id::text,
      'fromVersion', p_expected_asset_version,
      'version', v_sku.asset_version
    )
  );

  v_response := pg_catalog.jsonb_build_object(
    'skuId', p_sku_id,
    'assetId', v_asset.id,
    'imageKey', v_asset.image_key,
    'mimeType', v_asset.mime_type,
    'byteSize', p_byte_size,
    'assetVersion', v_sku.asset_version
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_sku_id
  );
  perform private.send_admin_change(array['catalogue', 'auditHistory'], p_sku_id);
  return v_response;
end;
$$;

create or replace function dastak_v1_api.finalize_catalogue_asset_upload(
  p_actor_id uuid,
  p_sku_id uuid,
  p_asset_id uuid,
  p_expected_asset_version bigint,
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
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'finalizeCatalogueAssetUpload';
  v_sku dastak_v1.skus%rowtype;
  v_asset dastak_v1.sku_images%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_catalogue_asset_governor(p_actor_id);
  if p_sku_id is null or p_asset_id is null
    or p_expected_asset_version is null or p_expected_asset_version < 1
    or p_checksum_sha256 !~ '^[0-9a-f]{64}$'
    or p_mime_type not in ('image/jpeg', 'image/png', 'image/webp')
    or p_byte_size is null or p_byte_size < 1 or p_byte_size > 5242880
    or p_width_pixels is null or p_width_pixels not between 1 and 20000
    or p_height_pixels is null or p_height_pixels not between 1 and 20000
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'verified catalogue asset metadata required';
  end if;

  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'skuId', p_sku_id, 'assetId', p_asset_id,
    'expectedAssetVersion', p_expected_asset_version,
    'checksumSha256', p_checksum_sha256, 'mimeType', p_mime_type,
    'byteSize', p_byte_size, 'widthPixels', p_width_pixels,
    'heightPixels', p_height_pixels, 'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key), 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak:catalogue-asset-sku:' || p_sku_id::text, 0
  ));
  select sku.* into v_sku
  from dastak_v1.skus sku where sku.id = p_sku_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'catalogue SKU not found'; end if;
  -- Finalization is the second half of one prepared upload, not a new Admin
  -- choice. Other gallery work may legitimately advance the SKU asset version
  -- while Storage is being written; the exact pending asset remains the lock.
  if v_sku.asset_version < p_expected_asset_version then
    raise exception using errcode = '40001', message = 'stale catalogue asset version';
  end if;
  select asset.* into v_asset
  from dastak_v1.sku_images asset
  where asset.id = p_asset_id and asset.sku_id = p_sku_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'catalogue asset not found for SKU'; end if;
  if v_asset.status <> 'PENDING' or v_asset.rights_status <> 'UNKNOWN'
    or v_asset.mime_type <> p_mime_type
    or v_asset.image_key !~ ('^canonical/admin/' || p_sku_id::text || '/' || p_asset_id::text || '\.(jpg|png|webp)$') then
    raise exception using errcode = '55000', message = 'catalogue asset cannot be finalized';
  end if;

  update dastak_v1.sku_images asset
  set checksum_sha256 = p_checksum_sha256,
      width_pixels = p_width_pixels,
      height_pixels = p_height_pixels,
      mime_type = p_mime_type,
      status = 'VERIFIED',
      verified_by = p_actor_id,
      verified_at = pg_catalog.now(),
      rights_status = 'CLEARED',
      rights_reference = v_asset.source_reference,
      rights_verified_by = p_actor_id,
      rights_verified_at = pg_catalog.now(),
      version = asset.version + 1
  where asset.id = p_asset_id and asset.sku_id = p_sku_id
  returning * into v_asset;

  update dastak_v1.skus sku
  set asset_version = sku.asset_version + 1,
      updated_at = pg_catalog.now()
  where sku.id = p_sku_id
  returning sku.* into v_sku;

  insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
  values (
    p_actor_id, 'CATALOGUE_ASSET_ADDED', 'catalogue_sku', p_sku_id,
    pg_catalog.jsonb_build_object(
      'skuId', p_sku_id, 'assetId', p_asset_id,
      'reason', pg_catalog.btrim(p_reason),
      'fromStatus', 'PENDING', 'toStatus', 'VERIFIED',
      'scope', v_asset.source_type,
      'outcome', 'Verified governed asset ' || p_asset_id::text,
      'fromVersion', p_expected_asset_version,
      'version', v_sku.asset_version
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'skuId', p_sku_id,
    'assetVersion', v_sku.asset_version,
    'asset', dastak_v1_api.catalogue_asset_json(v_asset)
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_sku_id
  );
  perform private.send_admin_change(array['catalogue', 'auditHistory'], p_sku_id);
  return v_response;
end;
$$;

-- The existing live-SKU guard is retained. A transaction-local marker permits
-- only the governed function to perform the demote/promote pair; the function
-- then proves the final single, verified, rights-cleared primary before commit.
create or replace function dastak_v1.guard_active_sku_primary_image_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_active boolean := false;
  v_old_qualifying boolean := false;
  v_new_qualifying boolean := false;
  v_other_exists boolean := false;
  v_governed_swap boolean := false;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    v_governed_swap := pg_catalog.current_setting(
      'dastak.catalogue_asset_primary_swap_sku', true
    ) = old.sku_id::text;
    if v_governed_swap then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;

    select exists(
      select 1 from dastak_v1.skus sku
      where sku.id = old.sku_id and sku.status = 'ACTIVE'
    ) into v_old_active;
    v_old_qualifying := old.role = 'PRIMARY'
      and old.status = 'VERIFIED' and old.rights_status = 'CLEARED';
    if tg_op = 'UPDATE' then
      v_new_qualifying := new.sku_id = old.sku_id
        and new.role = 'PRIMARY'
        and new.status = 'VERIFIED'
        and new.rights_status = 'CLEARED';
    end if;
    if v_old_active and v_old_qualifying and not v_new_qualifying then
      select exists(
        select 1 from dastak_v1.sku_images asset
        where asset.sku_id = old.sku_id and asset.id <> old.id
          and asset.role = 'PRIMARY' and asset.status = 'VERIFIED'
          and asset.rights_status = 'CLEARED'
      ) into v_other_exists;
      if not v_other_exists then
        raise exception using errcode = '23514',
          message = 'active SKU cannot lose its last verified primary image with cleared usage rights';
      end if;
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function dastak_v1_api.promote_catalogue_primary_asset(
  p_actor_id uuid,
  p_sku_id uuid,
  p_asset_id uuid,
  p_expected_primary_asset_id uuid,
  p_expected_asset_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'promoteCataloguePrimaryAsset';
  v_sku dastak_v1.skus%rowtype;
  v_target dastak_v1.sku_images%rowtype;
  v_current dastak_v1.sku_images%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
  v_primary_count bigint;
begin
  perform dastak_v1_api.assert_catalogue_asset_governor(p_actor_id);
  if p_sku_id is null or p_asset_id is null
    or p_expected_asset_version is null or p_expected_asset_version < 1
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid primary-image governance command required';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'skuId', p_sku_id, 'assetId', p_asset_id,
    'expectedPrimaryAssetId', p_expected_primary_asset_id,
    'expectedAssetVersion', p_expected_asset_version,
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key), 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak:catalogue-asset-sku:' || p_sku_id::text, 0
  ));
  select sku.* into v_sku
  from dastak_v1.skus sku where sku.id = p_sku_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'catalogue SKU not found'; end if;
  if v_sku.asset_version <> p_expected_asset_version then
    raise exception using errcode = '40001', message = 'stale catalogue asset version';
  end if;
  select asset.* into v_target
  from dastak_v1.sku_images asset
  where asset.id = p_asset_id and asset.sku_id = p_sku_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'catalogue asset not found for SKU'; end if;
  if v_target.status <> 'VERIFIED' or v_target.rights_status <> 'CLEARED'
    or v_target.checksum_sha256 is null or v_target.mime_type is null
    or v_target.image_key !~ '^canonical/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$' then
    raise exception using errcode = '55000', message = 'catalogue asset is not eligible to become primary';
  end if;
  select asset.* into v_current
  from dastak_v1.sku_images asset
  where asset.sku_id = p_sku_id and asset.role = 'PRIMARY'
  for update;
  if found then
    if v_current.id is distinct from p_expected_primary_asset_id then
      raise exception using errcode = '40001', message = 'stale catalogue primary image';
    end if;
    if v_current.id = p_asset_id then
      raise exception using errcode = '55000', message = 'catalogue asset is already primary';
    end if;
  elsif p_expected_primary_asset_id is not null then
    raise exception using errcode = '40001', message = 'stale catalogue primary image';
  end if;

  perform pg_catalog.set_config(
    'dastak.catalogue_asset_primary_swap_sku', p_sku_id::text, true
  );
  if v_current.id is not null then
    update dastak_v1.sku_images asset
    set role = 'GALLERY',
        sort_order = least(coalesce((
          select pg_catalog.max(other.sort_order) + 1
          from dastak_v1.sku_images other
          where other.sku_id = p_sku_id and other.role = 'GALLERY'
        ), 0), 1000),
        version = asset.version + 1
    where asset.id = v_current.id;
  end if;
  update dastak_v1.sku_images asset
  set role = 'PRIMARY', sort_order = 0, version = asset.version + 1
  where asset.id = p_asset_id and asset.sku_id = p_sku_id
  returning * into v_target;
  perform pg_catalog.set_config('dastak.catalogue_asset_primary_swap_sku', '', true);

  select pg_catalog.count(*) into v_primary_count
  from dastak_v1.sku_images asset
  where asset.sku_id = p_sku_id and asset.role = 'PRIMARY'
    and asset.status = 'VERIFIED' and asset.rights_status = 'CLEARED';
  if v_primary_count <> 1 or v_target.role <> 'PRIMARY' then
    raise exception using errcode = '23514', message = 'catalogue SKU must retain exactly one valid primary image';
  end if;

  update dastak_v1.skus sku
  set asset_version = sku.asset_version + 1,
      updated_at = pg_catalog.now()
  where sku.id = p_sku_id
  returning sku.* into v_sku;
  insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
  values (
    p_actor_id,
    case when v_current.id is null
      then 'CATALOGUE_PRIMARY_IMAGE_PROMOTED'
      else 'CATALOGUE_PRIMARY_IMAGE_REPLACED' end,
    'catalogue_sku', p_sku_id,
    pg_catalog.jsonb_build_object(
      'skuId', p_sku_id,
      'fromAssetId', v_current.id,
      'toAssetId', p_asset_id,
      'reason', pg_catalog.btrim(p_reason),
      'fromStatus', case when v_current.id is null then 'NO_PRIMARY' else 'PRIMARY' end,
      'toStatus', 'PRIMARY',
      'scope', 'PRIMARY_IMAGE',
      'outcome', case when v_current.id is null
        then 'Promoted governed primary asset ' || p_asset_id::text
        else 'Replaced primary asset ' || v_current.id::text || ' with ' || p_asset_id::text end,
      'fromVersion', p_expected_asset_version,
      'version', v_sku.asset_version
    )
  );
  v_response := pg_catalog.jsonb_build_object(
    'skuId', p_sku_id,
    'assetVersion', v_sku.asset_version,
    'primaryAssetId', p_asset_id,
    'previousPrimaryAssetId', v_current.id,
    'asset', dastak_v1_api.catalogue_asset_json(v_target)
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_sku_id
  );
  perform private.send_admin_change(array['catalogue', 'auditHistory'], p_sku_id);
  return v_response;
end;
$$;

create or replace function dastak_v1_api.remove_catalogue_asset(
  p_actor_id uuid,
  p_sku_id uuid,
  p_asset_id uuid,
  p_expected_asset_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_command constant text := 'removeCatalogueAsset';
  v_sku dastak_v1.skus%rowtype;
  v_asset dastak_v1.sku_images%rowtype;
  v_existing dastak_v1.idempotency_records%rowtype;
  v_hash bytea;
  v_response jsonb;
begin
  perform dastak_v1_api.assert_catalogue_asset_governor(p_actor_id);
  if p_sku_id is null or p_asset_id is null
    or p_expected_asset_version is null or p_expected_asset_version < 1
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_reason, ''))) not between 3 and 500
    or pg_catalog.char_length(pg_catalog.btrim(coalesce(p_idempotency_key, ''))) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'valid catalogue asset removal required';
  end if;
  v_hash := dastak_v1_api.request_hash(pg_catalog.jsonb_build_object(
    'skuId', p_sku_id, 'assetId', p_asset_id,
    'expectedAssetVersion', p_expected_asset_version,
    'reason', pg_catalog.btrim(p_reason)
  ));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_actor_id::text || ':' || v_command || ':' || pg_catalog.btrim(p_idempotency_key), 0
  ));
  select record.* into v_existing
  from dastak_v1.idempotency_records record
  where record.actor_id = p_actor_id
    and record.command_name = v_command
    and record.idempotency_key = pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash = v_hash then return v_existing.response_body; end if;
    raise exception using errcode = '22023', message = 'idempotency key was already used with a different request';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'dastak:catalogue-asset-sku:' || p_sku_id::text, 0
  ));
  select sku.* into v_sku
  from dastak_v1.skus sku where sku.id = p_sku_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'catalogue SKU not found'; end if;
  if v_sku.asset_version <> p_expected_asset_version then
    raise exception using errcode = '40001', message = 'stale catalogue asset version';
  end if;
  select asset.* into v_asset
  from dastak_v1.sku_images asset
  where asset.id = p_asset_id and asset.sku_id = p_sku_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'catalogue asset not found for SKU'; end if;
  if v_asset.role = 'PRIMARY' then
    raise exception using errcode = '55000', message = 'CATALOGUE_PRIMARY_ASSET_REQUIRES_REPLACEMENT';
  end if;
  if v_asset.image_key !~ '^canonical/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$' then
    raise exception using errcode = '55000', message = 'CATALOGUE_ASSET_STORAGE_PATH_NOT_GOVERNED';
  end if;

  delete from dastak_v1.sku_images asset
  where asset.id = p_asset_id and asset.sku_id = p_sku_id;
  update dastak_v1.skus sku
  set asset_version = sku.asset_version + 1,
      updated_at = pg_catalog.now()
  where sku.id = p_sku_id
  returning sku.* into v_sku;
  insert into dastak_v1.audit_events(actor_id, action, resource_type, resource_id, metadata)
  values (
    p_actor_id, 'CATALOGUE_ASSET_REMOVED', 'catalogue_sku', p_sku_id,
    pg_catalog.jsonb_build_object(
      'skuId', p_sku_id, 'assetId', p_asset_id,
      'reason', pg_catalog.btrim(p_reason),
      'fromStatus', v_asset.status, 'toStatus', 'REMOVED',
      'scope', v_asset.role,
      'outcome', 'Removed unused governed asset ' || p_asset_id::text,
      'fromVersion', p_expected_asset_version,
      'version', v_sku.asset_version
    )
  );
  -- The path is returned only to the service-role Edge boundary. It remains in
  -- the idempotent response so an uncertain Storage deletion can be retried.
  v_response := pg_catalog.jsonb_build_object(
    'skuId', p_sku_id,
    'assetId', p_asset_id,
    'assetVersion', v_sku.asset_version,
    'storageObjectPath', v_asset.image_key
  );
  insert into dastak_v1.idempotency_records(
    actor_id, command_name, idempotency_key, request_hash,
    response_body, response_status, resource_id
  ) values (
    p_actor_id, v_command, pg_catalog.btrim(p_idempotency_key), v_hash,
    v_response, 200, p_sku_id
  );
  perform private.send_admin_change(array['catalogue', 'auditHistory'], p_sku_id);
  return v_response;
end;
$$;

create or replace function public.dastak_v1_admin_catalogue_sku_assets(
  p_sku_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select dastak_v1_api.admin_catalogue_sku_assets(auth.uid(), p_sku_id)
$$;

create or replace function public.dastak_v1_admin_prepare_catalogue_asset(
  p_actor_id uuid,
  p_sku_id uuid,
  p_expected_asset_version bigint,
  p_mime_type text,
  p_byte_size bigint,
  p_source_type text,
  p_source_reference text,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.prepare_catalogue_asset_upload(
    p_actor_id, p_sku_id, p_expected_asset_version, p_mime_type,
    p_byte_size, p_source_type, p_source_reference, p_reason, p_idempotency_key
  )
$$;

create or replace function public.dastak_v1_admin_finalize_catalogue_asset(
  p_actor_id uuid,
  p_sku_id uuid,
  p_asset_id uuid,
  p_expected_asset_version bigint,
  p_checksum_sha256 text,
  p_mime_type text,
  p_byte_size bigint,
  p_width_pixels integer,
  p_height_pixels integer,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.finalize_catalogue_asset_upload(
    p_actor_id, p_sku_id, p_asset_id, p_expected_asset_version,
    p_checksum_sha256, p_mime_type, p_byte_size, p_width_pixels,
    p_height_pixels, p_reason, p_idempotency_key
  )
$$;

create or replace function public.dastak_v1_admin_promote_catalogue_primary_asset(
  p_actor_id uuid,
  p_sku_id uuid,
  p_asset_id uuid,
  p_expected_primary_asset_id uuid,
  p_expected_asset_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.promote_catalogue_primary_asset(
    p_actor_id, p_sku_id, p_asset_id, p_expected_primary_asset_id,
    p_expected_asset_version, p_reason, p_idempotency_key
  )
$$;

create or replace function public.dastak_v1_admin_remove_catalogue_asset(
  p_actor_id uuid,
  p_sku_id uuid,
  p_asset_id uuid,
  p_expected_asset_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select dastak_v1_api.remove_catalogue_asset(
    p_actor_id, p_sku_id, p_asset_id, p_expected_asset_version,
    p_reason, p_idempotency_key
  )
$$;

revoke all on function dastak_v1_api.admin_catalogue_sku_assets(uuid,uuid)
  from public, anon;
grant execute on function dastak_v1_api.admin_catalogue_sku_assets(uuid,uuid)
  to authenticated, service_role;
revoke all on function public.dastak_v1_admin_catalogue_sku_assets(uuid)
  from public, anon;
grant execute on function public.dastak_v1_admin_catalogue_sku_assets(uuid)
  to authenticated, service_role;

revoke all on function dastak_v1_api.prepare_catalogue_asset_upload(uuid,uuid,bigint,text,bigint,text,text,text,text)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.finalize_catalogue_asset_upload(uuid,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.promote_catalogue_primary_asset(uuid,uuid,uuid,uuid,bigint,text,text)
  from public, anon, authenticated;
revoke all on function dastak_v1_api.remove_catalogue_asset(uuid,uuid,uuid,bigint,text,text)
  from public, anon, authenticated;
grant execute on function dastak_v1_api.prepare_catalogue_asset_upload(uuid,uuid,bigint,text,bigint,text,text,text,text)
  to service_role;
grant execute on function dastak_v1_api.finalize_catalogue_asset_upload(uuid,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text)
  to service_role;
grant execute on function dastak_v1_api.promote_catalogue_primary_asset(uuid,uuid,uuid,uuid,bigint,text,text)
  to service_role;
grant execute on function dastak_v1_api.remove_catalogue_asset(uuid,uuid,uuid,bigint,text,text)
  to service_role;

revoke all on function public.dastak_v1_admin_prepare_catalogue_asset(uuid,uuid,bigint,text,bigint,text,text,text,text)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_admin_finalize_catalogue_asset(uuid,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_admin_promote_catalogue_primary_asset(uuid,uuid,uuid,uuid,bigint,text,text)
  from public, anon, authenticated;
revoke all on function public.dastak_v1_admin_remove_catalogue_asset(uuid,uuid,uuid,bigint,text,text)
  from public, anon, authenticated;
grant execute on function public.dastak_v1_admin_prepare_catalogue_asset(uuid,uuid,bigint,text,bigint,text,text,text,text)
  to service_role;
grant execute on function public.dastak_v1_admin_finalize_catalogue_asset(uuid,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text)
  to service_role;
grant execute on function public.dastak_v1_admin_promote_catalogue_primary_asset(uuid,uuid,uuid,uuid,bigint,text,text)
  to service_role;
grant execute on function public.dastak_v1_admin_remove_catalogue_asset(uuid,uuid,uuid,bigint,text,text)
  to service_role;

comment on function public.dastak_v1_admin_catalogue_sku_assets(uuid) is
  'Caller-bound exact-SKU catalogue asset governance projection.';
comment on function public.dastak_v1_admin_prepare_catalogue_asset(uuid,uuid,bigint,text,bigint,text,text,text,text) is
  'Service-bound preparation of a server-generated, exact-SKU catalogue object path.';
comment on function public.dastak_v1_admin_finalize_catalogue_asset(uuid,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text) is
  'Service-bound finalization after Edge verifies stored catalogue image bytes.';
comment on function public.dastak_v1_admin_promote_catalogue_primary_asset(uuid,uuid,uuid,uuid,bigint,text,text) is
  'Service-bound atomic primary-image replacement for one canonical SKU.';
comment on function public.dastak_v1_admin_remove_catalogue_asset(uuid,uuid,uuid,bigint,text,text) is
  'Service-bound removal of a non-primary canonical asset with replayable cleanup path.';
