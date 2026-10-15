-- Read-only durable receipt, linked production database.
with batch as (
 select i.resource_id, i.response_body, a.metadata
 from dastak_v1.idempotency_records i
 join dastak_v1.audit_events a on a.actor_id=i.actor_id
  and a.metadata->>'idempotencyKey'=i.idempotency_key and a.action='CATALOGUE_SKU_UPDATED'
 where i.actor_id='7105206a-6fec-45c9-8c00-3dfd5178fc1b'
  and i.command_name='updateCatalogueSku'
  and i.idempotency_key like 'dastak-approved-milk-20261009:%'
)
select jsonb_build_object(
 'verifiedAt',now(), 'batchRows',(select count(*) from batch),
 'outboxRows',(select count(*) from dastak_v1.domain_events_outbox e join batch b
  on e.aggregate_id=b.resource_id and e.aggregate_version=(b.response_body->>'version')::bigint
  where e.event_type='CATALOGUE_SKU_UPDATED' and e.actor_id='7105206a-6fec-45c9-8c00-3dfd5178fc1b'),
 'activeSkus',(select count(*) from dastak_v1.skus where status='ACTIVE'),
 'classifiedActiveSkus',(select count(*) from dastak_v1.skus where status='ACTIVE' and attribute_data->>'productType' is not null),
 'skus',(select jsonb_agg(jsonb_build_object('id',s.id,'name',s.canonical_name,
  'pack',s.pack_size,'productType',s.attribute_data->>'productType','description',s.description,
  'version',s.version,'pricePaise',s.selling_price_paise,'slug',s.slug,'changedFields',b.metadata->'changedFields',
  'fromVersion',b.metadata->'fromVersion','outboxPresent',exists(select 1 from dastak_v1.domain_events_outbox e
    where e.aggregate_id=s.id and e.aggregate_version=s.version and e.event_type='CATALOGUE_SKU_UPDATED'))
  order by s.canonical_name,s.pack_size) from dastak_v1.skus s join batch b on b.resource_id=s.id),
 'projections',(select jsonb_agg(jsonb_build_object('name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
   'hasProductTypeProjection',pg_get_functiondef(p.oid) like '%productType%',
   'hasFullAttributesProjection',pg_get_functiondef(p.oid) like '%attribute_data%'))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='dastak_v1_api'
    and p.proname in ('customer_catalogue','admin_catalogue_snapshot','merchant_canonical_catalogue_snapshot'))
) as receipt;
