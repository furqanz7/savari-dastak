# Merchant iOS orders and notification routing

## Order desk

The native Merchant workspace requests `merchantOpportunities`, `restaurantRequests`
and `merchantFulfilments` independently. The first endpoint records the authenticated
actor's branch heartbeat. A foreground poll runs every ten seconds; notification,
realtime and foreground events request another refresh. Polls are coalesced.
Failures retain last-good data with an inline warning; catalogue, earnings and
legacy-order failures cannot discard a successful current-order response.
The Orders toolbar has no refresh button. Pull-to-refresh is the manual fallback;
the small status row explains automatic updates without a continuously ticking label.

Acceptance carries the server version, requested scope and selected preparation
time. Physical item/selection confirmation is required by the UI before acceptance.
Retries reuse their idempotency key. Preparation uses declared package counts,
uploaded evidence and the server's irreversible Ready transition. Pickup codes
are displayed only when supplied by the authorized fulfilment projection.

## Push contract

| Application | APNs topic | Audiences |
| --- | --- | --- |
| Dastak Customer / Delivery Partner | `com.dastak.app` | Customer, Rider |
| Dastak Merchant | `com.dastak.merchant` | Merchant |

The authenticated registration endpoint accepts `applicationId` and
`apnsEnvironment` (`sandbox` or `production`). Merchant registrations require an
explicit environment. Existing clients without these fields remain Customer-app
registrations and retain the configured legacy APNs environment.

New native Debug builds send sandbox; Release builds send production, matching
normal development signing and App Store/TestFlight distribution respectively.
If distributing a Release configuration with development signing, use a matching
sandbox registration configuration before testing it.

The APNs signing key must be valid for both topics in the same Apple team.
No new secret names are introduced. Existing `APNS_BUNDLE_ID` and
`APNS_ENVIRONMENT` are used only for legacy fallback; per-registration values route
new V1 deliveries. Web Push registration and routing remain unchanged.

Tokens are unique per app and environment. Fanout selects the correct app.
Claiming suppresses queued deliveries after token ownership changes. Completion
will not disable a registration refreshed after the delivery was claimed.
Topic mismatch responses do not retire tokens. Legacy senders are restricted
to Customer-app registrations and disable only explicitly unregistered tokens,
without deleting notification history.

### Registration feedback

Merchant requests a fresh APNs registration on foreground/account entry and sends
every callback through the authenticated registration endpoint, even when the token
value has not changed. It no longer uses a disk-cached token or skips registration
based solely on the last token string. The server remains the account authority.

Notification permission, Apple registration and server registration are distinct.
The inline alert prompt stays visible through connection, Apple failure, a missing
callback (15-second timeout), server failure or a false registration acknowledgment.
Disabled banners or sounds direct the merchant to iOS Settings. Successful server
registration is not proof of delivery, and iOS Focus can still silence notifications.

### Missing production route repair

The September 8 investigation found recent `MERCHANT_OPPORTUNITY_OFFERED` events
published with zero intents or deliveries. Production contained only the later
cancellation and restaurant-request routes; the six original Merchant routes were
absent. The registered Merchant device was bound to a different store from the
recent retail requests at inspection time; historical device ownership cannot be
inferred from its current registration.

`20260907183353_restore_merchant_order_notification_routes.sql` restores only missing
Merchant routes, uses pay-at-delivery preparation wording, and leaves existing route
copy, versions, disabled states and other audiences untouched. It does not replay
published events or change orders. This is a data-only seed repair, so a schema diff
cannot generate its inserts. Other missing Customer/Rider route seeds require a
separate scoped audit; this repair does not activate unrelated notifications.

Before and after deployment run the read-only release gate from the repository root:

```sh
bash scripts/check-merchant-notifications.sh --linked
```

It fails for missing/disabled Merchant iOS routes or an inactive outbox cron and
prints an aggregate active-device count without identifiers or tokens. The existing
dispatcher runs once per minute; inbox updates and push dispatch are independent.
The gate checks configuration, not actual Apple delivery or on-device permissions.

## Release and verification

Apply `20260907172722_merchant_app_notifications.sql`, then deploy:

- `register-device-token`
- `process-v1-outbox`
- `process-order-notification-queue`
- `send-order-notification`

Ship updated Merchant and Customer iOS binaries separately. Backend deployment
does not update installed apps. Merchant users must enable notification permission
in the order desk or iOS Settings. There is no production test-order creation in
this release.

Regression gates include the database suite and app-routing pgTAP tests,
Edge handler/provider tests, native package tests, and generic iOS compilation.
Browser, Simulator and physical-device tests require the owner's explicit request.

The local database predates three migration-history entries despite having the
preceding schema changes. `db pull --local` therefore cannot generate a trustworthy
incremental migration in this checkout. Its history was left unchanged; the scoped
migration was created with the CLI, applied locally in a transaction, and verified
with the full pgTAP suite and security advisor. Production dry-run must list only
the new notification migration.
