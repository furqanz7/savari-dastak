# Locked focus: phone navigation and Admin — 2026-10-08

The owner locked work to these two items until wrapped. No background, staff, weather, payment-provider or unrelated feature changes.

## Phone brief correction

The original master handoff requires a top-left vertical Home/Orders/Profile/Settings list, Location beside it, top-right Services with the Grocery directory beneath, centre shopping and bottom cart/order state. A later mobile override had moved navigation to a conventional bottom row and categories to a horizontal strip. That override is corrected; mobile and desktop retain the same mental model.

Validated local browser widths: 320×568, 390×844, 430×932 and tablet 768×1024. Phone navigation remains vertical, directory scrolls vertically, controls do not overlap the main panel, cart remains below it, and there is no horizontal page overflow. At 390px shelves show about 2.5 cards with horizontal swiping. Narrow phone service targets remain 44px wide. Short screens scroll instead of crushing content. Food retains the same left navigation while hiding only the Grocery directory.

## Admin work

Existing Admin catalogue uses `getV1CatalogueBrowseMap`, canonical taxonomy/SKU UUIDs and the shared `browseSkuIds` relationship resolver. No duplicate map or new product identities were introduced. Merchant governance already supports reviewed suspension/reactivation and routing correction; operational safety and delivery-partner governance remain their own existing controls. This pass is not a redesign/audit of every Admin finance or payment screen.

The missing action is now explicit Restaurant/Cafe Customer removal/restoration:

- Admin → Merchant governance → Restaurant branch → Remove from Customer / Restore to Customer.
- Separate `customer_listing_visible` flag, default true. Closing, stopping orders, operational pause or suspension does not remove listings.
- Permission `platform.merchants.manage`, active Admin assignment, actor bound to authenticated session, expected branch version, required reason and idempotency key. Removal requires typed branch-name confirmation. The existing uncertain-result reconciliation framework is reused.
- Removal is reversible, not deletion. Branch, menu, orders and financial history are preserved. Restoration does not reopen a closed store. Already-confirmed orders continue; new submissions/confirmations for removed stores are blocked on the server.
- Regional availability, nearest/alphabetical paging, exact lookups and already-loaded Customer menus respect explicit removal. Admin still lists removed records. Older backend projections disable the new control instead of assuming visibility.

Migration: `20261008114655_admin_customer_restaurant_visibility.sql`. Only this migration is releasable by `Backends/Dastak/scripts/release-customer-visibility.mjs verify|apply`; no blanket migration push. Native linked preflight passed and rolled back without removing any live branch.

## Verification checkpoint

- Web: 880 tests passed, TypeScript/ESLint/production build passed. Existing large-3D-chunk warning remains.
- Orders Edge: 39 handler tests passed; Deno check passed.
- Isolated PostgreSQL assertions passed for removal/restore, unchanged operational state, retained Admin record, region/exact lookup filtering, new-order/confirmation rejection, stale versions, audit once, retry replay, conflicting retry key, non-admin and retail-target rejection. This fixture uses synthetic geography and a small governance-auth stub; it is not a live privileged mutation test.
- Native linked migration trial passed with real schema/function definitions, unauthenticated rejection and default-all-visible assertion. Error-level security advisor scan was clean.
- No real restaurant, cart, order, stock or account was changed for testing. No subagents, paid model APIs or image generation.

Production release and read-only verification pending at this checkpoint. Keep this focus locked until that is recorded; user visual acceptance is separate from automated geometry checks.
