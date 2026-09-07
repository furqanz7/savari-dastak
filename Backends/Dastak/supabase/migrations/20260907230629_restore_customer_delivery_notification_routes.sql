-- Restore missing Customer and Delivery Partner lifecycle routes only.
-- Preserve existing overrides and disabled routes. Never replay historical events.
insert into dastak_v1.notification_routes (
  event_type, audience, notification_type, title, body
) values
  ('ORDER_SUBMITTED', 'CUSTOMER', 'customer.order_submitted', 'Finding your items', 'We are securing every exact item in your order.'),
  ('PAYMENT_WINDOW_STARTED', 'CUSTOMER', 'customer.payment_ready', 'Your items are reserved', 'Open your order to confirm before the reservation expires.'),
  ('PAYMENT_ATTEMPT_FAILED', 'CUSTOMER', 'customer.payment_failed', 'Payment did not complete', 'Your items remain reserved. You can try payment again.'),
  ('PAYMENT_CONFIRMED', 'CUSTOMER', 'customer.payment_confirmed', 'Order confirmed', 'Your order is confirmed and is being prepared.'),
  ('PAYMENT_RESERVATION_EXPIRED', 'CUSTOMER', 'customer.payment_expired', 'Reservation expired', 'The order was not confirmed in time. Your item reservation has been released.'),
  ('PREPARATION_STARTED', 'CUSTOMER', 'customer.preparing', 'Preparing your order', 'Your order is being prepared.'),
  ('RIDER_ASSIGNED', 'CUSTOMER', 'customer.rider_assigned', 'Picking up your order', 'A delivery partner is collecting every package.'),
  ('ORDER_OUT_FOR_DELIVERY', 'CUSTOMER', 'customer.out_for_delivery', 'Your order is on the way', 'Keep your in-app delivery code ready for handoff.'),
  ('RIDER_ARRIVED_CUSTOMER', 'CUSTOMER', 'customer.rider_arrived', 'Your delivery partner has arrived', 'Check your packages and complete any payment due before sharing the delivery code.'),
  ('ORDER_DELIVERED', 'CUSTOMER', 'customer.delivered', 'Order delivered', 'Every package was handed over and verified.'),
  ('ORDER_UNAVAILABLE', 'CUSTOMER', 'customer.unavailable', 'Order unavailable', 'We could not secure every exact item. You were not charged.'),
  ('ORDER_CANCELLED_PREPAYMENT', 'CUSTOMER', 'customer.cancelled', 'Order cancelled', 'Your unpaid order and item reservations were cancelled.'),
  ('RECOVERY_STARTED', 'CUSTOMER', 'customer.recovery_started', 'We are fixing an item issue', 'Dastak is securing the same exact item.'),
  ('RECOVERY_SUCCEEDED', 'CUSTOMER', 'customer.recovery_succeeded', 'Exact item secured', 'Your order can continue without a substitution.'),
  ('RECOVERY_FAILED', 'CUSTOMER', 'customer.recovery_failed', 'Item recovery update', 'The exact item could not be recovered. Open your order for the next steps.'),
  ('DELIVERY_RECOVERY_STARTED', 'CUSTOMER', 'customer.delivery_recovery', 'Delivery support is helping', 'Operations is resolving a delivery problem.'),
  ('CUSTOMER_ISSUE_REPORTED', 'CUSTOMER', 'customer.issue_reported', 'Issue received', 'Support has received your report and evidence.'),
  ('REFUND_CREATED', 'CUSTOMER', 'customer.refund_started', 'Refund started', 'Your refund is being processed. Open your order for details.'),
  ('REFUND_COMPLETED', 'CUSTOMER', 'customer.refund_completed', 'Refund completed', 'Your refund has been completed. Open your order for details.'),
  ('RETURN_APPROVED', 'CUSTOMER', 'customer.return_approved', 'Return approved', 'Follow the in-app return steps and keep every package ready.'),
  ('RETURN_RIDER_ASSIGNED', 'CUSTOMER', 'customer.return_rider_assigned', 'Return pickup assigned', 'A delivery partner was assigned to collect your return.'),
  ('RETURN_PICKUP_VERIFIED', 'CUSTOMER', 'customer.return_picked_up', 'Return collected', 'Your return packages are on their way back.'),
  ('RETURN_RECEIPT_VERIFIED', 'CUSTOMER', 'customer.return_received', 'Return received', 'The merchant verified receipt of every return package.'),
  ('RIDER_POOL_OPENED', 'RIDER', 'rider.mission_offer', 'New delivery mission', 'Review the pickup count, route and required transport before accepting.'),
  ('RIDER_ASSIGNED', 'RIDER', 'rider.assigned', 'Delivery assigned', 'Your delivery is confirmed. Continue to the pickup stops.'),
  ('FULFILMENT_READY', 'RIDER', 'rider.fulfilment_ready', 'Pickup is ready', 'A pickup stop has marked every package Ready.'),
  ('RETURN_RIDER_ASSIGNED', 'RIDER', 'rider.return_assigned', 'Return mission assigned', 'Collect and transfer every return package using in-app verification.'),
  ('LAUNCH_PAYMENT_COLLECTED', 'CUSTOMER', 'customer.payment_collected_at_delivery', 'Payment collected', 'Your payment was collected at delivery. You can now complete the handoff.')
on conflict (event_type, audience, notification_type) do nothing;
