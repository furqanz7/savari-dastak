begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select is((select count(*) from dastak_v1.notification_routes
 where audience='CUSTOMER' and enabled and platform in ('ios','all')),25::bigint,
 'Customer lifecycle routes and cancellation are present after migrations');
select is((select count(*) from dastak_v1.notification_routes
 where audience='RIDER' and enabled and platform in ('ios','all')),5::bigint,
 'Delivery offers, assignment, readiness, returns and cancellation have routes');
select ok(exists(select 1 from dastak_v1.notification_routes
 where event_type='RIDER_POOL_OPENED' and audience='RIDER'
 and notification_type='rider.mission_offer' and enabled and platform='all'),
 'new delivery offers route to both supported platforms');
select ok(exists(select 1 from dastak_v1.notification_routes
 where event_type='LAUNCH_PAYMENT_COLLECTED' and audience='CUSTOMER'
 and notification_type='customer.payment_collected_at_delivery' and enabled),
 'pay-at-delivery collection has a Customer notification');
select is(has_table_privilege('authenticated','dastak_v1.notification_routes','INSERT'),false,
 'clients cannot bypass audited route management');
select ok((select relrowsecurity from pg_class where oid='dastak_v1.notification_routes'::regclass),
 'notification route RLS remains enabled');

select * from finish();
rollback;
