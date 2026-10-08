# Reimagined deep parity audit — 2026-10-08

Audited release: `b70f041` repository / deployed Customer feature `3fcd0ec`. This is a read-only Customer parity and brief audit, including account-role entry points and their existing operational adapters. It is not certification of every native application, financial settlement path or production fulfilment scenario. No application code, production data, settings, role assignments, carts or orders were changed. Background/staff remain frozen; no subagents or paid model/image APIs.

## Confirmed gaps

| ID | Priority | Finding | Evidence and consequence |
|---|---|---|---|
| F1 | High | Merchant and Delivery entry points are misplaced in Profile, absent from Settings | Live Settings has no `.customer-partner-cta`; live Profile has the correct Merchant and Delivery URLs. `CatalogueView.tsx:1245` and `:1260` explicitly exclude both cards when `accountPane` is settings. This is placement regression, not removed role functionality. Restore them to Settings using their existing approval/application-state presentations. |
| F2 | High | Active-order strip cannot discover existing work on a fresh device/sign-in without a local hint | `useReimaginedActiveOrder.ts:31` restores one local-storage ID, and `:60` skips the server read if it has no ID. Root has no server order-list hydration for this strip. An order placed elsewhere can remain visible in Orders but absent from the persistent bottom strip. This is source-confirmed; no real order was created to reproduce it. |
| F3 | Medium | Grocery search lost canonical aliases/identifier search | Old `DastakV1CustomerExperience.tsx:483` calls the canonical search API. Reimagined `reimaginedCatalogue.ts:94` instead checks only name, brand, pack, variant and category/subcategory text. The canonical SQL also searches `sku_search_aliases`, identifiers and a search document. These matching capabilities are not present in the local projection; even the available barcode property is not searched. |
| F4 | Medium | Failed catalogue refresh discards useful previous content | `useReimaginedCatalogue.ts:25` replaces the resource with error only; `:30` excludes earlier revisions. Retry hides previous content immediately and failure leaves no catalogue. This contradicts the brief's useful-cache-retention rule. Different-account/session isolation must remain intact when fixed. |
| F5 | Medium | Selected category is not reliably visible in the phone directory | Live 390×844 Milk quick-pick check: directory y=139.5–271.5; selected Dairy, Bread & Eggs button y=257–301. It is partially clipped. Highlight state exists, but no selected-row reveal keeps it in the visible directory window. Brief section 30 requires immediate right-side orientation. |
| F6 | Medium | Product Type filter exists in code but is ineffective for current live data | `reimaginedCatalogue.ts:10` derives Product Types only from explicit `variant`; filters do not infer types from names. Linked read-only aggregate: all 572 active SKUs have empty `variant_name`, none has a productType/product_type attribute. Live Milk has zero Product Type controls despite Full Cream/Toned product names. A canonical field/data plan is required; do not guess identities. |
| F7 | Medium | Real city-trending discovery remains unimplemented | Grocery accepts an optional trending projection but authenticated root supplies none, showing the unavailable message. Food has no genuine city-ranking/trending-badge integration. This was already documented, not completed by later releases. Do not invent rankings from shelf order. |
| F8 | Medium | Product facts are incomplete in the database | Of 572 active SKUs, only 52 have a non-empty description (520 do not), and zero have a manufacturer name. UI supports these fields but cannot display absent facts. Existing pack grouping is implemented; missing variant/family metadata prevents claiming all product/variant semantics are reference-complete. Approved product information is needed, not new SKUs or fabricated facts. |
| F9 | Low | Food content has missing imagery | One of two active Food menu items has no image key. The Food DTO/UI consumes that key directly. A suitable owned/approved product image is needed. Catalogue category imagery remains out of scope, as the owner previously directed. |
| F10 | Low | Food typing suggestions cover loaded menus, not the complete regional catalogue | `ReimaginedFoodSuggestions` searches its supplied menu cache; the food loader issues regional search only for a submitted query. With multiple pages, a restaurant/dish beyond loaded pages can be absent from suggestions although submitted search can find it. This is a bounded-suggestions limitation, not evidence that full Food search is missing. |

## Important false positive ruled out

25 active Grocery SKU rows have a blank legacy `image_key`, but **all 572 active SKUs have VERIFIED, CLEARED PRIMARY `sku_images` records**. The current canonical catalogue reads governed primary assets, not that legacy field. Therefore this audit does **not** report 25 missing Customer product images. Image URL reachability/visual correctness for every asset still needs its own validation; approved records alone do not prove image content quality.

## Coverage inventory

| Area | Current disposition |
|---|---|
| Phone spatial layout, safe sizing, separate directory | Implemented and live; selected-row clipping remains F5 |
| Home resets exploration but preserves both carts | Existing reducer and tests cover it; same selected-service Home behaviour exists |
| Food/Grocery independent cart persistence and exclusive edit ownership | Existing state/storage/locking implementation and tests retained |
| Bucket acquisition and exact displayed pack Add | Implemented; explicit Bucket gate remains |
| One shelf product with exact pack choices | Implemented and live; data completeness remains F6/F8 |
| Product detail gallery, pack, MRP, unit price, Save/Share | Existing components present; facts depend on real data |
| Canonical directory and Admin catalogue IDs | Shared map/resolver retained; no second taxonomy |
| Search typing preserves main panel until Submit | Reducer/shell support it; search capabilities differ as F3/F10 |
| City/zone serviceability, local positive stock, no-rider order block | Deployed backend/UI policy; no live purchase was attempted |
| Closed restaurants remain visible; explicit Admin removal/restore | Implemented, deployed and read-only Admin dialog verified in the prior release; no live removal performed |
| Food category filtering and nearest regional pagination | Present; real trending is still F7 |
| Wishlist and unavailable saved identities | Existing API/identity preservation and UI retained |
| Saved addresses/profile recipient propagation | Existing editors/adapters retained; no live add/edit/delete/default changes in this audit |
| Orders, older-order routing, receipts, Payments workspace | Existing operational controllers mounted, not placeholders; active discovery F2 remains |
| Order cancellation/help/issues/returns/refunds | Existing controls and adapters retained; execution not tested on production |
| Settings notifications, identities, sessions, data export, legal/support | Real shared account components retained; role placement F1 remains |
| Sign-out / Delete Customer | Present. Delete Customer is persona-scoped, intentionally not deletion of Merchant/Delivery identities; no destructive action tested |
| Offline indicators and cart preservation | Existing guards retained; catalogue cache handling F4 remains |
| Reduce Motion, focus restoration, keyboard controls | Existing implementation/tests retained; this is not a physical VoiceOver/TalkBack audit |
| Parcel and Print | Intentionally Soon/disabled under the approved brief; not a missed feature |
| Background/weather/staff | Frozen by user instruction; no further work performed |

## Why the passing tests did not establish full parity

81 focused existing tests passed during this audit (workspace, active-order hook, state, Grocery, Food, catalogue). This means their assertions pass, not that every requirement is covered. Root integration tests mock the operational account workspace. Real `ReimaginedWorkspace.test.tsx` renders Profile/Settings but does not require Merchant/Delivery cards in Settings. The active-order tests exercise an existing hint, not discovery without one. Parity assertions must cover actual entry points and missing-state scenarios rather than treating counts as completeness proof.

## Fix sequence and release boundaries

1. Correct Settings role entries and add real-pane regressions for unaffiliated, pending, approved, suspended, rejected and deleted-role presentations. Preserve URLs and backend access checks.
2. Add owned server-side active-order discovery on sign-in/resume, with explicit behaviour for multiple active orders and legacy order identities. No guessed IDs or cross-account leakage.
3. Restore canonical submitted Grocery search semantics and safe cache retention, without changing the brief's typing-only-dropdown rule.
4. Reveal selected phone-directory rows and verify quick-pick, search, Back and service-return paths.
5. Plan truthful canonical Product Type/family data, genuine trending, and approved product-content completion. Do not silently add reference-only SKUs or unapproved imagery.

No fixes, commits, pushes, migrations or deployments were executed in the original audit above. Before claiming full operational end-to-end completion, separately authorize a designated real/staging merchant, delivery partner and order scenario. Payments, cancellation, returns/refunds, role deletion and account security actions were deliberately not executed.

## Authorized correction batch — implementation checkpoint

The owner authorized implementing and deploying F1–F5. The original evidence is retained above, not rewritten as though the regression never existed.

- F1: Merchant and Delivery cards now appear in Settings rather than Profile, using the existing application/approval presentations and exact role URLs. Shared legacy unsplit account access remains unchanged.
- F2: New actor-bound `dastak_v1_customer_active_orders()` discovers owned active V1 and legacy Merchant orders without a local hint. It returns at most 20 hints plus the exact count, uses partial indexes, rejects anonymous/foreign actors, and performs no order/cart/payment writes. The strip refreshes on sign-in/resume and every 60 seconds while visible and online; multiple orders open Orders, and single legacy identities open their existing detail controller. Same-account error recovery and cross-account abort guards are covered.
- F3: Grocery typing and submitted search now use the existing canonical catalogue search API, including aliases and identifiers. Typing remains dropdown-only; submission changes the centre. Debouncing, bounded query caching, pagination/version guards, session isolation and canonical facts for encountered cart identities avoid redundant requests or guessed products.
- F4: Slow or failed refresh preserves useful same-session catalogue content with an explicit error/retry state. Different accounts or authentication contexts cannot inherit it; stock and checkout policy still use current availability checks.
- F5: Selected phone-directory rows reveal themselves by scrolling only that directory, without moving the page or resetting centre scroll.

Local gates: 893 Web tests across 132 files; TypeScript, ESLint and production build; 40 Orders Edge handler tests; native PostgreSQL fixtures for actor ownership, terminal filtering, legacy discovery, exact counts/page limits and anonymous rejection. Linked migration preflight compiled and verified the actual schema inside a transaction, then rolled back. Vercel Customer project/root/variant checks passed.

Release still pending at this checkpoint. Only migration `20261008130951`, Orders Edge and Customer are in scope; unrelated pending migration `20260929191745` and both untracked RPM staff assets are excluded. F6–F10 remain open, and passing tests are not certification of real fulfilment, role transitions, purchases or refunds.

### Production release evidence

- Feature commit: `b3b4bca54d97f98a4689b754cc6967355a450975`; final local production build passed in 28.30 seconds.
- Linked migration `20261008130951` committed atomically and recorded. Post-release checks: authenticated execute allowed, anonymous execute denied, unrelated `20260929191745` still unapplied.
- `dastak-v1-orders` deployed to the verified linked project. Customer deployment `dpl_DXw961QuHeL5zET9q9y83a5R4d29` is READY and aliased to the normal Customer address. The deployment script verified HTML release SHA, Customer variant, production environment, deployment ID and security headers.
- Error-level database lint for `dastak_v1`, `dastak_v1_api`, `private` and `public` returned no findings. A separate all-schema lint reported existing PostGIS extension helper diagnostics; these are outside the changed application functions and were not modified or represented as a clean global database audit.
- The Codex browser repeatedly lost its sign-in; the owner requested Safari. In the existing signed-in Safari Customer tab, refreshed Settings displayed both Become a Dastak Merchant and Become a Delivery Partner, and Profile displayed neither. Typing barcode `8904064712041` preserved the Home centre and returned Aachi Curry Masala 100 g through canonical search. Submission changed the heading to the barcode results.
- Full submitted-result verification paused at a regional availability loading state after visiting Profile. Safari inspection then stopped because the Mac locked. Phone live bounds and authenticated active-discovery response remain unverified at this checkpoint; no production order or stock was manufactured to make a test pass.

Logs: `/tmp/dastak-parity-customer-deploy.log`, `/tmp/dastak-active-discovery-release.log`, `/tmp/dastak-active-advisors-scoped-release.log`, `/tmp/dastak-active-advisors-release.log`, `/tmp/dastak-parity-batch-build-final.log`, `/tmp/dastak-parity-batch-web.log`, `/tmp/dastak-parity-orders-edge.log`, `/tmp/dastak-active-discovery-sql.log`. No Git push performed in this batch.

### Automatic sign-out incident and targeted repair

- Confirmed linked `authenticated` lacks USAGE on `private`. The new invoker RPC called a helper in that schema, causing `permission denied for schema private`. The background Reimagined error handler classified 403 as sign-in and invoked the full sign-out callback, which revoked the account-session registry. This explains why changing browsers did not resolve the loop.
- Migration `20261008174027` moves only the guarded read helper into the existing unexposed `dastak_v1_api` schema and updates its public invoker wrapper. No broad access to `private` is granted; customer/actor checks and anonymous/service-role restrictions remain.
- Customer permission failures now present a retryable access error. Automatic 401 recovery verifies the login with Auth before clearing local auth and never calls the explicit registry-revoking sign-out callback. Network/server errors and stale-token responses cannot sign out a valid/refreshed session. Explicit user sign-out is unchanged. Both Reimagined and embedded existing Customer order controllers use this recovery boundary.
- Verified: original failure reproduced using `authenticated` on the linked database, repair tested in a rollback transaction; native SQL suite checks actual Customer role, owned results, limits, foreign-actor rejection and unauthenticated denial. 904 web tests / 133 files passed, targeted ESLint passed, TypeScript/production build passed (existing large-asset warning), linked security advisors at error level reported no issues.
- Production repair migration committed atomically and recorded. Post-release check confirms authenticated helper access, anonymous denial, private schema still inaccessible, unrelated migration `20260929191745` still unapplied. Customer deployment `dpl_FayVZ76qGGGUQcXepNQjMo183xz1` is READY at the normal address; release SHA `069b2ed7de401b2674347d5ea26624b0801633ce`, Customer variant, production environment and security headers verified. No Orders Edge redeployment required.
- Owner refreshed and signed in to Safari after the release. Read-only live verification: Home loaded personalized content and regional availability; Orders loaded Active/Past counts and owned history; Settings loaded account controls plus approved Merchant/Delivery cards. Session remained authenticated for more than two minutes (including a background refresh interval), survived a full page reload back into Settings, then returned to authenticated Home. This verifies the reported immediate sign-out loop no longer occurred in the tested Safari session; it is not certification of indefinite session duration or fulfilment/payment flows.

### Phone navigation and submitted Grocery search follow-up

- Live production Safari at 390×844: Milk quick pick opened the Milk shelf and revealed the selected Dairy, Bread & Eggs row fully within the right directory. This verifies the previously observed F5 clipping case, not every device/breakpoint.
- Typing `Nestle` opened suggestions while keeping the Milk shelf in the centre. Submit changed the centre to one grouped Nestle Everyday Dairy Whitener product with four pack choices (200 g, 15 g, 1 kg, 400 g). Selecting 15 g updated the detail/Add identity and price to ₹10.00; out-of-stock Add remained disabled. No cart, stock or order writes were performed.
- Browser Back restored the Milk shelf and search dropdown. Closing search preserved Milk/Dairy selection. Switching to Food and back to Grocery also restored that shelf and selected department. This was a service-return test, not a complete Food loading/ordering test.
- The signed-in Safari session persisted throughout. An initially prolonged availability-loading state eventually resolved without a source change; its cause remains unconfirmed because Safari's inspector was blank. Do not count this delay as repaired or as evidence that availability/session reliability is universally proven.
- Focused local tests: six files, 30 tests passed (shell, responsive sizing, navigation, canonical Grocery search resource, availability resource, product parity). No implementation change or production deployment was needed for the behaviours verified here. Live alias/barcode matching and real fulfilment/payment workflows remain outside this completed check; F6–F10 remain open.
- No browser setting changes, orders, payments, stock writes or account-session revocations performed for testing. Logs: `/tmp/dastak-auth-repair-web.log`, `/tmp/dastak-auth-repair-build.log`, `/tmp/dastak-auth-repair-sql.log`, `/tmp/dastak-auth-repair-advisors.log`, `/tmp/dastak-auth-repair-release.log`, `/tmp/dastak-auth-repair-customer-deploy.log`. No Git push in this repair batch.

### F6 Product Type — local shared-field implementation, not a production resolution

- Linked read-only inspection found 572 active SKUs, zero recorded `attribute_data.productType` values and zero variants. No classifications were inferred or written. Existing Customer/Admin projections expose attributes; Merchant's deployed canonical snapshot does not.
- The shared contract is the optional string `attributes.productType` (trimmed, at most 100 characters, no control characters), separate from variant/flavour. This uses existing SKU metadata; it is not a new Product Type entity registry or a change to canonical category/SKU IDs. Labels must use consistent reviewed wording across related packs.
- Admin can maintain Product Type through the existing privileged, version-protected SKU update review. The patch preserves other attributes, clearing removes only this key, and unrelated edits omit unchanged attributes. Customer rail filters/detail facts and Merchant detail facts use the same field. Merchant's existing subcategory selector is correctly labelled Subcategory, not Product Type. Different recorded types do not merge into one shelf product. Unclassified products remain in All; filters are shown only where multiple recorded types are present, and stale filters fall back to All without changing the cart.
- Unapplied migration `20261008182018_catalogue_product_type_metadata.sql` validates the field and adds only Product Type to Merchant's projection. It surgically preserves the existing deployed function body, permissions, search path, actor/branch checks and stock fields, rejecting unexpected source drift. No backfill, price, stock, status, order or permission changes are included.
- Verified locally: 911 Web tests across 135 files, targeted ESLint, TypeScript and production build (existing large-chunk warning). A separate socket-only temporary PostgreSQL fixture verifies invalid-value rejection, exact function-source/grant preservation, classification-only disclosure and fixture actor/anonymous guards. This is not a live Merchant authorization integration test. Test logs: `/tmp/dastak-product-type-web.log`, `/tmp/dastak-product-type-build.log`; database fixture diagnostics were retained in the reported temporary directory.
- No commit, push, database application, production deployment or browser verification for this implementation. Both untracked RPM staff assets remain excluded; background/staff are unchanged. F6 remains open until release and verified data population; F7–F10 are not resolved by this change.

Remaining F6 sequence: (1) target only this migration after checking the linked function still matches and existing attributes satisfy the constraint, excluding unrelated pending migration `20260929191745`; (2) deploy the changed Customer, Merchant and Admin bundles; (3) prepare exact-SKU mappings from reliable product evidence/reference categories with source and expected version, leaving uncertain items blank, without adding reference-only SKUs; (4) obtain approval for that mapping and populate through the guarded Admin update route; (5) verify the same type, correct shelf, exact pack choices and unchanged availability policy in all three apps. This checkpoint does not authorize production data writes.

### F6 infrastructure production release — 9 October 2026

- Owner approved applying this migration and deploying Customer, Merchant and Admin while leaving classifications unchanged. Feature/release commit `8901e65fb6ba4b520bb48189df01478652c337a0`; no Git push performed.
- Targeted linked preflight applied the migration in a transaction, checked exact function-source replacement, grants, owner, security/search path, unchanged SKU-record digest, constraint validation and authenticated missing/foreign-actor denial, then rolled back. The apply run repeated these checks, committed only `20261008182018` and recorded its migration history atomically. No blanket database push.
- Post-release: migration recorded once, constraint validated, 572 active SKUs, zero recorded Product Types, unrelated `20260929191745` remains unapplied. Linked security advisors at error level reported no issues before and after.
- Customer deployment `dpl_2sfeULpm4GNu9qUGXPkmjyDiNFpX`, Merchant `dpl_DxnnDqd2sKxufYRwYyrJBUhRpVfa`, Admin `dpl_Dp7E1TdVXCkNp5HA72H5eZkoev2J` are READY in production. Their normal aliases serve the same feature SHA, correct app variant, production environment and deployment IDs; expected security headers verified. Release checks verified each project's root and production configuration. The two unrelated untracked staff assets were excluded from every upload.
- Immediate deployment-scoped error-level Vercel log scans returned no entries for all three releases. This bounded scan is not certification of future/browser errors, signed-in UI workflows or purchases. No signed-in browser verification or production classification edits were performed in this release.
- Logs: `/tmp/dastak-product-type-release-preflight.log`, `/tmp/dastak-product-type-release-apply.log`, `/tmp/dastak-product-type-release-postcheck.log`, `/tmp/dastak-product-type-advisors-before.log`, `/tmp/dastak-product-type-advisors-after.log`, and `/tmp/dastak-product-type-{customer,merchant,admin}-deploy.log` plus inspect/error-scan files for those roles.
- F6 infrastructure is deployed; verified classification mapping/population and cross-app populated-filter verification remain outstanding. F7–F10 and real operational/payment workflows are not resolved by this release. Background/staff, stock, prices, orders and classifications remain unchanged.
