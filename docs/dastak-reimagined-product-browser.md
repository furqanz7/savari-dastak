# Reimagined product-detail browsing — 2026-10-08

Owner approved the focused detail-browsing follow-up. Local implementation; not pushed or deployed. Starting branch/HEAD unchanged from the shelf checkpoint. Earlier shelf edits and both unrelated RPM assets are preserved. No database, inventory, production account or cart writes. Background/staff are unchanged.

## Restored behavior

- Previous/next product controls, a live position count and keyboard left/right navigation. Ends stop instead of wrapping. Navigation and Close remain reachable when scrolling long details.
- Horizontal pointer/touch swipes on the detail content. Vertical scrolling, short/diagonal gestures, cancellation and gestures starting on purchase, pack or form controls do not page products.
- A curved orbit-style thumbnail picker using the established `productPickerPose` geometry. Click/tap a thumbnail or drag the picker to navigate. It renders at most five nearby thumbnails, not every catalogue image. Missing/failed images use an honest icon fallback. Reduced-motion preferences remove entrance animation/transitions.
- One page per genuine product family. Exact pack selection, prices, stock caps, Wishlist identity and quantity controls continue to use canonical SKU IDs. Revisiting a product within the detail session remembers its chosen pack. Browsing alone does not add items or modify cart lines.
- Browsing context follows the current category/shelves, search results or supplied trending list. A size-specific search starts with that matching size but retains other genuine sizes in its detail picker. Opening a product outside that browsing context does not invent unrelated neighbours. Single-product views disable both arrows and omit the orbit.
- Shelf DOM/scroll positions survive opening and closing. If a selected SKU disappears from the loaded catalogue, details show the unavailable state rather than substituting another product.

## Verification

Flow: loaded canonical catalogue → existing grouped shelf → exact detail selection → local browsing state → unchanged canonical purchase controls. This is client presentation/state only; no new API endpoint or environment configuration is required.

- Regression tests cover family-level paging, exact pack memory, boundaries, orbit selection, swipes, non-swipes, cancellation, keyboard/select behavior, drag-click suppression, single-product views, search scope, cart-line preservation, disappearing SKUs and shelf-scroll restoration.
- Browser synthetic fixture: selected 1 L, navigated away/back and retained 1 L; performed a real drag in the phone layout and reached product 2 of 3; selected the unavailable product via the picker and confirmed Add disabled. No captured console warnings/errors during these checks.
- Responsive checks used 390×844 and 320×568, plus desktop. Both phone widths had no document-level horizontal overflow; Next and Close worked at 320×568. The smallest height requires scrolling. Temporary viewport overrides were reset. These are browser viewport checks, not physical iPhone/Safari certification. The fixture has no authentication, server checkout or live-cart persistence.
- Final gates: 818 tests across 125 files passed; ESLint, TypeScript and production build passed; `git diff --check` passed. Existing large 3D chunk warning remains unrelated.

## Deployment scope

The shelf correction and this follow-up are ready for one scoped Customer release after the owner requests push/deployment. No Merchant/Admin deployment or database migration is required for these presentation changes. Real fulfilment and source-image quality remain separate checks, not claimed complete here.

Owner's follow-up “go ahead” authorizes this scoped Customer push and production deployment. The local-only statements above record the pre-release checkpoint. Release uses `scripts/deploy-dastak-web.sh customer --production`, which verifies the Customer project/variant, archives an isolated web snapshot and excludes both untracked RPM assets. The preceding normal-address release was `0aacf52c9a60ec9e2368649a01e258d120f3ee69`, deployment `dpl_Dim4jepdhqdD6K1EnCYpGmLnpRgS`. Actual new release identity and live read-only evidence are reported in the release handoff; no real purchase or account/cart mutation is included.
