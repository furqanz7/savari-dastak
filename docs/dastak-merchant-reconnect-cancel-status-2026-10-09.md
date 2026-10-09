# Merchant dispatch and cancelled Customer status

## Production evidence

Order DSK-261009-00000093 was CANCELLED_PREPAYMENT, version 3. Its Wave 1
evaluated an eligible, stocked Zuper branch at distance 0, but created zero
merchant opportunities (also confirmed by WAVE_1_STARTED outbox payload).
The reachability BEFORE INSERT trigger suppresses work when the branch heartbeat
is older than its configured 120 seconds. The Merchant shell stopped heartbeat
updates while hidden, and original Wave 1 dispatch never reconsidered a request
suppressed at startup after a merchant reconnected during the original window.

Separately, embedded Orders cancellation updated its own order detail, while the
Reimagined bottom status bar had an independent minute-long polling cycle.

## Fix

- Merchant shell heartbeats every 30 seconds while online, including hidden tabs;
  no overlapping heartbeat requests. Online/visibility resumption refreshes promptly.
- Merchant Orders feed reconciles immediately on visibility/online resumption.
- Private reconnect helper runs inside the existing authenticated heartbeat RPC.
  It locks at most 50 eligible parent orders with SKIP LOCKED, rechecks transport,
  exact inventory, capacity, branch permission and reachability, and creates only
  previously unoffered Wave 1 opportunities within their original open window.
- Existing reachability and emergency-pause triggers retain their final veto.
  No cancelled/expired/declined request is revived and no deadline is extended.
  Exact opportunity lines, audit entry and existing notification outbox event are
  committed atomically. No new exposed endpoint or grants; helper is private.
- Embedded V1 order snapshots now notify the parent. Known terminal orders hide
  their own active bar immediately and trigger fresh owned-order discovery.
  Cart contents and other active orders are not cleared. Legacy order kinds are
  not hidden by a canonical V1 cancellation with the same ID.

## Verification

- Real linked-schema BEGIN/ROLLBACK harness: synthetic actor/permissions, branch,
  stock, five order scenarios and matching attempts. Actual public Merchant feed
  returns the recovered pending offer; exact lines/outbox/deadline verified.
  Repeated heartbeat creates no duplicate. Closed stores, cancelled/expired orders
  and previously declined opportunities are excluded. Private grants remain denied.
- Frontend regressions cover hidden/background heartbeat, offline pause, prompt
  reconnect, no overlap, and immediate cancelled-bar removal with cart preservation.
- No real customer order was submitted or manually resent. Order 93 stays cancelled.
- Supabase security advisor ERROR scan reported no issues; not a claim about WARNs.
- Existing 30 km discovery, delivery-partner gate, fees, acceptance/idempotency and
  cancellation lifecycle remain unchanged. Browser/OS fully suspending a closed
  or offline app still expires real merchant reachability; no fake liveness added.
- Unrelated dirty docs/assets and pending catalogue activation are excluded.

Release identities and final verification are recorded after deployment.
