-- Exact-entity media association for curated taxonomy art and restaurant media.
-- Storage bytes are written only by the existing service-role Edge boundary.
create table dastak_v1.governed_entity_media (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in (
    'CATEGORY_TYPE','CATEGORY','SUBCATEGORY','RESTAURANT_BRANCH_BANNER','RESTAURANT_MENU_ITEM'
  )),
  entity_id uuid not null,
  image_key text not null unique check (
    image_key ~ '^canonical/(taxonomy|restaurant)/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$'
  ),
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/webp')),
  byte_size bigint not null check (byte_size between 1 and 5242880),
  checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9a-f]{64}$'),
  width_pixels integer check (width_pixels is null or width_pixels between 1 and 12000),
  height_pixels integer check (height_pixels is null or height_pixels between 1 and 12000),
  status text not null default 'PENDING_UPLOAD' check (status in ('PENDING_UPLOAD','ACTIVE','REPLACED')),
  source_reference text not null check (char_length(trim(source_reference)) between 3 and 500),
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  created_by uuid not null references public.accounts(id),
  created_at timestamptz not null default now(), finalized_at timestamptz,
  version bigint not null default 1 check (version > 0)
);
create unique index governed_entity_media_active_uidx on dastak_v1.governed_entity_media(entity_type,entity_id) where status='ACTIVE';
create index governed_entity_media_entity_idx on dastak_v1.governed_entity_media(entity_type,entity_id,created_at desc);

alter table dastak_v1.category_types add column media_version bigint not null default 1 check(media_version>0);
alter table dastak_v1.categories add column media_version bigint not null default 1 check(media_version>0);
alter table dastak_v1.subcategories add column media_version bigint not null default 1 check(media_version>0);
alter table dastak_v1.merchant_branches add column banner_image_key text,
  add column media_version bigint not null default 1 check(media_version>0),
  add constraint merchant_branch_banner_path check(banner_image_key is null or banner_image_key ~ '^canonical/restaurant/[A-Za-z0-9/_-]+\.(jpg|jpeg|png|webp)$');
alter table dastak_v1.restaurant_menu_items add column media_version bigint not null default 1 check(media_version>0);

create function dastak_v1_api.assert_governed_media_actor(p_actor uuid,p_type text,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_name text; v_version bigint; v_image text; v_org uuid; v_branch uuid;
begin
  perform dastak_v1_api.assert_authenticated_actor(p_actor);
  if p_type='CATEGORY_TYPE' then
    perform dastak_v1_api.assert_platform_permission(p_actor,'platform.catalogue.assets.manage');
    select name,media_version,image_key into v_name,v_version,v_image from dastak_v1.category_types where id=p_id;
  elsif p_type='CATEGORY' then
    perform dastak_v1_api.assert_platform_permission(p_actor,'platform.catalogue.assets.manage');
    select name,media_version,image_key into v_name,v_version,v_image from dastak_v1.categories where id=p_id;
  elsif p_type='SUBCATEGORY' then
    perform dastak_v1_api.assert_platform_permission(p_actor,'platform.catalogue.assets.manage');
    select name,media_version,image_key into v_name,v_version,v_image from dastak_v1.subcategories where id=p_id;
  elsif p_type='RESTAURANT_BRANCH_BANNER' then
    select b.display_name,b.media_version,b.banner_image_key,b.organization_id,b.id into v_name,v_version,v_image,v_org,v_branch
      from dastak_v1.merchant_branches b join dastak_v1.merchant_organizations o on o.id=b.organization_id and o.merchant_type='RESTAURANT_CAFE' where b.id=p_id;
  elsif p_type='RESTAURANT_MENU_ITEM' then
    select i.name,i.media_version,i.image_key,i.organization_id,i.branch_id into v_name,v_version,v_image,v_org,v_branch from dastak_v1.restaurant_menu_items i where i.id=p_id;
  else raise exception using errcode='22023',message='invalid governed media entity'; end if;
  if v_name is null then raise exception using errcode='P0002',message='governed media entity not found'; end if;
  if v_org is not null and not dastak_v1_api.actor_has_wave1_merchant_permission(p_actor,v_org,'merchant.restaurant.menu.manage',v_branch) then raise exception using errcode='42501',message='permission denied'; end if;
  return jsonb_build_object('entityType',p_type,'entityId',p_id,'name',v_name,'mediaVersion',v_version,'imageKey',v_image,'branchId',v_branch);
end $$;

create function dastak_v1_api.prepare_governed_media_upload(p_actor uuid,p_type text,p_id uuid,p_expected bigint,p_mime text,p_bytes bigint,p_source text,p_reason text,p_key text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_entity jsonb; v_asset uuid:=gen_random_uuid(); v_ext text; v_path text; v_hash bytea; v_old dastak_v1.idempotency_records%rowtype; v_result jsonb;
begin
  if p_expected<1 or p_mime not in('image/jpeg','image/png','image/webp') or p_bytes not between 1 and 5242880 or char_length(trim(coalesce(p_source,''))) not between 3 and 500 or char_length(trim(coalesce(p_reason,''))) not between 3 and 500 or char_length(trim(coalesce(p_key,''))) not between 1 and 200 then raise exception using errcode='22023',message='valid governed media upload intent required'; end if;
  v_hash:=dastak_v1_api.request_hash(jsonb_build_object('type',p_type,'id',p_id,'expected',p_expected,'mime',p_mime,'bytes',p_bytes,'source',trim(p_source),'reason',trim(p_reason)));
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text||':governedMedia:'||trim(p_key),0));
  select * into v_old from dastak_v1.idempotency_records where actor_id=p_actor and command_name='prepareGovernedMedia' and idempotency_key=trim(p_key);
  if found then if v_old.request_hash=v_hash then return v_old.response_body; end if; raise exception using errcode='22023',message='idempotency key was already used with a different request'; end if;
  perform pg_advisory_xact_lock(hashtextextended('dastak:governed-media:'||p_type||':'||p_id,0));
  v_entity:=dastak_v1_api.assert_governed_media_actor(p_actor,p_type,p_id);
  if (v_entity->>'mediaVersion')::bigint<>p_expected then raise exception using errcode='40001',message='stale governed media version'; end if;
  v_ext:=case p_mime when'image/png'then'png'when'image/webp'then'webp'else'jpg'end;
  v_path:='canonical/'||case when p_type like'RESTAURANT_%'then'restaurant'else'taxonomy'end||'/'||lower(p_type)||'/'||p_id||'/'||v_asset||'.'||v_ext;
  insert into dastak_v1.governed_entity_media(id,entity_type,entity_id,image_key,mime_type,byte_size,source_reference,reason,created_by) values(v_asset,p_type,p_id,v_path,p_mime,p_bytes,trim(p_source),trim(p_reason),p_actor);
  v_result:=jsonb_build_object('assetId',v_asset,'imageKey',v_path,'mediaVersion',p_expected);
  insert into dastak_v1.idempotency_records(actor_id,command_name,idempotency_key,request_hash,response_body,response_status,resource_id) values(p_actor,'prepareGovernedMedia',trim(p_key),v_hash,v_result,200,p_id);
  return v_result;
end $$;

create function dastak_v1_api.finalize_governed_media_upload(p_actor uuid,p_type text,p_id uuid,p_asset uuid,p_expected bigint,p_checksum text,p_mime text,p_bytes bigint,p_width integer,p_height integer,p_reason text,p_key text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_entity jsonb; v_media dastak_v1.governed_entity_media%rowtype; v_previous uuid; v_hash bytea; v_old dastak_v1.idempotency_records%rowtype; v_result jsonb;
begin
  if p_checksum!~'^[0-9a-f]{64}$' or p_width not between 1 and 12000 or p_height not between 1 and 12000 or char_length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception using errcode='22023',message='valid governed media finalization required'; end if;
  v_hash:=dastak_v1_api.request_hash(jsonb_build_object('type',p_type,'id',p_id,'asset',p_asset,'expected',p_expected,'checksum',p_checksum,'mime',p_mime,'bytes',p_bytes,'width',p_width,'height',p_height,'reason',trim(p_reason)));
  perform pg_advisory_xact_lock(hashtextextended(p_actor::text||':finalizeGovernedMedia:'||trim(p_key),0));
  select * into v_old from dastak_v1.idempotency_records where actor_id=p_actor and command_name='finalizeGovernedMedia' and idempotency_key=trim(p_key); if found then if v_old.request_hash=v_hash then return v_old.response_body; end if; raise exception using errcode='22023',message='idempotency key was already used with a different request'; end if;
  perform pg_advisory_xact_lock(hashtextextended('dastak:governed-media:'||p_type||':'||p_id,0));
  v_entity:=dastak_v1_api.assert_governed_media_actor(p_actor,p_type,p_id); if(v_entity->>'mediaVersion')::bigint<>p_expected then raise exception using errcode='40001',message='stale governed media version'; end if;
  select * into v_media from dastak_v1.governed_entity_media where id=p_asset and entity_type=p_type and entity_id=p_id and status='PENDING_UPLOAD' for update; if not found then raise exception using errcode='P0002',message='governed media asset not found for entity'; end if;
  if v_media.mime_type<>p_mime or v_media.byte_size<>p_bytes then raise exception using errcode='22023',message='stored media does not match prepared intent'; end if;
  select id into v_previous from dastak_v1.governed_entity_media where entity_type=p_type and entity_id=p_id and status='ACTIVE' for update;
  update dastak_v1.governed_entity_media set status='REPLACED',version=version+1 where id=v_previous;
  update dastak_v1.governed_entity_media set status='ACTIVE',checksum_sha256=p_checksum,width_pixels=p_width,height_pixels=p_height,finalized_at=now(),version=version+1 where id=p_asset returning * into v_media;
  if p_type='CATEGORY_TYPE'then update dastak_v1.category_types set image_key=v_media.image_key,media_version=media_version+1,updated_at=now() where id=p_id;
  elsif p_type='CATEGORY'then update dastak_v1.categories set image_key=v_media.image_key,media_version=media_version+1,updated_at=now() where id=p_id;
  elsif p_type='SUBCATEGORY'then update dastak_v1.subcategories set image_key=v_media.image_key,media_version=media_version+1,updated_at=now() where id=p_id;
  elsif p_type='RESTAURANT_BRANCH_BANNER'then update dastak_v1.merchant_branches set banner_image_key=v_media.image_key,media_version=media_version+1,updated_at=now() where id=p_id;
  else update dastak_v1.restaurant_menu_items set image_key=v_media.image_key,media_version=media_version+1,updated_at=now() where id=p_id; end if;
  insert into dastak_v1.audit_events(actor_id,action,resource_type,resource_id,metadata) values(p_actor,'GOVERNED_MEDIA_REPLACED',lower(p_type),p_id,jsonb_build_object('assetId',p_asset,'previousAssetId',v_previous,'entityType',p_type,'fromVersion',p_expected,'version',p_expected+1,'reason',trim(p_reason)));
  v_result:=jsonb_build_object('entityType',p_type,'entityId',p_id,'assetId',p_asset,'imageKey',v_media.image_key,'mediaVersion',p_expected+1);
  insert into dastak_v1.idempotency_records(actor_id,command_name,idempotency_key,request_hash,response_body,response_status,resource_id) values(p_actor,'finalizeGovernedMedia',trim(p_key),v_hash,v_result,200,p_id);
  perform private.send_admin_change(array['catalogue','auditHistory'],p_id); return v_result;
end $$;

create function public.dastak_v1_prepare_governed_media(p_actor_id uuid,p_entity_type text,p_entity_id uuid,p_expected_media_version bigint,p_mime_type text,p_byte_size bigint,p_source_reference text,p_reason text,p_idempotency_key text)returns jsonb language sql security invoker set search_path=''as $$select dastak_v1_api.prepare_governed_media_upload(p_actor_id,p_entity_type,p_entity_id,p_expected_media_version,p_mime_type,p_byte_size,p_source_reference,p_reason,p_idempotency_key)$$;
create function public.dastak_v1_finalize_governed_media(p_actor_id uuid,p_entity_type text,p_entity_id uuid,p_asset_id uuid,p_expected_media_version bigint,p_checksum_sha256 text,p_mime_type text,p_byte_size bigint,p_width_pixels integer,p_height_pixels integer,p_reason text,p_idempotency_key text)returns jsonb language sql security invoker set search_path=''as $$select dastak_v1_api.finalize_governed_media_upload(p_actor_id,p_entity_type,p_entity_id,p_asset_id,p_expected_media_version,p_checksum_sha256,p_mime_type,p_byte_size,p_width_pixels,p_height_pixels,p_reason,p_idempotency_key)$$;

revoke all on table dastak_v1.governed_entity_media from public,anon,authenticated;
revoke all on function dastak_v1_api.assert_governed_media_actor(uuid,text,uuid),dastak_v1_api.prepare_governed_media_upload(uuid,text,uuid,bigint,text,bigint,text,text,text),dastak_v1_api.finalize_governed_media_upload(uuid,text,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text),public.dastak_v1_prepare_governed_media(uuid,text,uuid,bigint,text,bigint,text,text,text),public.dastak_v1_finalize_governed_media(uuid,text,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text) from public,anon,authenticated;
grant execute on function dastak_v1_api.assert_governed_media_actor(uuid,text,uuid),dastak_v1_api.prepare_governed_media_upload(uuid,text,uuid,bigint,text,bigint,text,text,text),dastak_v1_api.finalize_governed_media_upload(uuid,text,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text),public.dastak_v1_prepare_governed_media(uuid,text,uuid,bigint,text,bigint,text,text,text),public.dastak_v1_finalize_governed_media(uuid,text,uuid,uuid,bigint,text,text,bigint,integer,integer,text,text) to service_role;

-- The restaurant projection now uses a dedicated banner field, never address JSON.
create or replace function dastak_v1_api.restaurant_menu_json(p_branch_id uuid,p_include_inactive boolean default false)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('restaurant',jsonb_build_object('organizationId',o.id,'branchId',b.id,'name',o.display_name,'branchName',b.display_name,'imageKey',b.banner_image_key,'mediaVersion',b.media_version,'description',b.address_snapshot->>'description','serviceZoneId',b.service_zone_id,'acceptingOrders',coalesce(s.accepting_orders,false),'isOpen',coalesce(s.is_open,false),'operationalVersion',coalesce(s.version,0),'branchStatus',b.status,'merchantType',o.merchant_type,'softActiveOrderThreshold',(dastak_v1_api.effective_setting_json('restaurant.soft_active_order_threshold',b.id,o.id,b.service_zone_id)#>>'{}')::integer,'activeOrderCount',(select count(*)from dastak_v1.restaurant_capacity_commitments c where c.branch_id=b.id and c.status='COMMITTED')),
    'categories',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'description',c.description,'sortOrder',c.sort_order,'status',c.status,'version',c.version,'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'description',i.description,'imageKey',i.image_key,'mediaVersion',i.media_version,'basePricePaise',i.base_price_paise,'currencyCode','INR','taxRateBps',i.tax_rate_bps,'logisticsAttributes',i.logistics_attributes,'status',i.status,'version',i.version,'optionGroups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'selectionType',g.selection_type,'minimumSelections',g.minimum_selections,'maximumSelections',g.maximum_selections,'sortOrder',g.sort_order,'status',g.status,'version',g.version,'options',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'priceDeltaPaise',x.price_delta_paise,'sortOrder',x.sort_order,'status',x.status,'version',x.version)order by x.sort_order,x.id)from dastak_v1.restaurant_menu_options x where x.option_group_id=g.id and(p_include_inactive or x.status='ACTIVE')),'[]'::jsonb))order by g.sort_order,g.id)from dastak_v1.restaurant_menu_option_groups g where g.menu_item_id=i.id and(p_include_inactive or g.status='ACTIVE')),'[]'::jsonb))order by i.name,i.id)from dastak_v1.restaurant_menu_items i where i.category_id=c.id and(p_include_inactive or i.status='ACTIVE')),'[]'::jsonb))order by c.sort_order,c.id)from dastak_v1.restaurant_menu_categories c where c.branch_id=b.id and(p_include_inactive or c.status='ACTIVE')),'[]'::jsonb))
  from dastak_v1.merchant_branches b join dastak_v1.merchant_organizations o on o.id=b.organization_id left join dastak_v1.branch_operational_states s on s.branch_id=b.id where b.id=p_branch_id
$$;
