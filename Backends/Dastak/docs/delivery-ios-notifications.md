# Delivery workspace and Customer / Rider notifications

## September 8, 2026 changes

- The native Delivery workspace prioritizes active deliveries and offers. It has
  a compact automatic-update status, pull-to-refresh, an online/location control,
  a notification setup/retry prompt and an expandable weekly earnings section.
- Pickup, route and handoff progress follow the server's mission state. Addresses
  wrap, pickup readiness is explicit, six-digit codes accept ASCII digits only,
  and expired offers cannot be accepted. Payment collection and pre-pickup release
  require confirmation. Server capability, custody and payment guards remain intact.
- Snapshot endpoints update independently. A legacy-service or earnings failure
  cannot hide a successfully fetched V1 assignment. Failed refreshes retain the
  last-known data and show an inline reconnect message instead of a modal alert.
- Customer and Delivery share fresh authenticated APNs registration above the app
  mode switch. No disk-cached token is trusted. Debug registers the sandbox topic;
  Release registers production, as in the existing Merchant registration contract.
- APNs payloads now include the authoritative `notificationType`. Rider alert taps
  select Delivery mode and the Deliveries tab, rather than Customer order details.

## Backend repair and release order

Production inspection found only cancellation routes for Customer and Rider,
while all eight Merchant routes from the previous repair were enabled. Restore the
24 Customer and four Rider missing seeds with
`20260907230629_restore_customer_delivery_notification_routes.sql`. Expected totals:
25 Customer, five Rider, eight Merchant. Existing custom copy, route versions and
disabled states are preserved. Historical published events are not replayed.

Production rider offers last 60 seconds, but the existing dispatcher ran once a
minute. Deploy `process-v1-outbox` **before** applying
`20260907232655_accelerate_delivery_order_notifications.sql`. The migration reuses
the existing vaulted URL/header command for an authenticated notification-only
pass every ten seconds. Durable claims and per-event/device uniqueness remain the
same. The existing minute job still handles account deletions and invariant checks;
the faster pass skips those tasks. This is a dispatch interval, not a guarantee of
Apple presentation or ten-second end-to-end delivery.

The migration dry run must list only these two new migrations. Native builds must
be distributed separately; deploying Supabase does not update an installed app.
No web source changes are included in this native-screen release.

## Verification completed before release

- DastakUI: 69 tests passed, including partial refresh retention, offer expiry,
  code validation and Customer/Delivery APNs registration regressions.
- Dastak Edge Functions: all 306 tests passed (16 notification-worker tests).
- Worker entrypoint Deno typecheck passed.
- Local database: 58 pgTAP files / 1,661 assertions passed.
- `bash scripts/test-notification-repair.sh` from this backend: route override
  preservation and schedule replay passed, with all fixtures rolled back.
- Generic iOS builds passed: Dastak Debug, Dastak Release, DastakMerchant Release.
- Production advisors: no performance warnings; four existing security warnings
  (three authenticated SECURITY DEFINER wrappers and leaked-password protection).
  This repair introduces no functions, grants or RLS changes.
- `git diff --check` passed.

The existing local database has schema changes whose migration-history entries
are absent. Bulk `migration up` stopped on an already-present permission seed.
No destructive reset or history rewrite was used. The new seed SQL was applied
idempotently to the existing local database, the full database suite passed, and
the separate rollback-only regression exercised the actual migration files.

No browser, simulator, physical iPhone, live-order or end-to-end push presentation
test was run, per the owner's instruction. Successful backend provider records
are not evidence that a device displayed a banner; permission, Focus and OS
delivery conditions remain relevant.

## Production result

Pending the release commands and post-deployment read-only verification.
