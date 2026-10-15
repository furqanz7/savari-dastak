-- Approved data-only batch. Default is ROLLBACK: rehearse before making a COMMIT copy.
-- Uses the existing audited/version-protected command, not direct SKU updates.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
select pg_advisory_xact_lock(hashtextextended('dastak-v1-catalogue-write', 0));
select set_config('request.jwt.claim.sub', '7105206a-6fec-45c9-8c00-3dfd5178fc1b', true);
select set_config('request.jwt.claims', '{"sub":"7105206a-6fec-45c9-8c00-3dfd5178fc1b","role":"authenticated"}', true);

create temp table approved_milk_targets (
  id uuid primary key, expected_version bigint, expected_name text,
  expected_pack text, product_type text, repair_description boolean
) on commit drop;
insert into approved_milk_targets values
('21de9800-be42-4da4-ba6f-13bf17980145',5,'Nestle Everyday Dairy Whitener','200 g','Dairy Whitener',false),
('2642d986-1130-4d4a-88bf-d0da178469d7',9,'Nestle Everyday Dairy Whitener','15 g','Dairy Whitener',true),
('6c425649-c011-4f9e-80dc-3b228a95b5ff',5,'Nestle Everyday Dairy Whitener','1 kg','Dairy Whitener',false),
('d5e0f1fc-f851-4469-b307-b858d4fed175',5,'Nestle Everyday Dairy Whitener','400 g','Dairy Whitener',false),
('5908c4c1-9dce-4104-9342-13a9ab7926aa',5,'Arokya Full Cream Milk','1 L','Full Cream',false),
('5d9344b3-4d48-4cc2-a041-289fba4155bb',6,'Amul Taaza Toned Milk','1 L','Toned',false),
('a51d8c7d-bd8c-4f1e-8728-27b2b3df7397',7,'Amul Taaza Toned Milk','200 ml','Toned',false),
('3ca69e40-a71f-4c10-977b-738aa67b9b3f',5,'Arokya Toned Milk','500 ml','Toned',false);

create temp table approved_milk_before on commit drop as
select s.id, to_jsonb(s) as row_data
from dastak_v1.skus s join approved_milk_targets t on t.id=s.id;
create temp table approved_milk_invariants on commit drop as
select
 (select md5(coalesce(jsonb_agg(to_jsonb(s) order by s.id)::text,'[]'))
  from dastak_v1.skus s where not exists(select 1 from approved_milk_targets t where t.id=s.id)) as other_skus,
 (select md5(coalesce(jsonb_agg(to_jsonb(m) order by m.branch_id,m.sku_id)::text,'[]'))
  from dastak_v1.merchant_sku_selections m join approved_milk_targets t on t.id=m.sku_id) as selections,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.inventory_hold_id)::text,'[]'))
  from dastak_v1.merchant_stock_reservations r join approved_milk_targets t on t.id=r.sku_id) as reservations;

do $batch$
declare
  actor constant uuid := '7105206a-6fec-45c9-8c00-3dfd5178fc1b';
  v_target record; v_sku dastak_v1.skus%rowtype; patch jsonb; receipt jsonb;
begin
  perform dastak_v1_api.assert_platform_permission(actor,'platform.catalogue.manage');
  if md5(pg_get_functiondef('dastak_v1_api.update_catalogue_sku(uuid,uuid,text,bigint,jsonb)'::regprocedure))
     <> 'bf7dd44be9bf075b99bfdd67f9be9c76' then
    raise exception 'Catalogue command changed since review';
  end if;
  if (select count(*) from approved_milk_before) <> 8 or exists (
    select 1 from approved_milk_targets t join dastak_v1.skus s on s.id=t.id
    where s.version is distinct from t.expected_version
      or s.canonical_name is distinct from t.expected_name
      or s.pack_size is distinct from t.expected_pack
      or s.status::text <> 'ACTIVE'
      or s.attribute_data ? 'productType'
      or (t.repair_description and s.description is distinct from
        'Curated infant milk formula for Dastak grocery delivery.')
  ) then raise exception 'Reviewed SKU preconditions changed; no batch applied'; end if;
  if exists (select 1 from dastak_v1.idempotency_records
    where actor_id=actor and command_name='updateCatalogueSku'
      and idempotency_key like 'dastak-approved-milk-20261009:%') then
    raise exception 'Batch key already exists; inspect durable receipt before retrying';
  end if;

  for v_target in select * from approved_milk_targets order by id loop
    select * into strict v_sku from dastak_v1.skus where id=v_target.id for update;
    patch := jsonb_build_object('attributes',v_sku.attribute_data || jsonb_build_object('productType',v_target.product_type));
    if v_target.repair_description then
      patch := patch || jsonb_build_object('description','Dairy whitener for tea and coffee.');
    end if;
    receipt := dastak_v1_api.update_catalogue_sku(actor,v_target.id,
      'dastak-approved-milk-20261009:' || v_target.id::text,v_target.expected_version,patch);
    if (receipt->>'version')::bigint <> v_target.expected_version+1 then
      raise exception 'Unexpected command receipt';
    end if;
  end loop;

  if exists (
    select 1 from approved_milk_targets t
    join approved_milk_before b on b.id=t.id join dastak_v1.skus s on s.id=t.id
    where s.version <> t.expected_version+1
      or s.attribute_data->>'productType' is distinct from t.product_type
      or (s.attribute_data-'productType') is distinct from (b.row_data->'attribute_data')
      or (to_jsonb(s)-(array['attribute_data','version','updated_at','description'] ||
          case when t.repair_description then array['search_document'] else array[]::text[] end))
         is distinct from (b.row_data-(array['attribute_data','version','updated_at','description'] ||
          case when t.repair_description then array['search_document'] else array[]::text[] end))
      -- The stored generated search index must follow the approved description, not remain stale.
      or s.search_document is distinct from (
          setweight(to_tsvector('simple'::regconfig,coalesce(s.canonical_name,'')),'A') ||
          setweight(to_tsvector('simple'::regconfig,coalesce(s.variant_name,'') || ' ' ||
            coalesce(s.pack_size,'') || ' ' || coalesce(s.barcode,'')),'B') ||
          setweight(to_tsvector('simple'::regconfig,coalesce(s.description,'')),'C'))
      or s.description is distinct from case when t.repair_description
         then 'Dairy whitener for tea and coffee.' else b.row_data->>'description' end
  ) then
    raise exception 'Post-update field preservation check failed: %', (
      select jsonb_agg(jsonb_build_object('id',t.id,'differences',(
        select jsonb_agg(jsonb_build_object('field',item.key,'before',b.row_data->item.key,'after',item.value))
        from jsonb_each(to_jsonb(s)) item where item.value is distinct from b.row_data->item.key
          and item.key not in ('version','updated_at','attribute_data','description')
      ),'beforeAttributes',b.row_data->'attribute_data','afterAttributes',s.attribute_data,
        'description',s.description))
      from approved_milk_targets t join approved_milk_before b on b.id=t.id join dastak_v1.skus s on s.id=t.id
    );
  end if;
  if (select other_skus from approved_milk_invariants) is distinct from
    (select md5(coalesce(jsonb_agg(to_jsonb(s) order by s.id)::text,'[]')) from dastak_v1.skus s
      where not exists(select 1 from approved_milk_targets t where t.id=s.id))
    or (select selections from approved_milk_invariants) is distinct from
    (select md5(coalesce(jsonb_agg(to_jsonb(m) order by m.branch_id,m.sku_id)::text,'[]'))
      from dastak_v1.merchant_sku_selections m join approved_milk_targets t on t.id=m.sku_id)
    or (select reservations from approved_milk_invariants) is distinct from
    (select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.inventory_hold_id)::text,'[]'))
      from dastak_v1.merchant_stock_reservations r join approved_milk_targets t on t.id=r.sku_id)
  then raise exception 'Non-target SKU or merchant stock changed during batch'; end if;
  if (select count(*) from dastak_v1.audit_events where actor_id=actor
    and action='CATALOGUE_SKU_UPDATED' and metadata->>'idempotencyKey' like 'dastak-approved-milk-20261009:%') <> 8
    or (select count(*) from dastak_v1.idempotency_records where actor_id=actor
    and command_name='updateCatalogueSku' and idempotency_key like 'dastak-approved-milk-20261009:%') <> 8
    or (select count(*) from dastak_v1.domain_events_outbox e join approved_milk_targets t
    on e.aggregate_id=t.id and e.aggregate_version=t.expected_version+1
    where e.event_type='CATALOGUE_SKU_UPDATED' and e.actor_id=actor) <> 8
  then raise exception 'Audit/outbox/idempotency verification failed'; end if;
end;
$batch$;

rollback;
select 'Approved Milk batch passed all checks and was rolled back (rehearsal only).' as result;
