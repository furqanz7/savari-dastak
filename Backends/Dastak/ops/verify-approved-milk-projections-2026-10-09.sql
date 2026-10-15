-- Read-only projection checks using the approved owner's existing permissions.
with context as materialized (
 select '7105206a-6fec-45c9-8c00-3dfd5178fc1b'::uuid as actor,
 set_config('request.jwt.claim.sub','7105206a-6fec-45c9-8c00-3dfd5178fc1b',true) as claim
), admin_pages as materialized (
 select dastak_v1_api.admin_catalogue_page(c.actor,q.query,null,null,null,null,null,100,null,null) as payload
 from context c cross join (values ('Nestle Everyday'),('Amul Taaza'),('Arokya')) q(query)
 where c.claim is not null
), admin_skus as (
 select distinct item from admin_pages p cross join lateral jsonb_array_elements(p.payload->'skus') item
), authorized_branch as materialized (
 select b.id,c.actor from dastak_v1.merchant_branches b cross join context c
 where c.claim is not null and b.status not in ('CLOSED','SUSPENDED')
 and dastak_v1_api.actor_has_wave1_merchant_permission(c.actor,b.organization_id,
   'merchant.catalogue.selection.manage',b.id)
 order by b.created_at,b.id limit 1
), merchant_page as materialized (
 select dastak_v1_api.merchant_canonical_catalogue_snapshot(actor,id,1000) as payload from authorized_branch
), target_ids as (
 select resource_id as id from dastak_v1.idempotency_records
 where actor_id='7105206a-6fec-45c9-8c00-3dfd5178fc1b' and command_name='updateCatalogueSku'
 and idempotency_key like 'dastak-approved-milk-20261009:%'
)
select jsonb_build_object(
 'admin',(select jsonb_agg(jsonb_build_object('id',item->>'id','pack',item->>'packSize',
  'productType',item->'attributes'->>'productType') order by item->>'id')
  from admin_skus join target_ids t on t.id=(item->>'id')::uuid),
 'merchantAuthorizedBranchFound',exists(select 1 from authorized_branch),
 'merchant',(select jsonb_agg(jsonb_build_object('id',item->>'skuId','pack',item->>'packSize',
  'productType',item->'attributes'->>'productType') order by item->>'skuId')
  from merchant_page p cross join lateral jsonb_array_elements(p.payload->'skus') item
  join target_ids t on t.id=(item->>'skuId')::uuid)
) as projection_receipt;
