# Merchant location context — local implementation

18 October 2026. M-04 follow-up to the [completion audit](dastak-merchant-completion-audit-2026-10-18.md), building on the [first reliability slice](dastak-merchant-reliability-implementation-2026-10-18.md). This is not a Merchant release or live/device acceptance report.

**Later follow-up:** [Complete-catalogue and location discovery](dastak-merchant-discovery-implementation-2026-10-18.md) adds an authenticated directory of current-generation permitted locations, independent of recent orders/default probes, with paging and separately verified saved/journal focus. The old discovery remains only an explicitly limited fallback when the new directory is unavailable. Its migration/Edge activation and separate acceptance remain outstanding; the report below preserves the earlier implementation scope/results.

## Scope

- Solo work in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, `codex/dastak-v1-launch`, baseline HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`.
- Continued the preceding uncommitted Merchant changes. Existing unrelated Customer screenshot fixtures, release documents and untracked artwork were preserved.
- No backend contract, migration, database, web, Customer/Delivery behaviour, Apple listing, deployment or real order/payment was changed. The shared product-detail file was edited only within its Merchant-specific views.
- No commit/push, iPhone installation, signed-in runtime query or simulator visual test was performed.

## Implemented

### One selected location across Orders and Store

- A current-location header appears in Orders and Store. A single discovered location is selected automatically; multiple locations get a selector with confirmation before closing current editors.
- The display uses one customer-facing location name and a Grocery / Restaurant-Café service label. No new branch-name input or third naming field was added. Identical names/services receive a short ID suffix only in the selection menu for disambiguation.
- Incoming requests, held items, current/history fulfilments, recovery offers and return receipts are filtered to the same selected location, including their counts and empty-state checks.
- Restaurant versus retail Store routing follows the selected location's verified type, not the presence of any cached Restaurant menu. Reads explicitly request that location and reject a different returned ID or mismatched current-generation merchant type.
- Older Store tools remain an explicitly expanded **account-wide** section when earlier catalogue data exists; a current Store failure no longer silently presents another Store's settings as its fallback. Earlier orders remain explicitly account-wide. Settlement entries retain their existing organization-wide disclosure, because their contract is not a per-location ledger.

### Discovery, preference and authorization boundaries

- Reuses existing authenticated Merchant default catalogue and Restaurant-menu reads. Additional candidates come from accessible order/recovery/return feeds and the same account's stored selection.
- Store-management probes check the exact returned ID and merchant type. A stored preference alone cannot add an accessible location or grant management authority. Account-scoped UserDefaults stores only the selected UUID, not credentials or order data.
- Operational records can expose a location even when Store management is unavailable. Such a location is labelled **Orders · Store access not verified**; Orders remain usable under their normal fresh-feed/version guards, while Store editing stays unavailable.
- Candidate probes have at most four concurrent tasks and use the preceding slice's bounded production clients. Unknown/transient/access/session failures are visible; the selection list is not presented as complete.
- The existing APIs expose defaults plus candidates found in recent operational windows, not a complete all-authorized-locations directory. An inactive location absent from those windows and not the saved/default location may not be discoverable. Completing that directory needs a separately implemented authorized backend read; this slice does not claim it exists.
- A current selection is not silently changed to another Store during a failed refresh; cached location identity may remain as unverified navigation context, without claiming fresh Store access.
- Client filtering is navigation only. Existing authenticated endpoint/database actor and permission checks remain the security boundary; no privileged key, metadata-based authorization or new RLS policy was introduced.

### Saved actions and late replies

- The existing immutable journal retains its original location. A pending current-generation command takes priority when choosing the startup location, and switching stays disabled until it is resolved. If the original location cannot be discovered, another Store is not silently substituted for it.
- Unsaved retail batch selections must be saved or explicitly discarded before switching or refreshing location context.
- Explicit location changes invalidate old Store readers and clear location-specific Store data. Late Restaurant/catalogue replies cannot populate the newly selected location.
- Retail product-detail stock/add controls, store operating controls and new Restaurant menu-entry controls carry their editor's origin ID. Delayed actions with another origin are rejected, rather than rewritten for the newly selected location.
- Location discovery checks both actor identity and generation after its final awaited identity check. Account changes clear location/operational presentation without replaying or removing the original actor's recovery journal.
- Switching intentionally closes location-specific editors, with a warning. Same-location dirty-menu/version handling remains the separate M-08 task, not completed by this slice.

## Local verification

Added 14 location tests covering:

1. Automatic single-location selection without another name input.
2. Shared Orders/Store context and service routing.
3. Account-scoped preference restoration and re-verification.
4. Rejection of foreign stored candidates.
5. Blocking an old location's new order action after switching.
6. Original-location pinning and exact replay for a pending command.
7. Operational access during a Store-service outage without claiming management access.
8. Rejection of wrong-branch probe replies.
9. Retention of dirty retail selection batches.
10. Late Restaurant-read rejection after switching to retail.
11. Location clearing after account change.
12. Stable location and disabled stock writes during an outage.
13. Account change during in-flight discovery.
14. Origin-bound stock and new menu-entry controls.

The full DastakUI package passed **587 tests with zero failures**, including **120 Merchant tests** (14 new location tests). These are macOS-hosted package tests, not simulator UI or physical-device acceptance. The final Merchant native Debug iOS Simulator build, after all source/copy changes, returned **BUILD SUCCEEDED**, exit 0, with signing disabled. `git diff --check` passed. Logs are local ephemeral outputs:

- `/tmp/dastak-merchant-location-complete-ui.log`
- `/tmp/dastak-merchant-location-complete-ios.log`

## Still separate

Physical iPhone/iPad selection/editor/scroll/keyboard acceptance, signed-in multi-location permissions and notification navigation are not marked passed. No app was installed on the owner's phone. Complete location enumeration remains a backend-contract gap as described above. M-05 onward, including full Merchant order details on both platforms, is still pending.
