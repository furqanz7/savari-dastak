# Merchant Earnings / Royalty — native read workspace

18 October 2026. M-06 read-only follow-up to the [Merchant completion audit](dastak-merchant-completion-audit-2026-10-18.md). Not a live financial acceptance or Merchant release sign-off.

**Later follow-up:** [Native financial setup, withdrawal and retry controls](dastak-merchant-payout-controls-implementation-2026-10-18.md) now adds the local financial controls, protected recovery, a new capability snapshot and additive checked-withdrawal guard. The original read-only slice and its results below are historical, not a statement that these controls remain absent from current source. New migration/earnings activation, provider availability and financial/device acceptance remain separate.

## Scope

- Solo implementation in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`.
- Existing Merchant reliability/location/detail changes and unrelated Customer screenshot fixtures, release documents and artwork were preserved. The existing Xcode-generated dependency-lockfile change was left untouched.
- Added a native Earnings tab, typed Merchant Royalty read client, bounded model, display helpers and tests. No Customer/Delivery source or web/backend contract was modified by this slice. The older History aggregate is now labelled “Earlier order totals”, with a note distinguishing it from the Royalty ledger.
- No migration, production query, deployment, push/commit, Apple change, installation, real payout, destination registration, withdrawal or provider activation.

## Implemented

### Business context, not store or rider earnings

The native workspace reads the existing `earnings` Edge Function using only `{"operation":"merchantRoyaltySnapshot"}`. It does not send an actor ID, organization override or store filter. The existing backend authenticates the bearer, supplies the authenticated account to `dastak_v1_get_royalty_snapshot`, and checks `merchant.earnings.read` for each merchant organization. Server authorization—not a client-side organization picker—is the access boundary.

The separate typed `DastakMerchantRoyalty` contract rejects Rider subjects, duplicate organizations, negative available/owed/lifetime amounts, inconsistent per-organization balance splits, inconsistent aggregate sums, overflow, invalid destination versions and malformed withdrawal statuses. Merchant organization IDs are not required to equal the signed-in person's account ID. Multiple businesses may be authorized, and one positive business balance does not net away a different business's amount owed.

The screen deliberately has no selected-store header. It explains that the ledger is organization-wide, across stores. When more than one business is returned, an organization selector limits the visible account sections; the summary remains explicitly all authorized businesses. The current API does not supply organization display names, so additional accounts use a short ID with the full ID selectable beneath—not invented names or another branch-name field.

### Display and navigation

- Dedicated Earnings tab between Store and Account.
- Available-balance card, lifetime earned, amount owed and per-business ledger balances.
- Search by ledger type/reason, entry ID or order UUID; All, Credits and Adjustments views. Adjustment records are shown as a subset, never added again to the balance.
- Signed credits/deductions, readable reasons and timestamps, expandable order/fulfilment/refund/withdrawal references where supplied.
- Payout history with requested/processing/paid/failed/reversed status, requested/paid/failure timestamps where available, masked destination and reconciliation state. A requested/processing record is not described as a bank receipt.
- Progressive display of loaded activity and payouts. The existing snapshot API returns arrays, not a pagination/completeness contract; “Show more” expands those loaded arrays only.
- Semantic/adaptive light/dark surfaces, a restrained gold balance card, layouts that stack values at larger widths/text requirements, selectable references, a larger-text summary layout and 44-point refresh/show-more controls. No new decorative bitmap assets or fabricated earnings charts.

### Availability, privacy and reliability

Missing payout availability is unknown, not active. Positive balance alone does not imply withdrawal permission. Existing masked destination, server setup/withdrawal availability and `canWithdraw` are presented independently. No private provider metadata, bank account number or customer address is retained in the DTO.

Reads have an overall 12-second deadline, including account checks before/after the request, plus the existing bounded Merchant transport. Concurrent refresh calls coalesce. Generation checks and cancellation prevent an invalidated/old read publishing later. Background/disappearance invalidates current status; foreground/visible entry and the periodic loop refresh the view. Manual retry and pull-to-refresh are available.

Transient failure retains only a labelled last-known read-only snapshot and timestamp. Denied/authentication/account-change reads clear amounts, timestamp and organization selection. An unavailable balance is not presented as zero. No snapshot is persisted to disk, and no payout command can be issued by this client/model/view.

## Deliberately still pending

This slice completes the **native read workspace**, not all possible financial actions in M-06:

- Native destination setup/change, withdrawal requests and payout retry are not built. They remain in the existing Merchant web workspace. Implementing them requires separately scoped Merchant-organization command storage/reconciliation, masked-data handling, exact immutable request replay and explicit fresh permissions/availability. The Rider payout model was not relabelled or reused as Merchant authority.
- No RazorpayX/provider configuration, billing, destination or real money movement was activated or tested. No claim is made about current live provider availability.
- Live role/organization-permission acceptance, signed-in endpoint results, bank reconciliation, simulator appearance/VoiceOver and physical iPhone/iPad testing remain separate as requested.
- Existing full-order migration/Edge activation from M-05 remains separate and unperformed; this Earnings read uses a different existing endpoint and creates no new migration/deployment requirement itself.
- The remaining Merchant completion-audit items are not marked done by this slice.

## Local verification

Seventeen added tests cover:

1. Merchant organizations distinct from Rider IDs; aggregate available and owed balances kept separate.
2. Wrong subject kind, duplicate organizations, currency/money/aggregate/destination/withdrawal/entry rejection.
3. Empty/overflowed snapshots fail without trapping.
4. Unknown bank/provider/customer extras are not retained.
5. Missing payout availability remains unknown.
6. Exact Merchant read request with no actor, organization or payout payload.
7. Offline stale retention and successful refresh recovery.
8. Denial clears sensitive presentation and selection.
9. Invalid reply cannot replace a validated snapshot.
10. Concurrent refresh coalescing.
11. Account change during a read cannot publish data.
12. Cached balances cannot be reused by a changed account.
13. Invalidation releases loading and rejects old late replies.
14. Uncooperative dependency times out and the next refresh works.
15. Organization selection is display-only and resets when an organization disappears.
16. Ledger filters/search and adjustment subset handling.
17. Payout availability/eligibility not inferred from positive money.

Focused result: **17 tests passed, zero failures**. Existing backend earnings suite: **30 passed, zero failures**. These use local controlled fixtures, not live financial operations.

Final results:

| Check | Result | Boundary |
| --- | --- | --- |
| Full DastakUI package | 610 passed, zero failures | macOS-hosted package/model tests, including all 17 new Earnings tests; not native interaction acceptance |
| Full MarketplaceInfrastructure package | 189 passed, zero failures | Existing infrastructure regression suite |
| Backend earnings function tests | 30 passed, zero failures | Existing authenticated routing/availability/provider-handler fixtures; no live requests |
| Merchant Debug generic iOS Simulator build | BUILD SUCCEEDED, signing disabled | arm64/x86_64 Simulator compilation; not an installed-device or visual pass |
| `git diff --check` and final branch/HEAD guard | Passed | No whitespace errors; branch/HEAD unchanged |

The build retains existing warnings in Customer/account haptics and Account Sessions actor-isolation code. Those unrelated sources were not edited. Web source was not changed in this slice, so the preceding web-suite result is not presented as a fresh run here.

Local logs:

- `/tmp/dastak-merchant-earnings-focused.log`
- `/tmp/dastak-merchant-earnings-ui-full.log`
- `/tmp/dastak-merchant-earnings-infra.log`
- `/tmp/dastak-merchant-earnings-edge.log`
- `/tmp/dastak-merchant-earnings-ios.log`
