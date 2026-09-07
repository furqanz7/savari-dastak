-- Read-only release gate. No tokens, accounts, order details or credentials.
with required(event_type, notification_type) as (values
  ('MERCHANT_OPPORTUNITY_OFFERED', 'merchant.opportunity'),
  ('RESTAURANT_REQUEST_OFFERED', 'merchant.restaurant_request'),
  ('RECOVERY_OPPORTUNITY_OFFERED', 'merchant.recovery_opportunity'),
  ('PREPARATION_STARTED', 'merchant.preparation_started'),
  ('RIDER_ASSIGNED', 'merchant.rider_assigned'),
  ('RIDER_ARRIVED_PICKUP', 'merchant.rider_arrived'),
  ('RETURN_RIDER_ASSIGNED', 'merchant.return_incoming'),
  ('ORDER_CANCELLED', 'merchant.order_cancelled')
), missing as (
  select required.event_type from required
  where not exists (
    select 1 from dastak_v1.notification_routes route
    where route.event_type = required.event_type
      and route.notification_type = required.notification_type
      and route.audience = 'MERCHANT' and route.enabled
      and route.platform in ('ios', 'all')
  )
)
select
  not exists(select 1 from missing) as routes_ready,
  coalesce((select jsonb_agg(event_type order by event_type) from missing), '[]'::jsonb) as missing_routes,
  exists(select 1 from cron.job where jobname='dastak-v1-outbox-worker' and active) as worker_scheduled,
  (select count(*) from public.dastak_device_tokens
   where application_id='com.dastak.merchant' and platform='ios' and disabled_at is null) as active_merchant_devices;
