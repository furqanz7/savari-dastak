# Merchant complete-catalogue reads and authorized location directory

18 October 2026. Local M-04/M-09 follow-up to the [completion audit](dastak-merchant-completion-audit-2026-10-18.md). Completes the native paged-discovery implementation described here; **not production activation, device acceptance or Merchant release sign-off**.

## Scope and guard

- Solo work only in `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, unchanged HEAD `4d835cb0f411b2199fcd49c8499a4b3b40a5a801`.
- Earlier Merchant implementations and existing Customer screenshot fixtures, artwork, evidence, release documents and dependency-lockfile changes were preserved. No new Customer/Delivery UI or web implementation was made by this slice.
- Added one local migration, two operations in the existing catalogue Edge function, a typed native client, paged search/read state, directory integration and tests. No production database access, migration application, deployment, commit/push, physical-device installation, Apple change, real order/catalogue/stock write, upload, payment or payout.
- The Supabase and Postgres skills influenced the use of bearer-derived actor identity, narrow security-definer reads, explicit function grants, bounded keyset pages and the existing name/ID index. No service-role read or client-supplied account authority was added. See the official [database function guidance](https://supabase.com/docs/guides/database/functions) and [Edge authentication guidance](https://supabase.com/docs/guides/functions/auth).

## Complete-catalogue search and browsing

The capped metadata/category-preview snapshot remains unchanged. A **separate server-paged product read** now powers search, My storefront at the catalogue root and an explicit Browse complete catalogue action. Entering a query searches beyond the cached 5,000 products, regardless of an earlier selected category. Returning to the category directory preserves that navigation model.

- The server accepts a specific authorized retail location, optional product query, selected-only scope and complete `(name, SKU ID)` cursor. Native requests 100 rows per page; the server permits 1–250. The next cursor, not the result count or preview flag, determines whether more matching results remain.
- Matches include product name, variant, pack, description, brand, search aliases and taxonomy names. Prefix terms can span fields, such as a brand plus an alias. Queries are bounded to 80 characters; malformed/punctuation-only searches return explicit validation feedback rather than appearing as a successful empty catalogue.
- Active canonical products and this location's existing selections are eligible. An unrelated unselected draft is not exposed. My storefront is filtered on the server, not just within the first cached page; local staged additions/removals remain reflected separately.
- Each row retains current selection/version, stock/reserved quantity, prices, pack and taxonomy IDs. Only verified, rights-cleared primary/gallery image keys are projected. No fallback to an unlicensed raw image key was introduced.
- Result batches merge into the existing location cache so the established stock/selection editors can address products beyond the preview cap. Merging cannot downgrade a newer selection version or change the snapshot's `truncated` flag into a claim that the whole cache is complete.
- Query/scope/location/revision changes start a new cursor chain. A 300 ms UI debounce avoids issuing a request on every keystroke. The authenticated identity/read/identity sequence has an overall deadline (12 seconds in the normal model); request generations discard superseded, cancelled and late responses. Account changes between pages cannot mix actors.
- Failed pages invalidate editable search results and show retry guidance, without claiming no products exist or all results are loaded. Original journal ownership, mutation/version checks, staged selection protection and metadata freshness gates remain authoritative. Reads do not acknowledge or replay business actions.

**Deliberate boundary:** department/type/subcategory previews still use the labelled cached snapshot. They are not silently described as complete paged category lists. Search, root My storefront and Browse complete catalogue are the complete server-page routes. The web catalogue remains on its prior contract/UI; this native discovery slice does not claim web pagination parity. Pages are fresh reads, not a frozen multi-page database snapshot: concurrent catalogue changes can require a refresh.

## Authorized location directory

The new directory no longer depends on a store appearing in recent orders or being the default Store probe.

- The database enumerates locations for which the current actor has one or more current-generation catalogue, restaurant-menu, fulfilment or opportunity permissions. Existing active membership/organization, active Merchant bundle, branch/global scope and revocation checks remain in the established permission helper.
- Candidate organizations are restricted to the actor's active memberships before per-branch permission checks; the query does not run four probes against every store in the marketplace. Each native page contains up to 100 rows, ordered by UUID with a next-page cursor.
- The response contains only ID, customer-facing display name, merchant type and Store-management eligibility. No delivery/customer address, contact, PIN, private credentials or order contents are added.
- A separately authorized focused row can restore the current/saved/journal location even when it is beyond the first page. Saved preferences alone grant nothing. A revoked focused row is removed; it cannot survive solely because it appeared on an earlier page.
- Retail and Dastak Convenience Store locations route to retail Store; Restaurant/Café locations route to their menu. Order-only permission does not grant Store editing. Authorized closed locations can still be discovered; operating state is not confused with access.
- The location UI can load more and disclose whether more authorized rows remain. Manual Refresh locations restarts the directory and rechecks the focused location. This is not a new continuous organization-membership monitor.
- Directory access/session denial clears old location/Store presentation and does **not** revive operational cached IDs as verified access. A transient or not-yet-deployed directory can use the older probes only with a visible limited/incomplete-directory disclosure. Failure never establishes completeness. Each existing order/Store mutation still authorizes on the server.
- Account-scoped preferences, dirty selection guards, original-location journal pinning and in-flight generation checks are retained. Discovery does not send a saved command or overwrite its original actor, target, payload, key or version.

## Source and activation contract

- Migration: `Backends/Dastak/supabase/migrations/20261018131824_merchant_catalogue_and_location_pages.sql`.
- Private reads: `dastak_v1_api.merchant_inventory_page`, `dastak_v1_api.merchant_locations_page`; empty search path, authenticated actor assertion and explicit permissions.
- Public security-invoker wrappers: `dastak_v1_merchant_inventory_page` and `dastak_v1_merchant_locations_page`, deriving the actor from `auth.uid()`. Only authenticated execution is granted; anon/service-role execution is not added.
- Catalogue Edge operations: `merchantInventoryPage` and `merchantLocationsPage`, invoked with the caller's bearer token via the authenticated RPC path. Query/cursor/UUID/boolean/limit checks happen before SQL; a supplied account ID is ignored.
- Native transport: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/DastakMerchantDiscoveryClient.swift`; validates requested location, unique/bounded rows, cursor consistency and focused location identity.
- Native state: `DastakMerchantInventoryModel.swift`, `DastakMerchantModel.swift`, `DastakMerchantCatalogueView.swift`, `DastakMerchantLocation.swift`, `DastakMerchantLocationView.swift`.

All older migrations and public snapshot/page contracts remain unchanged. The old catalogue-page CTE correction already exists in `20260828200451_fix_giant_catalogue_page_cte_scope.sql`; this work does not misclassify that corrected function as broken or replace it.

**Not activated:** this migration and the updated `dastak-v1-catalogue` deployment are required before a distributed build can use the new reads against production. The earlier independent order-detail and active/history migrations/`dastak-v1-orders` activation remain pending as documented in their checkpoints. Do not install/distribute a new Merchant build and claim these backend features are live before their activation gates are completed.

## Local verification

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Full DastakUI package | **714 tests passed**, zero failures | macOS-hosted tests; includes 17 new discovery tests, not native touch acceptance |
| Full MarketplaceInfrastructure package | **189 passed**, zero failures | Transport/model regression suite |
| Full Edge test directory | **380 passed**, zero failures | Includes three new catalogue-operation tests; fixture requests, no live actions |
| Catalogue Edge entrypoint | `deno check` passed | Active handler/index type-check |
| Isolated SQL fixture | **Passed: 5,201 products and 151 quiet authorized locations** | Unix-socket-only disposable local database; no environment URL or hosted credentials |
| Merchant Debug generic iOS Simulator build | **BUILD SUCCEEDED**, signing disabled | Actual SwiftUI compilation for simulator; not installed-device interaction |
| Whitespace / branch / HEAD guard | Passed; unchanged | Existing unrelated dirty changes preserved |

The 17 native tests cover cursor continuation and rich fields; scope/query resets; wrong-location/duplicate/malformed replies; stale-response suppression; timeout/dismissal; overlong-query feedback; identity changes during reads and between pages; failed next-page currentness; quiet locations and saved focus beyond page one; denial clearing; focused permission loss; directory timeout/retry; explicitly limited unavailable-directory fallback; order-only access; original journal/location preservation; and stock-version non-downgrade.

`scripts/test-merchant-discovery.mjs` starts/stops its own local Postgres instance. The fixture loads the repository's original permission and prefix-query helper definitions plus the new migration into a minimal isolated schema. Assertions check unique complete product traversal beyond 5,000, selected-only/alias/cross-field/taxonomy search, stock/version/media fields, 151-location paging/focus, foreign scope denial, actor spoof rejection, invalid limits/cursors, role grants, membership/organization inactivity and permission revocation. **This verifies the new migration with those helpers; it is not a fresh rebuild of the entire backend migration chain, a hosted-schema integration pass or a production performance benchmark.**

Logs: `/tmp/dastak-merchant-discovery-ui-final.log`, `/tmp/dastak-merchant-discovery-native-extra.log`, `/tmp/dastak-merchant-discovery-infra.log`, `/tmp/dastak-merchant-discovery-edge-full.log`, `/tmp/dastak-merchant-discovery-edge-index.log`, `/tmp/dastak-merchant-discovery-sql.log`, `/tmp/dastak-merchant-discovery-ios.log`. Local SQL diagnostics are retained under the temporary path printed by that script; its server is stopped.

## Remaining independent work

Production integration/activation, signed-in multi-location/page/stock acceptance and iPhone/iPad/keyboard/VoiceOver checks remain separate. Broader category/group editing and persistent unsent menu drafts, native financial setup/withdrawal/retry parity, live notification acceptance and Merchant distribution retain their earlier status. This checkpoint closes neither those items nor the whole Merchant checklist.
