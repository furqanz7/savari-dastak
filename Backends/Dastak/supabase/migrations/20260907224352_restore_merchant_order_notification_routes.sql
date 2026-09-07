-- Production had the later cancellation/food routes but none of the original
-- Merchant order routes. Published events without a route produce no intent.
-- Restore only this task's Merchant routes; do not replay expired order events
-- or change an existing route's identity, copy, or intentional disabled state.
insert into dastak_v1.notification_routes (
  event_type, audience, notification_type, platform, title, body
) values
  ('MERCHANT_OPPORTUNITY_OFFERED', 'MERCHANT', 'merchant.opportunity', 'all',
   'New Dastak request', 'Confirm the exact requested items before the timer expires.'),
  ('RECOVERY_OPPORTUNITY_OFFERED', 'MERCHANT', 'merchant.recovery_opportunity', 'all',
   'Exact-item recovery request', 'Confirm the exact SKU and full quantity before the timer expires.'),
  ('PREPARATION_STARTED', 'MERCHANT', 'merchant.preparation_started', 'all',
   'Order confirmed', 'Start preparing this order now. The Delivery Partner will collect payment at the doorstep.'),
  ('RIDER_ASSIGNED', 'MERCHANT', 'merchant.rider_assigned', 'all',
   'Rider assigned', 'A delivery partner is heading to the pickup stops.'),
  ('RIDER_ARRIVED_PICKUP', 'MERCHANT', 'merchant.rider_arrived', 'all',
   'Rider arrived', 'Verify every declared package before handoff.'),
  ('RETURN_RIDER_ASSIGNED', 'MERCHANT', 'merchant.return_incoming', 'all',
   'Return incoming', 'A return rider will bring packages for verified receipt.')
on conflict (event_type, audience, notification_type) do nothing;
