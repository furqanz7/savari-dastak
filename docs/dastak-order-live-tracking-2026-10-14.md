# Customer Live Activity tracking — 14 October 2026

## Build 32 correction — 15 October: preserve Preparing before assignment

- Corrected Build 30's overly broad rule: missing rider alone no longer replaces Preparing. Server helper requires a confirmed order, at least one active fulfilment, every active fulfilment actually READY, and no assigned active rider. Partial preparation stays Preparing. Assignment ends when a rider is attached; already-assigned orders do not fabricate a waiting stage.
- Native order title, message, symbol, journey label, active-order strip and timeline use the server fulfilment presentation state. Foreground Live Activity uses the same readiness signal. Assignment no longer displays a running preparation ETA.
- Applied only `20261014195708_preserve_preparation_before_rider_assignment`, with exact production-function hash guards and atomic history recording. Preserved actor/session checks, empty search paths, current grants and the order/payment state machine. Order JSON keeps existing preparation metadata while adding the ready-and-waiting presentation.
- Disabled the early `DELIVERY_MISSION_CREATED` assignment alert. A deferred fulfilment Ready trigger emits one durable `RIDER_ASSIGNMENT_PENDING` event only when the complete active order is ready and waiting. It serializes final readiness checks by order and uses event-key deduplication. The Customer route uses the existing notification worker. No historical replay.
- Local PostgreSQL fixture verifies preparation is not skipped, partial readiness emits no assignment, complete readiness produces one notification and matching UI/Live Activity states, rider assignment/reassignment, preconfirmation and terminal guards, ownership/session/lease protection, and metadata preservation. DastakLiveTracking 6 and DastakUI 478 tests pass. Fixture cluster stopped.
- Production verification confirms readiness-based order/activity projections, migration entry, early alert disabled, new alert enabled and deferred trigger present. Direct authenticated access to the helper is denied. Before/after advisors show the same six existing unrelated warnings, with none naming the new helper/trigger.
- Simulator and signed device Build 32 succeed; signature verification and diff checks pass. Includes Build 31 checkout contrast/canvas corrections. Simulator installed/launched. Physical install and visual checks remain pending: iPhone unavailable and Device Hub cannot find the locked Mac window. Existing unlock/reconnect questions remain pending. Real-order testing remains deferred by user direction.

## Build 30 revision — 15 October: Assigning your rider

- Added `ASSIGNING_RIDER` as a customer presentation state for confirmed `PAID`/`PREPARING` orders without an assigned active rider. The shared projection drives the native order card, active-order strip, journey label, timeline and foreground Live Activity. Assigned, pickup, arrival, terminal and unconfirmed orders retain their correct states. Preparation continues while assignment is pending.
- Added matching Live Activity title, detail, person/clock symbol and compact label; calling stays unavailable until the last-mile stages. Grocery and Food preview states verified; actual Food Lock Screen screenshot: `/tmp/dastak-tracking30-assigning-food.png`.
- Applied only migration `20261014192213_live_activity_assigning_rider`, guarded against production-function drift and recorded atomically. Background worker projection now publishes assignment/reassignment status changes without an order-version change. Added the existing `DELIVERY_MISSION_CREATED` event's Customer notification route, titled “Assigning your rider”, for iOS and web. No historical replay or new order/payment state, trigger or Edge deployment.
- Production verification confirms assignment projection active, migration recorded, notification title/platform installed, authenticated callers denied and service-role worker allowed. Advisor command was attempted but its temporary database-role connection failed; the query/privilege verification completed through the linked management query path.
- DastakUI 478 tests, DastakLiveTracking 6 tests and APNs payload/worker 5 tests pass. Isolated PostgreSQL fixture passes assignment, reassignment, assigned-rider exit, preconfirmation guard, arrival, cancellation, session, ownership and lease checks plus notification route registration. Local fixture cluster stopped after tests.
- Simulator and signed iPhone builds pass; signature verification and diff whitespace checks pass. Build 30 installed, independently queried as version 30, and launched on the physical iPhone (container `58DD3B81-3A8F-49AF-A789-402E7C0EBB3E`). Real-order APNs delivery remains pending by user direction.

## Build 29 revision — 15 October: Lock Screen clipping and one destination door

- User screenshots showed the brand header and Call rider/footer clipped. The prior four-row card exceeded the system's 160-point Live Activity limit. Moved the call link into the status row, reduced spacing and margins, and made the order reference a small separate line. The actual simulator Lock Screen now shows the full header, status, Call rider, journey and reference. Evidence: `/tmp/dastak-tracking29-onway.png`.
- The journey uses one fixed destination door in every state. Arrival highlights that same door and fades the travelling badge; it no longer changes a house to a door while showing another door beside it. Shared arrival card visually verified with one door. Route coordinates now align the progress line and courier with the destination centre.
- Shared rendering covers Grocery and Food; the debug preview accepts `-DastakFoodTrackingPreview` for Food samples. No activity payload, calling guard, server status projection or production data changes.
- DastakLiveTracking's 5 tests pass. Simulator and signed device builds succeed; deep/strict signature verification passes. Build 29 installed on the physical iPhone in container `9ECA8D13-06F4-4531-A265-CAF3A9D6D9F1`, independently queried as bundle version 29, then launched successfully.
- Actual expanded Dynamic Island visual recheck remains pending because Device Hub coordinate input is unavailable; actual Lock Screen on-the-way and shared arrival rendering are verified. Real-order and call-through checks remain pending by user direction.

## Build 28 revision: journey, rider contact and arrival

- Replaced the bicycle and five-segment bar with a scooter journey between a store/food pickup and doorstep, gold-to-mint progression, a distinct arrival door symbol, and reduced-motion-aware 1.2-second milestone transitions. These are status transitions, not continuous motion or simulated GPS.
- Added Call rider to expanded Dynamic Island and Lock Screen while on the way/arrived. The link carries only an order UUID, opens the authenticated app, fetches the latest authorized order, checks current delivery status/contact, and asks for confirmation before opening the phone app. No phone number is placed in ActivityKit payloads.
- Root cause: the previous activity projection read only order.status. Rider arrival lives in delivery_missions.status while the order remains OUT_FOR_DELIVERY. Both foreground and background now project RIDER_ARRIVED without changing the order state machine.
- With explicit approval “Apply the tracking fix”, applied only migration `20261014121929_live_activity_rider_arrival` atomically with its history entry. Verified production function includes arrival handling, authenticated clients cannot execute it, and service_role can. Existing unrelated pending migration remains untouched. No Edge Function redeployment was required: the existing worker passes the presentation status through.
- PostgreSQL fixture passes mission-only arrival (unchanged order version), arrival deduplication, cancellation after arrival, lease/token generation, ownership and session checks. Local fixture cluster stopped after verification.
- DastakLiveTracking 5 tests, DastakUI 477 tests and APNs payload/worker 4 tests pass. Final simulator and signed device builds succeed; deep/strict signature verification and diff whitespace check pass.
- Final Build 28 installed on the physical iPhone (container 471DFE8C-6C86-4990-A904-2CF10BB81D37), launched successfully, and installed bundle version 28 independently queried. This includes the expanded-Island clipping correction: Call rider now sits beside the status and the extra footer is removed.
- Visually checked shared card preparation/on-the-way/arrival, compact system Island, expanded system Island before final clipping correction, and actual stale Lock Screen. Latest simulator compact Island shows basket and scooter. Final expanded-layout visual recheck remains pending: Device Hub long-press input reports no available window in both full and compact windows, although semantic controls and screenshots work. End sample succeeded and disappearance from the system Island was visually confirmed. No calls or production orders were created. Real-order APNs and call-through checks remain pending by user direction.

Build 28 logs: `/tmp/dastak-tracking28-{tests,ui-tests,db,backend,sim-final,device-final}.log`.

## Delivered

- Native ActivityKit/WidgetKit tracking for Grocery and Food. Basket/cutlery service icons, dark green and gold Lock Screen card, compact/minimal/expanded Dynamic Island, five-stage order progress, status text and symbol transitions, order deep link, stale-state messaging and terminal handling.
- The widget carries order number and status, not customer addresses or phone numbers. No fabricated ETA or continuously looping animation.
- Foreground order synchronization with account scoping, monotonic version handling, up to two activities, token registration/retry and local teardown.
- Private server registrations with ownership/session validation, token-generation and lease guards, bounded APNs batches, retry and terminal retirement. Existing alert delivery is isolated from Live Activity worker failures.

## Production activation

Explicit user approval: “Activate background tracking”.

- Applied only `20261014111434_customer_order_live_activities` atomically with migration history to project `zmtsolkfxlrxepshnjdf`.
- Left unrelated pending migration `20260929191745` unapplied.
- `register-order-live-activity` version 1 ACTIVE, JWT verification enabled. Unauthenticated HTTP request returns 401.
- `process-v1-outbox` version 12 ACTIVE; existing secret-protected worker remains on its existing schedule.
- Verified RLS, no anon/authenticated table access or registration-RPC execution, service-role registration execution, zero initial registrations.
- Existing outbox cron active on `* * * * *`; recent cron submissions succeeded. Recent pg_net HTTP responses returned 200, but those aggregated responses alone are not proof of ActivityKit APNs delivery.
- Production advisors reported no findings naming the new objects. Six unrelated warnings remain: five pre-existing public SECURITY DEFINER RPCs and disabled leaked-password protection. Not changed in this scope.
- No production order, payment or sample registration created. No real APNs token delivery test performed.

## Build and tests

- DastakUI: 477 tests passed.
- DastakLiveTracking: 3 tests passed.
- Targeted backend suite: 22 tests passed; Deno checks passed.
- Isolated PostgreSQL tests passed for ownership, client privileges, lease exclusion, token rotation, cancellation, heartbeat deduplication and session expiry/revocation. Dedicated local cluster stopped after tests, files retained.
- Final simulator and signed physical-device Debug builds succeeded; deep/strict codesign verification passed.
- Final Build 27 installed and launched on the physical iPhone. Latest installation container: `3C360DD2-E4BF-4DDC-A8A8-98C3736321D1`. Installed version 27 was independently queried before final widget-margin-only reinstall.

## Visual verification and remaining gates

- Local-only synthetic activity rendered through actual ActivityKit: compact Dynamic Island, expanded Dynamic Island, actual Lock Screen card.
- Observed preparation, pickup and on-the-way changes in shared card; actual Lock Screen pickup state and stale state verified.
- Lock Screen screenshot: `/tmp/dastak-live-tracking-lock-screen.png`.
- Expanded Island initially had footer too near rounded corners. Added horizontal footer inset and bottom padding; both builds passed. Final visual recheck after that edit remains pending because Device Hub coordinate input/capture became unreliable.
- Sample uses `pushType: nil`, no account/order API. Final End sample click was not confirmed due to capture failure; if still present, open the simulator preview and tap End sample. No screen recording was started.
- Physical iPhone 12 supports the Lock Screen experience, not Dynamic Island. Island checks used the iPhone 17 Pro simulator.
- Real-order end-to-end testing remains pending by user direction: authenticated token registration, server-to-APNs delivery while backgrounded, terminal retirement, and tap-through to a real order. Food-specific system rendering and final expanded footer check also remain to be confirmed.

## Evidence

Build/test logs live under `/tmp/dastak-live-tracking-{device,simulator,ui-tests,tests,backend-tests,backend-check,db-tests}.log`. Production function metadata and advisors snapshots are in `/tmp/dastak-live-tracking-functions.json` and `/tmp/dastak-live-tracking-production-advisors.json`.
