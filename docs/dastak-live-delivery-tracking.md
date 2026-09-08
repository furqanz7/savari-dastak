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

## Coordinated activation

**Do not activate strict backend gates while active riders still use an old native build.** Build 2 lacks the mission GPS publisher and separate PIN command. Applying these guards alone would make arrival or handoff unavailable to that build. This is a release-coordination dependency, not a need for a new order architecture.

1. Distribute Dastak and DastakMerchant build 3 through the owner's selected signing/install channel. Keep the backend unchanged until the updated riders are ready.
2. Prepare the affected web artifacts using `scripts/deploy-dastak-web.sh customer --staged-production` and the equivalent `delivery` command. This uses production configuration but leaves existing aliases unchanged. Record their returned deployment URLs and commit metadata.
3. In the agreed activation window, apply the reviewed migration with `supabase db push --linked` from `Backends/Dastak`, deploy only `courier-dispatch` with its existing JWT setting, and promote the exact staged web artifacts.
4. Re-run read-only migration/function/role checks. Do not create or mutate live orders as an unauthorized smoke test.
5. With owner authorization, exercise assignment, Maps navigation, background/lock screen, weak GPS, reconnect, merchant/customer tracking, 50-metre arrival, the complete handoff, and notification behavior on devices.

The production database and courier function are intentionally not marked deployed until native rollout readiness is confirmed. The repository currently has no configured TestFlight/App Store upload pipeline or Apple Distribution signing identity; generic builds alone do not update installed apps.

If activation causes a problem, do not remove verification records, reset order states, or revert consumed payment/custody history. Keep gates fail-closed and fix forward; use existing Operations recovery for affected missions.
