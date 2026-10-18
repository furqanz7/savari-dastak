-- Production-safe read smoke: existing actors only, no identity creation,
-- no business writes, and no payload/account/order identifiers in the result.
-- SQL role/claim simulation is not a real signed-in HTTP/device acceptance test.
begin read only;
set local statement_timeout='15s';
set local lock_timeout='2s';
do $smoke$
declare
 actor uuid; branch uuid; target uuid; foreign_branch uuid;
 customer uuid; nonmerchant uuid; rider uuid;
 result jsonb := '{}'::jsonb; value jsonb; page_two jsonb;
 snapshot jsonb; status integer; denied boolean;
begin
 select u.account_id,b.id into actor,branch
 from dastak_v1.merchant_users u
 join dastak_v1.merchant_organizations o on o.id=u.organization_id
 join dastak_v1.merchant_branches b on b.organization_id=o.id
 where u.status='ACTIVE' and o.status='ACTIVE'
  and o.merchant_type in ('RETAIL','DASTAK_CONVENIENCE_STORE')
  and dastak_v1_api.actor_has_wave1_merchant_permission(u.account_id,o.id,'merchant.catalogue.selection.manage',b.id)
  and dastak_v1_api.actor_has_wave1_merchant_permission(u.account_id,o.id,'merchant.fulfilment.manage',b.id)
 order by exists(select 1 from dastak_v1.fulfilments f where f.branch_id=b.id) desc,b.id,u.account_id limit 1;
 if actor is null then raise exception 'No existing permitted retail actor for smoke'; end if;
 select id into target from dastak_v1.fulfilments where branch_id=branch order by committed_at desc,id desc limit 1;
 select b.id into foreign_branch from dastak_v1.merchant_branches b where
  not dastak_v1_api.actor_has_wave1_merchant_permission(actor,b.organization_id,'merchant.fulfilment.manage',b.id)
  order by b.id limit 1;
 select m.account_id into customer from private.account_memberships m where m.role='customer'
  and (m.suspended_until is null or m.suspended_until<=now()) order by m.account_id limit 1;
 select a.id into nonmerchant from public.accounts a where not exists(
  select 1 from dastak_v1.merchant_users u where u.account_id=a.id and u.status='ACTIVE') order by a.id limit 1;
 select m.account_id into rider from private.account_memberships m
  join private.delivery_partner_profiles p on p.account_id=m.account_id
  where m.role='dastak_partner' and m.approved_at is not null
   and (m.suspended_until is null or m.suspended_until<=now()) order by m.account_id limit 1;

 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 value := public.dastak_v1_merchant_locations_page(1,null,branch);
 if jsonb_typeof(value->'locations') is distinct from 'array' or value->'focusedLocation'->>'id' is distinct from branch::text then
  raise exception 'Location read failed'; end if;
 result := result || jsonb_build_object('locations',true,'locationRows',jsonb_array_length(value->'locations'));
 if value->>'nextCursor' is not null then
  page_two := public.dastak_v1_merchant_locations_page(1,(value->>'nextCursor')::uuid,null);
  if jsonb_array_length(page_two->'locations')>0 and page_two->'locations'->0->>'id'=value->'locations'->0->>'id' then
   raise exception 'Location cursor repeated'; end if;
  result := result || jsonb_build_object('locationCursor',true);
 end if;
 value := public.dastak_v1_merchant_inventory_page(branch,null,false,1,null,null);
 if jsonb_typeof(value->'skus') is distinct from 'array' then raise exception 'Inventory read failed'; end if;
 result := result || jsonb_build_object('inventory',true,'inventoryRows',jsonb_array_length(value->'skus'));
 if value->>'nextCursor' is not null then
  page_two := public.dastak_v1_merchant_inventory_page(branch,null,false,1,value->'nextCursor'->>'name',
   (value->'nextCursor'->>'skuId')::uuid);
  if jsonb_array_length(page_two->'skus')>0 and page_two->'skus'->0->>'skuId'=value->'skus'->0->>'skuId' then
   raise exception 'Inventory cursor repeated'; end if;
  result := result || jsonb_build_object('inventoryCursor',true);
 end if;
 value := public.dastak_v1_merchant_fulfilment_history(branch,null,null,1);
 if jsonb_typeof(value->'fulfilments') is distinct from 'array' then raise exception 'History read failed'; end if;
 result := result || jsonb_build_object('history',true,'historyRows',jsonb_array_length(value->'fulfilments'));
 if value->>'nextCursor' is not null then
  page_two := public.dastak_v1_merchant_fulfilment_history(branch,
   (value->'nextCursor'->>'committedAt')::timestamptz,(value->'nextCursor'->>'id')::uuid,1);
  if jsonb_array_length(page_two->'fulfilments')>0 and page_two->'fulfilments'->0->>'id'=value->'fulfilments'->0->>'id' then
   raise exception 'History cursor repeated'; end if;
  result := result || jsonb_build_object('historyCursor',true);
 end if;
 if target is not null then
  value := public.dastak_v1_merchant_order_detail(branch,'FULFILMENT',target);
  if value->'target'->>'id' is distinct from target::text or jsonb_typeof(value->'records') is distinct from 'array' then raise exception 'Detail failed'; end if;
  result := result || jsonb_build_object('fullOrderDetail',true);
 end if;
 value := public.dastak_v1_merchant_fulfilments(1);
 if jsonb_typeof(value->'fulfilments') is distinct from 'array' then raise exception 'Existing Merchant list failed'; end if;
 perform public.dastak_v1_merchant_canonical_catalogue_snapshot(branch,1);
 result := result || jsonb_build_object('existingMerchantList',true,'existingMerchantCatalogue',true);
 if foreign_branch is not null then
  denied := false;
  begin perform public.dastak_v1_merchant_fulfilment_history(foreign_branch,null,null,1);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Foreign history was not denied'; end if;
  result := result || jsonb_build_object('foreignBranchDenied',true);
 end if;
 execute 'reset role';
 execute 'set local role service_role';
 select r.response_body,r.response_status into snapshot,status from public.dastak_v1_merchant_royalty_controls_snapshot(actor) r;
 if status is distinct from 200 or jsonb_typeof(snapshot->'subjects') is distinct from 'array' then raise exception 'Merchant capability read failed'; end if;
 result := result || jsonb_build_object('merchantRoyaltyCapabilities',true,'royaltySubjectRows',jsonb_array_length(snapshot->'subjects'));
 if rider is not null then
  select r.response_body,r.response_status into snapshot,status from public.dastak_v1_delivery_partner_snapshot(rider) r;
  if status is distinct from 200 then raise exception 'Existing Delivery snapshot failed'; end if;
  select r.response_body,r.response_status into snapshot,status from public.dastak_v1_get_royalty_snapshot(rider,'RIDER') r;
  if status is distinct from 200 then raise exception 'Existing Delivery royalty read failed'; end if;
  result := result || jsonb_build_object('existingDeliverySnapshot',true,'existingDeliveryRoyalty',true);
 end if;
 execute 'reset role';
 if nonmerchant is not null then
  perform set_config('request.jwt.claim.sub',nonmerchant::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',nonmerchant,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  denied := false;
  begin perform public.dastak_v1_merchant_inventory_page(branch,null,false,1,null,null);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Non-Merchant inventory was not denied'; end if;
  result := result || jsonb_build_object('nonMerchantDenied',true);
  execute 'reset role';
 end if;
 if customer is not null then
  perform set_config('request.jwt.claim.sub',customer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  value := public.dastak_v1_customer_active_orders();
  if jsonb_typeof(value->'orders') is distinct from 'array' then raise exception 'Existing Customer read failed'; end if;
  result := result || jsonb_build_object('existingCustomerActiveOrders',true);
  execute 'reset role';
 end if;
 perform set_config('dastak.merchant_activation_smoke',result::text,true);
end $smoke$;
select current_setting('dastak.merchant_activation_smoke')::jsonb read_smoke;
rollback;
