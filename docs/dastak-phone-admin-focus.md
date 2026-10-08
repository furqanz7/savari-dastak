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

## Production wrap

- Code commit `3fcd0ecb0e8fe81edede01158edc38bd5674bd5d` released to Customer (`dpl_7gxWWeb8sp7PNbGvkZKbmuBJ21Pf`) and Admin (`dpl_9MqVVrrdXTsCB9gmis1uoAT4VbJF`). Both READY / production at the normal domains; the scoped deployment script verified commit, app variant, environment, deployment ID and security headers.
- Specific migration applied and recorded; `dastak-v1-orders` deployed. All existing branches remain visible, both listing admission triggers exist, anonymous removal is blocked, unrelated migration `20260929191745` remains pending, and post-release error-level security advisors are clean.
- Owner signed into Admin. Live Merchant governance shows Craft's “Listed — closed stores remain visible” state and Remove from Customer. The review dialog requires the branch name and includes reason controls with Confirm removal disabled. The dialog was cancelled without sending a mutation. Live Admin Catalogue renders the shared Browse Dastak map.
- Live Customer at 390×844: vertical navigation starts at y=62, Location beside it, Services to the right, vertical directory under Services, centre panel below without overlap, 2.49-card shelf capacity and no page overflow. Orders/Profile/Settings and Food navigation preserve the layout. Existing availability/pack grouping remain active. No cart or account writes were used for this verification.
- No browser error/warning entries were captured. Error-level Vercel scans found no logs for either deployment; ongoing monitoring/drains were not changed or claimed verified.
- Local final focused layout/Admin UI tests: 11 passed after the narrow-phone touch-target refinement. Earlier complete 880-test suite, TypeScript, ESLint and build passed; both remote release builds passed. Existing large-bundle warning is unrelated and unchanged.
- Phone and scoped Admin implementation/release are wrapped. User visual acceptance remains separate. No real restaurant was removed/restored to test the control; privileged mutation behaviour is covered by isolated tests, not a live action. The two staff assets remain untracked and excluded. Git commits are local, not pushed.
