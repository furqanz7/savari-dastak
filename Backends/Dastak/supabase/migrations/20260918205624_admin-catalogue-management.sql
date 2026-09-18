-- Privileged catalogue taxonomy management. Archive is deliberately soft so
-- historical order references remain valid and records can be restored.
create or replace function dastak_v1_api.admin_catalogue_taxonomy_mutation(
  p_actor_id uuid,
  p_idempotency_key text,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type_id uuid; v_category_id uuid; v_subcategory_id uuid; v_id uuid;
  v_slug text := lower(trim(coalesce(p_payload->>'slug','')));
  v_name text := trim(coalesce(p_payload->>'name',''));
  v_parent_slug text := lower(trim(coalesce(p_payload->>'categorySlug','')));
  v_type_slug text := lower(trim(coalesce(p_payload->>'categoryTypeSlug','')));
  v_status dastak_v1.catalogue_status := upper(coalesce(p_payload->>'status','DRAFT'))::dastak_v1.catalogue_status;
  v_sort integer := coalesce(nullif(p_payload->>'sortOrder','')::integer,0);
begin
  perform dastak_v1_api.assert_platform_permission(p_actor_id,'platform.catalogue.manage');
  if p_idempotency_key is null or char_length(p_idempotency_key) not between 1 and 200 then
    raise exception using errcode='22023',message='invalid idempotency key';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode='22023',message='catalogue mutation payload must be an object';
  end if;
  if p_operation in ('CREATE_CATEGORY_TYPE','ARCHIVE_CATEGORY_TYPE') then
    if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or char_length(v_name) not between 1 and 100 then
      raise exception using errcode='22023',message='category type fields are invalid';
    end if;
    insert into dastak_v1.category_types(name,slug,image_key,status,sort_order,created_by)
    values(v_name,v_slug,nullif(trim(p_payload->>'imageKey'),''),v_status,v_sort,p_actor_id)
    on conflict(slug) do update set name=excluded.name,image_key=excluded.image_key,
      status=case when p_operation='ARCHIVE_CATEGORY_TYPE' then 'INACTIVE' else excluded.status end,
      sort_order=excluded.sort_order,updated_at=now(),version=dastak_v1.category_types.version+1
    returning id into v_type_id;
    if p_operation='ARCHIVE_CATEGORY_TYPE' then
      update dastak_v1.categories set status='INACTIVE',updated_at=now(),version=version+1 where category_type_id=v_type_id;
      update dastak_v1.skus set status='INACTIVE',updated_at=now(),version=version+1
      where subcategory_id in (select sc.id from dastak_v1.subcategories sc join dastak_v1.categories c on c.id=sc.category_id where c.category_type_id=v_type_id);
    end if;
    return jsonb_build_object('operation',p_operation,'id',v_type_id,'status',case when p_operation='ARCHIVE_CATEGORY_TYPE' then 'INACTIVE' else v_status::text end);
  end if;
  if p_operation in ('CREATE_CATEGORY','ARCHIVE_CATEGORY') then
    if v_type_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or char_length(v_name) not between 1 and 100 then
      raise exception using errcode='22023',message='category fields are invalid';
    end if;
    select id into v_type_id from dastak_v1.category_types where slug=v_type_slug;
    if v_type_id is null then raise exception using errcode='P0002',message='category type was not found'; end if;
    insert into dastak_v1.categories(category_type_id,name,slug,image_key,status,sort_order,created_by)
    values(v_type_id,v_name,v_slug,nullif(trim(p_payload->>'imageKey'),''),v_status,v_sort,p_actor_id)
    on conflict(slug) do update set category_type_id=excluded.category_type_id,name=excluded.name,image_key=excluded.image_key,
      status=case when p_operation='ARCHIVE_CATEGORY' then 'INACTIVE' else excluded.status end,sort_order=excluded.sort_order,
      updated_at=now(),version=dastak_v1.categories.version+1 returning id into v_category_id;
    if p_operation='ARCHIVE_CATEGORY' then
      update dastak_v1.subcategories set status='INACTIVE',updated_at=now(),version=version+1 where category_id=v_category_id;
      update dastak_v1.skus set status='INACTIVE',updated_at=now(),version=version+1 where subcategory_id in (select id from dastak_v1.subcategories where category_id=v_category_id);
    end if;
    return jsonb_build_object('operation',p_operation,'id',v_category_id,'status',case when p_operation='ARCHIVE_CATEGORY' then 'INACTIVE' else v_status::text end);
  end if;
  if p_operation in ('CREATE_SUBCATEGORY','ARCHIVE_SUBCATEGORY') then
    if v_parent_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or char_length(v_name) not between 1 and 100 then
      raise exception using errcode='22023',message='subcategory fields are invalid';
    end if;
    select id into v_category_id from dastak_v1.categories where slug=v_parent_slug;
    if v_category_id is null then raise exception using errcode='P0002',message='category was not found'; end if;
    insert into dastak_v1.subcategories(category_id,name,slug,image_key,status,sort_order,created_by)
    values(v_category_id,v_name,v_slug,nullif(trim(p_payload->>'imageKey'),''),v_status,v_sort,p_actor_id)
    on conflict(category_id,slug) do update set name=excluded.name,image_key=excluded.image_key,
      status=case when p_operation='ARCHIVE_SUBCATEGORY' then 'INACTIVE' else excluded.status end,sort_order=excluded.sort_order,
      updated_at=now(),version=dastak_v1.subcategories.version+1 returning id into v_subcategory_id;
    if p_operation='ARCHIVE_SUBCATEGORY' then update dastak_v1.skus set status='INACTIVE',updated_at=now(),version=version+1 where subcategory_id=v_subcategory_id; end if;
    return jsonb_build_object('operation',p_operation,'id',v_subcategory_id,'status',case when p_operation='ARCHIVE_SUBCATEGORY' then 'INACTIVE' else v_status::text end);
  end if;
  raise exception using errcode='22023',message='unsupported catalogue mutation';
end;
$$;

create or replace function public.dastak_v1_admin_catalogue_taxonomy_mutation(
  p_idempotency_key text, p_operation text, p_payload jsonb
) returns jsonb language sql security definer set search_path='' as $$
  select dastak_v1_api.admin_catalogue_taxonomy_mutation(auth.uid(),p_idempotency_key,p_operation,p_payload)
$$;
revoke all on function public.dastak_v1_admin_catalogue_taxonomy_mutation(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.dastak_v1_admin_catalogue_taxonomy_mutation(text,text,jsonb) to authenticated;
