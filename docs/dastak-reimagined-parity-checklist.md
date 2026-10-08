# Reimagined Customer parity checklist — 2026-10-08

This is a Customer feature-restoration checklist, not a claim that the entire
Customer/Merchant/Admin platform or all production catalogue data has been audited.
It consolidates the earlier feature, shelf, workspace and navigation passes.

## Release and verification boundaries

- Worktree: `.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`.
- Baseline/deployed release: `aae8352b83daa08d4b5b079bc48235b8eacd0b4b`.
- The older merchant-order routing correction below is local, not deployed.
- Current local gate: **845 tests / 127 files passed**, ESLint passed,
  TypeScript and production build passed; `git diff --check` passed.
- Build still warns about large 3D/animation chunks. Those are not resolved here.
- Production was inspected in the signed-in Codex browser at the normal Customer
  address. No cart, Wishlist, profile, address, permission, order, payment,
  support or account changes were submitted. No sensitive account data is copied
  into this checklist.
- Automated tests use fixtures/mocked adapters. They do not prove a real purchase,
  delivery, refund or destructive account action.

## Consolidated checks

| Capability | Implementation / automated evidence | Signed-in production check this pass |
| --- | --- | --- |
| Normal Customer address | Reimagined entry ownership; `DastakCustomerView.reimagined.test.tsx` | Signed-in Reimagined loaded without a query flag |
| Search, Wishlist, Payments and browser history | `useReimaginedNavigation.test.ts`, `ReimaginedCustomerRoot.test.tsx`; account-scoped navigation history excludes cart/token/payment state | Grocery search returned results; Wishlist loaded empty; Payments returned 10 activity entries. Back/Forward verified locally, not across every live screen |
| Older merchant-order links | Separate `merchantOrderId`; `#/orders/<uuid>` opens `CatalogueView` rather than the V1 controller. Closing returns to general Orders. Direct links and Back/Forward covered by root and wrapper tests | Local fix only. Synthetic browser restored the selected older ID after Back, retaining Grocery 2 / Food 1. No actual older merchant-order record checked |
| Newer V1 order links | `#/v1-orders/<uuid>` stays separate; wrapper/root tests | Orders loaded 29 past / 0 active. One delivered Food order opened through its exact V1 link |
| Bills, order items, receipt and timeline | `customer-orders.test.tsx` covers destination snapshots, receipt affordance, timeline, ETA, map and PIN state | Delivered order showed items, immutable recipient/destination, bill, collected payment, timeline, receipt button and help controls. Receipt was not downloaded; live tracking/PIN not exercised because no active order |
| Grocery category/rail map | Canonical directory and catalogue adapters; `reimaginedCatalogue.test.ts`, `ReimaginedGrocery.test.tsx` | Directory and quick picks rendered. This was not a database-wide taxonomy/content audit |
| One product with multiple pack sizes | Exact branded-family grouping; `ReimaginedProductParity.test.tsx`, catalogue/product-browser tests | Nestle Everyday displayed one result with 4 sizes. Selecting 400 g changed price to ₹255 and opened matching details; no Add/Save action |
| Product details, variants, gallery, share and navigation | `ReimaginedProductParity.test.tsx`, `ReimaginedProductBrowser.test.tsx`; variants only when explicit data exists | Selected pack details, unit price and supplied product facts rendered. Share button visible but not invoked; all production metadata/gallery coverage remains unaudited |
| Food discovery, menu, options and pagination | `ReimaginedFood.test.tsx`, `useReimaginedFood.test.tsx`, Food selection/recovery tests; deployed pagination recorded separately | Craft and its Hot drinks menu loaded. Cappuccino/ Espresso prices rendered. Neither dish had customisation options, so live required-option selection and pagination were not exercised |
| Wishlist save/remove | Native controls with existing exact-SKU/menu-item adapters; `ReimaginedWishlist.test.tsx`, `useReimaginedWishlist.test.tsx` | Empty state loaded correctly; no live save/remove writes |
| Separate Grocery/Food carts and reorder | Persistence, ownership and reconstruction tests; approval before replacement; unavailable identities not substituted | No live cart/reorder writes. Older-link restore tests retain both carts and make no submit/payment calls |
| Addresses and recipient profile | Existing address/profile controllers; `ReimaginedAddressPicker.test.tsx`, `useReimaginedAddresses.test.tsx`, root recipient propagation tests | Profile loaded one saved place and existing recipient details; no edit/add/delete/default action |
| Grocery/Food checkout and recovery | Checkout counter, billing, journal/recovery and mocked API tests | Not exercised live: no reservation, confirmation, payment or cancellation performed |
| Notifications, identity and account safety | Existing shared push/account controllers, mounted in Reimagined | Settings loaded alert state, linked sign-in method, session/data/legal/support controls; no enabling alerts, identity linking, export, session revocation, sign-out or deletion |
| Help, cancellation, issues/returns/refunds | Existing operational controllers retained, not placeholder pages | Order help affordance visible. No support submission/cancellation/return/refund execution; not claimed end-to-end verified |
| Mobile layout | Earlier synthetic mobile checks recorded in feature/shelf/workspace docs; local component tests | Not re-run on an actual phone in this pass |

## Remaining work — explicit, not silently marked complete

1. **Nearest-first Food discovery:** local implementation now adds server-side
   saved-address distance paging and UI labels. Not yet released; real PostGIS
   verification and production rollout remain. See `dastak-reimagined-nearest-food.md`.
2. **Genuine city trending:** Grocery displays the unavailable state; authenticated
   root has no actual city-ranking data, and Food lacks the requested ranked
   city-trending entries/badges. Do not fabricate rankings.
3. **Catalogue content completeness:** audit all existing SKUs for product-family,
   pack and Product Type metadata before claiming every production product groups
   exactly as intended. Do not add reference-only SKUs.
4. **Missing Food imagery:** the live Espresso dish shows Image unavailable.
   Needs a suitable owned/approved source asset and a separate content update.
5. **Operational end-to-end verification:** real checkout/fulfilment/payment,
   active tracking/PIN, support/returns/refunds and security/destructive account
   actions remain separately gated; read-only visibility is not proof of success.
6. **Release this correction:** older-order routing changes have not been pushed
   or deployed in this pass. Recheck an actual older order after release.

Parcel and Print remain Soon under the approved brief. Background/staff work
remains frozen by the owner's decision. The two untracked RPM staff assets are
untouched and excluded from this change.

## Local evidence artifacts

- `/tmp/dastak-legacy-order-tests.log`
- `/tmp/dastak-legacy-order-build.log`
- `/tmp/dastak-older-order-navigation-2026-10-08.jpg` (synthetic, no real order data)
- `/tmp/dastak-signed-in-settings-2026-10-08.jpg` (current production Settings)

Temporary artifacts may be removed by the OS. Tests and this checklist are the
durable evidence within the worktree.

## Release authorization — 2026-10-08

The owner's following "go ahead" approves committing and pushing this scoped
older-order routing correction and deploying Customer production only. Use
`scripts/deploy-dastak-web.sh customer --production` to verify the linked project,
Customer variant, release provenance and security headers, and exclude both
untracked RPM assets. Local-only statements above describe the checkpoint before
this approval. The actual release identity and live verification results are
reported in the deployment handoff. No database changes, other app releases or
live commerce/account mutations are included.

## Follow-up checkpoints

- The older-order correction above was subsequently pushed/deployed as `c143970`.
  The normal Customer URL served that release. A deliberately nonexistent older
  ID reached the correct controller; a real delivered V1 order opened. This
  account's older-order list was empty, so no actual older record was verified.
- The nearest-first follow-up is local-only; its rollout and test limitations
  are recorded in `dastak-reimagined-nearest-food.md`. Historical local/release
  statements earlier in this checklist describe their respective checkpoints.
