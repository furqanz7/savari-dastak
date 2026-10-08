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
