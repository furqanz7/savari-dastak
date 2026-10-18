# Merchant notification navigation and registration recovery

18 October 2026. Local M-12 implementation follow-up to the [completion audit](dastak-merchant-completion-audit-2026-10-18.md), not a live notification-delivery sign-off.

## Scope and guard

Solo work in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Earlier local Merchant work, Customer screenshot fixtures, release documents, artwork and generated dependency-lock changes were preserved.

No migration, server implementation change, production read/write, route activation, deployment, commit/push, installation, Apple configuration, real notification, order, payment or payout was performed. The server-side change in this slice is a mock APNs regression test only.

The Supabase skill guided authenticated-read and identity boundaries. Official [Edge authentication guidance](https://supabase.com/docs/guides/functions/auth) was checked; notification payloads and local preferences are never authorization. Existing Merchant actor checks and the separate safe-detail endpoint remain required.

## Notification taps

`DastakMerchantNotificationRoute`, `DastakMerchantNotificationInbox` and `DastakMerchantNotificationNavigator` replace the former boolean-only navigation for supported order alerts.

- The parser accepts only the existing eight `merchant.*` types: opportunity, restaurant request, recovery opportunity, preparation started, rider assigned, rider arrived, incoming return and cancellation.
- A route must have `entityType: dastakV1Order` and a UUID order ID. Present `orderId` and `entityId` fields must agree. Foreign roles, unknown types, malformed/conflicting IDs are rejected.
- The app delegate handles normal notification taps only. Foreground presentation still refreshes Orders and offers banner/sound; receiving an alert alone never performs an order action or opens a detail sheet.
- A single pending hint survives launch/sign-in in UserDefaults, expires after 24 hours and is consumed once. Only type, order UUID and receipt time are retained. No token, title/body, customer address, contact, PIN or arbitrary payload extras are stored by this inbox.
- The most recent system-alert fingerprint suppresses repeat callbacks within 24 hours. This is bounded local tap deduplication, not an exactly-once APNs delivery guarantee or a persistent history of every alert.
- A tap selects Orders and its relevant queue, then opens a dismissible read-only lookup sheet. Current authenticated operations and restaurant-request reads run concurrently under an overall 12-second deadline. Identity is checked before and after. Access/session failure in either read fails closed; a transport failure may expose only exact matches from the successful read, with an explicit partial-results explanation.
- Only exact order-ID matches from authorized server reads become choices. Each choice keeps its own record kind and location ID. Opening full order rechecks permission through the M-05 detail endpoint. It does not reuse Customer/Admin reads.
- Notification navigation does not silently change the selected Store, discard menu drafts, alter a pending command or acquire a business-action lock. If action is needed at a different location, the merchant returns to Orders and explicitly selects that Store.
- A newer tap supersedes an older lookup. Dismissal, timeout and account changes prevent stale results from publishing. Bounded UI waiting does not claim cancellation of a server request already in flight.
- The prior boolean preference is consumed as an all-Orders fallback for compatibility, then removed.

## Truthful fallback and existing limits

The current retail opportunity projection does **not** include order ID. A retail opportunity alert therefore cannot always identify an exact offer safely. It opens New orders with an explanation unless the same order already has a matching authorized fulfilment. It never guesses from a display number, payload branch ID or unrelated offer.

Food requests, recovery and returns resolve their corresponding exact record where available; other supported order alerts resolve matching fulfilments. If an exact record has expired, completed outside the available window, been removed or is unavailable to the account, the sheet explains that limitation and allows returning to the relevant queue or retrying. A cancellation alert is not proof that historical data is still available in current reads.

Earlier M-05/M-10 production migration and Edge activation remain pending. M-12 adds no new production migration. Existing `scripts/check-merchant-notifications.sql` was inspected but **not executed against production**; mock sender tests do not establish that live route configuration, cron, credentials or device registration is healthy.

## Registration recovery

- Existing 15-second Apple device-token callback watchdog is retained.
- Settings lookup and authenticated server registration have separate bounded request waits, default 12 seconds. Unresponsive callbacks or server acknowledgements cannot keep the UI in Connecting indefinitely.
- Failure details remain visible. Permission alone and a false/failed/late acknowledgement cannot report a device registered.
- Concurrent settings refreshes and repeated identical in-flight token callbacks coalesce. Invalidated attempts and late acknowledgements cannot reclaim the current registration state.
- Merchant registration verifies current account identity around the request. A changed account fails the attempt rather than declaring the new account linked.
- Foreground Merchant recovery makes at most three automatic retries, with 5/15/45-second backoff gates. It asks Apple for a fresh callback each time; it does not replay a disk-cached token. Explicit refresh/foreground re-entry starts a new bounded recovery cycle.
- Muted alerts/sound still direct the user to Settings. Automatic recovery never prompts for permission; enabling permission is an explicit user action.
- Merchant app topic and APNs environment remain explicit. No device token is added to preferences or logs.

`DastakMerchantNotifications` is also the pre-existing shared Customer/Delivery registration helper. Its bounded/coalescing/failure behavior therefore applies there too. The new automatic recovery loop and account provider wiring are Merchant-only; Customer/Delivery retain their own `com.dastak.app` topic and foreground registration lifecycle. Their existing fresh-token/topic regression test is preserved. No Customer shopping or Delivery business workflow was edited by M-12.

## Automated verification

Added 18 Swift tests (12 routing/resolution and six registration recovery) plus one server mock test iterating all eight Merchant alert types, sandbox/production hosts and first/retry attempts. They cover malformed/foreign/conflicting hints, persisted/expired/corrupt hints, exact-location/order matching, retail fallback, partial transport reads versus access denial, actor changes, superseding/dismissed/timed-out lookups, late registration responses, bounded recovery, permission changes and callback coalescing.

| Check | Result |
| --- | --- |
| Full DastakUI hosted package | 694 tests, zero failures |
| Full Infrastructure hosted package | 189 tests, zero failures |
| Full Dastak Edge fixture suite | 377 tests, zero failures; mocked transports, no production requests |
| Merchant generic iOS Simulator Debug build | BUILD SUCCEEDED, signing disabled |
| Shared Customer/Delivery app generic iOS Simulator Debug build | BUILD SUCCEEDED, signing disabled |
| Whitespace and branch/HEAD guard | Passed; unchanged |

Logs: `/tmp/dastak-merchant-notification-ui.log`, `/tmp/dastak-merchant-notification-infra.log`, `/tmp/dastak-merchant-notification-edge.log`, `/tmp/dastak-merchant-notification-ios-final.log`, `/tmp/dastak-merchant-notification-customer-ios.log`.

The newly introduced unused-result warning in the Merchant delegate was fixed before the final build. The final Merchant build retains Xcode's App Intents metadata-extraction warning because this target has no App Intents dependency; it is not a notification compilation failure.

## Deferred live acceptance

Still separate: foreground/background/terminated and pre-sign-in taps on a real Merchant device; all eight events with exact event/outbox/APNs/device timing; permission/Focus behavior; sandbox versus distributed production registration; duplication/missing/delayed delivery measurement; account/location revocation and expired records; actual sheet presentation and VoiceOver/large-text tap-through. Neither package tests nor a simulator compilation establishes these outcomes.

M-12's local navigation/recovery slice is implemented. Its live-delivery acceptance is not finished. Broader M-13 visual/interaction polish and M-14 Merchant distribution also remain separate.
