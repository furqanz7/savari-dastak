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

Customer production release and signed-in read-only verification pending.
An empty/unserviceable live Food region cannot prove populated production
menu choices; local fixture and integration evidence are separate from that.
