begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is((select count(*) from dastak_v1.notification_routes
 where audience='MERCHANT' and enabled and platform in ('ios','all') and event_type in (
 'MERCHANT_OPPORTUNITY_OFFERED','RESTAURANT_REQUEST_OFFERED','RECOVERY_OPPORTUNITY_OFFERED',
 'PREPARATION_STARTED','RIDER_ASSIGNED','RIDER_ARRIVED_PICKUP','RETURN_RIDER_ASSIGNED','ORDER_CANCELLED'
 )),8::bigint,'all Merchant order lifecycle routes are present after migrations');

select ok(exists(select 1 from dastak_v1.notification_routes
 where event_type='MERCHANT_OPPORTUNITY_OFFERED' and audience='MERCHANT' and enabled and platform='all'),
 'new retail requests route to both Merchant platforms');
select is((select title from dastak_v1.notification_routes
 where event_type='PREPARATION_STARTED' and audience='MERCHANT'),
 'Order confirmed','restored preparation copy preserves pay-at-delivery semantics');
select is(has_table_privilege('authenticated','dastak_v1.notification_routes','INSERT'),false,
 'authenticated clients cannot change routing configuration');
select ok((select relrowsecurity from pg_class where oid='dastak_v1.notification_routes'::regclass),
 'notification route RLS remains enabled');
select * from finish();
rollback;
