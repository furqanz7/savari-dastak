# Dastak live delivery tracking and ordered handoff

Implementation date: 9 September 2026. Native release: 1.0.0, build 3.

## Scope and architecture

Customer and Merchant order cards use the same MapKit tracking component as soon as an assigned mission exists. Customer may also see their own destination. Merchant tracking adds no customer destination or other branches' pickup data. An unavailable first fix is described explicitly, never replaced with an invented rider position.

This reuses the existing delivery mission state machine, authenticated order/fulfilment snapshots, and private `order-account:<account-id>` Realtime broadcasts. No new realtime provider or route-history service is introduced. Existing outbox notifications, payment accounting and package custody remain authoritative.

The existing private partner-availability row stores one mission-bound GPS sample, accuracy, device timestamp, server receipt time and monotonic sequence. Discovery availability can expire or go offline independently of active-mission tracking. Completion, cancellation, release and reassignment clear the mission location. Clients never have raw-table GPS access.

The authenticated courier Edge handler derives the rider account from the bearer session. The publishing RPC is service-only and rechecks approved, unsuspended partner membership and mission assignment. Customer and Merchant projections enforce ownership and active branch permissions on each fetch. Broadcasts contain only an order identifier and invalidation sequence, not coordinates, PINs or new push-notification intents.

## Location and proximity contract

- Native client: continuous Core Location only while assigned an active mission; at most one upload every 8 seconds, no route buffer.
- Server: accepts finite coordinates, accuracy 0–200 metres, no sample older than 60 seconds or more than 5 seconds into the future; ignores older/replayed samples and throttles accepted updates to at most one per 2 seconds.
- Live/arrival freshness: expires 30 seconds after the earlier device/receipt timestamp.
- Arrival: requires a fresh sample with horizontal accuracy at most 35 metres and geodesic distance at most 50 metres to the applicable merchant/customer destination.
- Both arrival buttons fail closed when eligibility expires, even without another network response. Database triggers enforce the same conditions for alternate command paths and old clients.
- Known stale/inaccurate locations are labelled delayed/last-known, not live. The existing reconnect loops and 30-second fallback order polling remain in place.

GPS is evidence supplied by the authenticated assigned device, not cryptographic proof of physical presence. This implementation does not claim to detect deliberate OS-level GPS spoofing.

## iOS background behavior

Tracking is owned by the authenticated Customer/Delivery Partner root, not a delivery card or tab. Switching to Customer mode or opening Apple Maps does not intentionally stop an assigned mission. Logout, loss of assignment or mission completion stops location updates. Only the Customer/Partner binary enables `UIBackgroundModes=location`; Merchant and Admin do not gain background tracking permission.

The app requests When In Use permission, enables background updates with the visible iOS location indicator after the mission starts, disables automatic location pausing, and gives each authenticated upload a bounded background task. Precise Location is needed to become arrival-eligible. No Always permission or continuous tracking outside an assigned mission is requested.

Force quit, revoked permission, an OS termination, missing GPS or no network can interrupt tracking. Consumers expire the location as stale instead of claiming uninterrupted tracking. Reopening the app reconciles the assigned mission. These OS/device behaviors require physical-device acceptance testing before a broad production rollout; none was performed in this task, per the owner's restriction.

The browser fallback reports location while its mission tab can execute. It explicitly directs riders to the iOS app for background tracking; it does not promise background browser execution.

## Final handoff

1. `ARRIVE_CUSTOMER`: fresh server-checked GPS within 50 metres; mission becomes ARRIVED.
2. `VERIFY_CUSTOMER_PIN`: six-digit in-app PIN, existing digest verification, attempt limit and idempotency. Records an immutable verified timestamp/actor without completing delivery.
3. `ADD_DELIVERY_EVIDENCE`: an immutable package photo after the verified PIN, covering all required packages.
4. Existing pay-at-delivery collection command: only after the photo; failed attempts can be retried. Existing successful collection and balanced fee accounting remain unchanged.
5. `COMPLETE_DELIVERY`: only after all prerequisites. Original completion/custody/outbox logic executes exactly once.

Customer PIN is visible before payment and retired from the UI after verification. The old VERIFY_DELIVERY command cannot bypass the new prerequisites. Existing separately authorized Operations recovery is not redesigned.

## Verification

Directly run in this task:

- Local database regression suite: 63 files, 1,736 checks passed.
- New database fixture: 57 checks for real PIN/photo/payment/completion commands, idempotency, custody, foreign-rider rejection, stale/invalid GPS, 49/51-metre customer and merchant boundaries, merchant revocation, and location cleanup.
- Courier Edge handler: 23 tests passed; Deno type check passed.
- Shared Swift UI package: 75 tests passed, including freshness, arrival expiry and mission payload tests.
- Web: 263 tests passed, TypeScript/Vite build passed, ESLint passed.
- Generic-device Debug builds: Dastak (Customer + Delivery Partner), DastakMerchant and DastakAdmin passed; no app was launched.
- Unsigned generic-device Release archives: Dastak and DastakMerchant build 3 passed. These require the selected distribution/signing channel before they can update installed apps.
- Linked production migration dry run: only `20260908201530_live_delivery_tracking_and_ordered_handoff.sql` pending.
- All four existing web role/project and production configuration checks passed.

No browser, simulator or iPhone runtime tests were run. No live order, stock, payment or assignment was changed as a test.

## Production activation — 9 September 2026

The owner confirmed that native apps are installed through Xcode. A read-only production preflight found **zero active orders and zero active delivery missions**. The release was activated with no in-progress deliveries to interrupt; no order was cancelled or modified for the rollout.

**Install Dastak and DastakMerchant build 3 before starting a new delivery.** Build 2 lacks the mission GPS publisher and separate PIN command and cannot satisfy the new server gates. No remote native install is implied by these deployments. The unsigned archives are build evidence, not installable distribution packages.

- Source commit: `01852318958a10e3f658910c5e6608d17e89bf30`, pushed to `codex/dastak-v1-launch`.
- Production migration `20260908201530` applied; the subsequent linked dry run reported the remote database up to date.
- `courier-dispatch` deployed as version 24, ACTIVE, with `verify_jwt=true` unchanged. Anonymous POST returned 401; OPTIONS returned 204.
- Production read-only checks confirmed the new arrival/consumption/cleanup triggers enabled, no authenticated-client execute permission on the GPS-writing RPC, no raw GPS table read permission, and service-role execute permission present.
- Customer and Delivery web were built as staged production artifacts, then promoted after the database/API rollout. Merchant and Admin web were also deployed. All four Vite deployments were verified READY with the exact source commit metadata.
- The four public production URLs returned HTTP 200. Customer/Delivery canonical URLs were also resolved through the deployment API to the exact new deployment IDs; protected team-scoped aliases were not mistaken for the public URLs. These are HTTP/release checks, not browser or authenticated order-flow tests.

| Web app | Production URL | Deployment |
| --- | --- | --- |
| Customer | https://dastak-customer.vercel.app | `dpl_CXCKKDKCCY1eeogenBLwzu4bZmiE` |
| Delivery Partner | https://dastak-delivery.vercel.app | `dpl_21HhzaGgh9BgcGTUk4qeFki91cZ2` |
| Merchant | https://dastak-merchant.vercel.app | `dpl_5oXkoJ5Z2iNs4cBG9QyGiuzPh4y6` |
| Admin | https://dastak-admin.vercel.app | `dpl_BuQmwU3io2zrsdLtUH1A2KkDoxkX` |

Open `SavariDastak.xcworkspace` from this worktree in Xcode. Install the `Dastak` scheme for Customer and Delivery Partner, and `DastakMerchant` for Merchant. Both are version 1.0.0, build 3.

With owner authorization, the remaining device acceptance gate is assignment, Maps navigation, background/lock screen, weak GPS, reconnect, merchant/customer tracking, 50-metre arrival, the complete handoff, and notification behavior. These runtime checks were deliberately not performed; successful compilation and server tests are not a substitute for physical-device acceptance.

If activation causes a problem, do not remove verification records, reset order states, or revert consumed payment/custody history. Keep gates fail-closed and fix forward; use existing Operations recovery for affected missions.
