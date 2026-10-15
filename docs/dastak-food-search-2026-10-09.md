# Regional Food suggestions and phone checkout

## Scope

Customer Reimagined only. No SKU, taxonomy, background, database migration,
Admin or Merchant changes. Existing unrelated working-tree edits preserved.
No paid model calls or subagents. Live verification is read-only.

## Implemented

- Food typing suggestions use the existing authenticated regional restaurant
  API with the selected saved-address identity/version, rather than searching
  only menus already loaded on screen.
- 300 ms debounce; eight restaurant results per request; eight-query,
  one-minute in-memory cache. No typing-driven pagination. Explicit Submit
  and Load more retain the existing complete server search flow.
- Abort/ignore late results after query, account, session, backend, address,
  address version, online state or search visibility changes.
- Main panel stays unchanged while typing. Selecting a server suggestion
  retains its exact restaurant/menu identities for details, options and cart.
- On reload, fetch the exact saved Food-cart branch if it lies outside the
  loaded restaurant page. Preserve cart quantities and exact option IDs.
- Apply current area availability to suggestions: closed restaurants stay
  visible but disabled; Admin-unlisted restaurants are omitted.
- Retain server-returned matches even when the visible branch name differs
  from the matching organisation name.
- Food checkout controls are stacked, styled and touch-sized within the
  existing scrolling phone panel. No-delivery-partner submission remains
  blocked, while available dishes can still be added to the cart.

## Verification

- TypeScript build and scoped ESLint.
- Full web unit/integration suite: 1,001 tests in 145 files passed.
- 390 × 844 local browser: regional-only dish suggestion, closed-store
  disabled suggestions, required Large option, Add, Back to menu, Food-cart
  quantity 1 → 2 → 1 (₹180 → ₹360 → ₹180), Continue Shopping, separate
  Grocery cart, no-delivery-partner disabled Reserve control.
- Phone document width 390 px: no horizontal overflow.
- Evidence: `verification/dastak-food-search-2026-10-09/`.
- Synthetic local menus/checkout only for cart mutations. No real order,
  reservation, payment, account, saved address or live cart was changed.

## Release

- Commit `1ce1569350d0473e1dc001110dedc2b9072e2218` pushed to
  `codex/dastak-v1-launch` and deployed to Customer production.
- Deployment `dpl_zSGURVGbrRK5wvhHkdKn1STbbX3s` is READY and aliased to
  `https://dastak-customer.vercel.app/`. Normal-address HTML and signed-in
  browser both confirm the exact commit SHA, Customer variant and production
  environment. Build passed; CLI final status polling hit ETIMEDOUT, so the
  deployment was inspected directly instead of creating another build.
- Normal address returns HTTP 200, CSP frame-ancestors none,
  X-Content-Type-Options nosniff and X-Frame-Options DENY.
- Signed-in 390 × 844 production verification: typing Craft returns the
  restaurant, Cappuccino and Espresso suggestions without replacing the main
  discovery panel. Catalogue requests returned HTTP 200. Selecting Cappuccino
  opens the correct dish details; Back to menu restores Craft's menu.
- Live area displays the no-delivery-partner notice. No real cart, order,
  reservation, payment, profile or saved-address changes were made. The live
  dish had no required options; option-price and cart/checkout mutation checks
  remain local synthetic evidence, not production transaction verification.
- Production document width is 390 px with no horizontal overflow; temporary
  viewport override cleared afterwards. Captured browser errors: zero. The
  bounded Vercel error-log query returned no entries; this is not a complete
  backend or Supabase log audit.
- Live proof: `verification/dastak-food-search-2026-10-09/phone-live-regional-suggestions.png`.
- Four exact-commit automatic non-production preview builds were cancelled
  to avoid duplicate build costs. No Admin, Merchant or Delivery production
  release was made. Post-release report/evidence updates are local only.
