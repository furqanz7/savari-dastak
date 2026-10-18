# Merchant active fulfilments and paged history

18 October 2026. Local M-10 follow-up to the [Merchant completion audit](dastak-merchant-completion-audit-2026-10-18.md).

## Scope

Solo implementation in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`. Earlier local Merchant work, Customer fixture changes, artwork, release evidence and the generated dependency-lockfile change were preserved.

No commit/push, production migration/database access, Edge deployment, Apple change, installation or real account/order/payment/payout mutation. Signed-in/device acceptance remains separate.

## Implemented

### Active work is independent of the recent-history cap

The new migration replaces the current `list_merchant_fulfilments` definition without changing its arguments or four response collections. The original September migration is unchanged.

- All authorized non-historical active fulfilments are selected independently of recent completed records. The active set has no shared row cap, so completed commitments cannot displace an older active fulfilment.
- The historical portion of the existing feed retains its caller-selected 1–100 bound for compatibility; it is not treated as complete history.
- Existing Merchant operational projections, actor checks and per-branch `merchant.fulfilment.manage` permission remain authoritative.
- Recovery opportunities, return receipts and settlements are unchanged, including existing guarded receipt-code behaviour. The local SQL test compares these three outputs with the preceding definition.
- The active response is not cost-free for arbitrarily large datasets. Clients still have bounded request deadlines; failure remains unknown/stale rather than empty. No production-volume performance claim is made.

Native now explicitly classifies fulfilment `COMPLETED` and `RELEASED` as history, even if the parent order is not terminal. Existing terminal-order rules match web. Historical cards distinguish order status from fulfilment status.

### Branch-authorized history cursor

New Edge operation `merchantFulfilmentHistory` calls public invoker RPC `dastak_v1_merchant_fulfilment_history`, delegating to an API-schema definer function with empty search path.

- Required branch, authenticated actor and managed-fulfilment permission. No caller-provided actor override or Customer order authority.
- Paired commitment timestamp/UUID cursor, descending order, default page 50 and maximum 100. One extra candidate determines continuation; the cursor identifies the last returned row.
- Cursor strings preserve timestamp precision rather than round-tripping through client Date conversion.
- Branch/timestamp/UUID index supports history access. Response includes branch ID, rows and explicit nullable next cursor. Missing continuation metadata is invalid, not proof of exhaustion.
- Authenticated execute grants only. No anon/service-role execute or direct table privileges were added. Existing list-function ACLs remain unchanged by replacement.

The Supabase/Postgres skills influenced actor/branch checks, privilege separation, indexed keyset paging and isolated SQL verification. The React skill influenced independent state, request cancellation, stable row keys and truthful conditional rendering. Current reference: [Supabase database functions](https://supabase.com/docs/guides/database/functions).

### Native and web history

Both Merchant desks load fulfilment history separately for the selected location, with **Load older orders**, **Refresh history**, loaded/checked state and independent errors.

- History cards are read-only and open the earlier Merchant-safe full-order detail view. No Ready, package, payment or receipt-code controls are presented on history cards.
- Older pages append and deduplicate by fulfilment ID. Explicit refresh restarts at the newest commitments and includes newly finished orders.
- Paging owns no mutation/journal lease. Concurrent reads coalesce; request deadlines remain bounded.
- Native checks identity before and after the whole read within one deadline. Authentication/access/account-change failures clear retained rows. A transient failure may retain labelled read-only records; refresh is required before continuing after failure.
- Web aborts/ignores the previous keyed account/location read. Denied access/session clears retained rows; transport failure is not displayed as empty history.
- Native uses lazy history rows. Web no longer presents the bounded recent-feed history count as a complete historical total.
- Earlier legacy orders, return/recovery and settlement records stay separate. Legacy history is explicitly labelled as a recent window.

## Local verification

Added 7 native tests, 11 web tests and 3 Edge tests for authority/cursor preservation, explicit COMPLETED classification, malformed/foreign/duplicate/missing-continuation pages, append/dedup/reset, read-only detail navigation, transient failure versus denial, account/location isolation, coalescing and non-cooperative native timeout recovery.

The isolated Unix-socket SQL fixture executes the actual old list definition and new migration against minimal tables and stubbed predecessor auth/projection helpers. It proves:

- An old active fulfilment remains visible behind more than 100 newer historical rows, even when the requested historical limit is one.
- All 151 historical rows are reached across five 37-row pages; equal timestamps do not skip or duplicate IDs.
- Six fractional timestamp digits survive the cursor.
- COMPLETED/RELEASED and terminal-parent classification agree.
- Recovery/return/settlement outputs are unchanged.
- Foreign branches, respond-only actors, forged actors, partial cursors and invalid limits are rejected.
- Function grants and authenticated public-wrapper execution work.

This is **not** a full empty-database migration-chain rebuild, integration verification of every historical projection, a production advisor run, live load test or device acceptance.

| Check | Result |
| --- | --- |
| Full DastakUI hosted package | 662 tests, zero failures |
| Full Infrastructure hosted package | 189 tests, zero failures |
| Full web suite | 151 files / 1,084 tests, zero failures |
| Full Edge fixture suite | 376 tests, zero failures |
| Isolated actual-migration SQL fixture | Passed |
| Web TypeScript/production build | Passed; existing large-chunk warning remains |
| New history React component/test lint | Passed |
| Merchant generic iOS Simulator Debug build | BUILD SUCCEEDED, signing disabled |
| Whitespace and branch/HEAD checks | Passed; guard unchanged |

The first native compile caught an incorrect new-view line identifier; the first new web tests used an incomplete product fixture. Both were corrected before passing final verification, without weakening validation.

Logs: `/tmp/dastak-merchant-history-ui-final.log`, `/tmp/dastak-merchant-history-infra.log`, `/tmp/dastak-merchant-history-web-final.log`, `/tmp/dastak-merchant-history-edge-all.log`, `/tmp/dastak-merchant-history-sql.log`, `/tmp/dastak-merchant-history-web-build-final.log`, `/tmp/dastak-merchant-history-ios-final.log`, `/tmp/dastak-merchant-history-eslint.log`.

## Activation and remaining boundaries

1. New migration `20261018014110_merchant_active_and_paged_history.sql` and updated orders Edge handler require separately authorized production application/deployment. The new read will fail visibly against an old endpoint rather than silently falling back to the recent window.
2. Earlier M-05 detail migration/Edge activation remains independently required for its detail contract. Neither was activated here.
3. Signed-in device, accessibility/large-text, multi-role, multi-location, reconnect and production-volume acceptance remain separate.
4. Pages are live reads, not a frozen audit snapshot. Terminal membership can change between requests; refresh restarts discovery. Commitment time—not completion time—is the sort order.
5. Incoming-offer and authorized-location discovery retain their existing contracts. A historical-only location missing from current location discovery is not made discoverable merely because a known branch ID supports history reads.
6. Legacy account-wide history stays explicitly bounded. Complete catalogue search beyond 5,000 loaded SKUs, native payout actions, broader group/menu editing and other audit items are not completed by M-10.
