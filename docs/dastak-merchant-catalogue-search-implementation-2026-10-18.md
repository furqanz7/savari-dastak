# Merchant catalogue — useful search, storefront scope and truthful read state

18 October 2026. M-09 native follow-up to the [Merchant completion audit](dastak-merchant-completion-audit-2026-10-18.md). This completes the local loaded-catalogue UX slice, **not** the full-catalogue pagination/server-search gap.

**Later follow-up:** [Complete-catalogue and location discovery](dastak-merchant-discovery-implementation-2026-10-18.md) now adds separate authenticated server pages to native search, root My storefront and Browse complete catalogue. The capped category-preview snapshot remains unchanged. The report below preserves this earlier slice's scope/results; its pagination gap is no longer an unimplemented native source feature, but production activation and separate acceptance remain outstanding.

## Scope

- Solo work in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, baseline HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`.
- Continued earlier uncommitted Merchant work. Existing Customer screenshot fixtures, artwork/evidence/release documents and Xcode-generated dependency-lockfile change were preserved. Shared product-detail source changes are confined to its Merchant-specific page.
- Added native catalogue filtering/presentation and model-read state, plus regression tests. No backend/web contract or SQL change. No migration, deployment, push/commit, Apple change, installation, real account/catalogue/order/stock/payment/payout mutation.
- Supabase skill was used to retain authenticated Merchant transport and server permission/version boundaries. No new service key, authorization claim, RLS policy or direct-table access was introduced. Local filtering is navigation, not permission.

## Implemented

### Search and scope work on the normal browse-map route

- The All products / My storefront selector is shared above both map and taxonomy routes, rather than appearing only in the alternate taxonomy browser.
- Entering search always opens product results across **all loaded products in the chosen scope**, regardless of a previously open department/destination. Clearing search returns to the preceding navigation context.
- Matching covers product, brand, pack, variant, description, search terms and type/category/subcategory names/slugs. The map route no longer has a narrower name/brand/pack-only filter.
- My storefront opens selected products directly from either root, without first guessing a department. Within a destination it retains that destination's scope. Unsaved additions are included and unsaved removals excluded, using the same staged selection state as the cards.
- Map and taxonomy product lists use one filter. Map subcategory matches are resolved once per filter operation instead of revalidating the entire map for every product. A missing SKU type ID can fall back to its category's type ID for taxonomy filtering.
- Invalid or absent category navigation falls back to the existing directory plus search/scope controls; a catalogue without directory types can still show its loaded products. A taxonomy destination chosen while the map loads is not immediately replaced by the map on arrival.
- Search-result artwork receives priority prefetching. Scope/search changes do not save, delete or reset pending selections.

### Product-read state is independent of navigation-read state

Product and map requests run concurrently but their outcomes are handled independently. Verified products publish before a slow map finishes. A failed/invalid/unavailable map clears that navigation projection and shows fallback guidance without marking a successful product read failed. A failed product read does not become successful merely because the map loaded.

- Product and map progress have separate flags. Overlapping refreshes coalesce. Both reads are bounded; product identity-before/read/identity-after checks share one overall request deadline (12 seconds in the production model).
- Generation checks prevent an invalidated response reclaiming presentation. The product response must match the requested location, supported Store type and basic snapshot integrity. A successful read is tied to the verified account, not just a cached location UUID.
- Transient product failures may retain a labelled last-known catalogue and last-checked timestamp. Product currentness becomes false; stock, selection and operating-state mutations are blocked at both presentation and model guards until a successful refresh.
- Authentication/access/account-change failures clear the cached product presentation, timestamp and unsent selections; the original durable action journal is not deleted or replayed for another actor.
- The Merchant product-detail page uses the same currentness guard and explains why stock editing is paused. Navigation failure alone does not block otherwise authorized fresh product editing.

### Incomplete is not empty or complete

The UI shows loaded product count, last successful check, read failure/progress, navigation failure and a persistent partial-catalogue warning when `truncated` is true. Search/storefront counts are labelled as loaded results. Empty messages distinguish stale, truncated and storefront scope, rather than claiming no products exist or promising future approvals.

The current authenticated product read still requests at most **5,000 rows**. The warning explicitly says matching or selected products outside that loaded set may be absent. This change does not add a cursor, server search, a complete total, or a “load all” button that cannot actually load more rows.

### Pending selection safety

- A staged product omitted from a refreshed loaded set remains unknown, not acknowledged. Its pending change is retained, with a visible warning.
- Batch Save refuses to send a partial subset when any pending SKU is missing from the loaded catalogue. Refresh may restore it; Discard is an explicit alternative.
- Acknowledged selection writes clear only matching submitted staged changes. An operating-state save no longer discards unrelated staged product selections.
- The existing original actor/location/version/payload/key journal remains the mutation/recovery mechanism. No attempt was made to synthesize a successful save from missing data.

## Local verification

Added **22 tests** covering routing, broad search fields, global search versus prior category, staged storefront scope, shared map/taxonomy matching, type fallback, missing nodes, truthful empty messages, invalid duplicate snapshots, map failure/slow/missing/invalid results, stale product failure and recovery, denial/account/location isolation, non-cooperative timeouts, coalescing, omitted staged products, fresh acknowledgements and preservation of staged selections across operating-state changes.

The first editing-availability test setup had not restored the protective command journal; it was corrected to match the normal workspace sequence. The corrected 22-test run passes without bypassing those editing guards.

Final verification after all source changes:

| Check | Result | Boundary |
| --- | --- | --- |
| Full DastakUI package | 655 tests passed, zero failures | Includes all 22 new catalogue tests; macOS-hosted package/model tests, not native tap-through |
| Full Infrastructure package | 189 passed, zero failures | Existing infrastructure regression suite |
| Existing catalogue Edge tests | 32 passed, zero failures | Controlled handler fixtures; no live catalogue mutations |
| Focused existing web regressions | 4 files / 58 passed, zero failures | Store correctness, operations, browse-map and V1 transport; web source unchanged |
| Merchant Debug generic iOS Simulator build | BUILD SUCCEEDED, exit 0, signing disabled | Actual SwiftUI compilation for arm64/x86_64 Simulator, not installed-device or visual acceptance |
| `git diff --check` and branch/HEAD guard | Passed | No whitespace errors; branch and HEAD unchanged |

No live Supabase query or production stock/selection write was used as verification. Existing unrelated haptics/account compiler warnings were not addressed by this slice.

Local logs:

- `/tmp/dastak-merchant-catalogue-tests-final.log`
- `/tmp/dastak-merchant-catalogue-ui-final.log`
- `/tmp/dastak-merchant-catalogue-infra.log`
- `/tmp/dastak-merchant-catalogue-edge.log`
- `/tmp/dastak-merchant-catalogue-web.log`
- `/tmp/dastak-merchant-catalogue-ios-verified.log`

## Still separate

- **Complete search/catalogue coverage beyond the cap remains pending:** needs an authorized pagination/server-search contract and matching clients. No complete-catalogue claim follows from a client-side filter.
- Physical iPhone/iPad/simulator appearance, keyboard, VoiceOver and signed-in multi-location/cross-role acceptance remain separate as requested. No installation was performed.
- M-10 active/history discovery and the remaining Merchant audit items are not completed here. The earlier M-05 detail migration/Edge activation remains unperformed independently; this slice adds no new migration or deployment requirement.
