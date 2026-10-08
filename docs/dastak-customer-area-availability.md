# Customer area availability — 2026-10-08

Status: production release authorized on 2026-10-08. The specific migration is applied and recorded on linked Dastak (`zmtsolkfxlrxepshnjdf`), and `dastak-v1-catalogue` is deployed. Customer deployment and live browser verification are the remaining release steps at this checkpoint.
Scope: location-aware Grocery inventory, delivery admission, and visible closed Food stores. Background/staff assets unchanged. No live orders, payments, inventory writes or customer account mutations were performed.

## Rules

- The selected, owned saved address and its exact version determine the canonical service zone; city-name string matching is not used. Changing account, location, address version, going offline, read failure or stale availability fails closed without deleting either cart.
- At least one active onboarded retail merchant in that zone makes Grocery serviceable. Otherwise display “Grocery delivery isn’t available in your area yet.” and Change location.
- An exact Grocery SKU/pack requires selected positive numeric merchant stock, active merchant/branch, an open accepting branch, the configured retail radius, and no branch/zone retail pause. Missing, unknown and zero stock are Out of stock. Stock is the maximum available at one eligible merchant, not a sum promising a cross-merchant quantity. Pack grouping and exact SKU identities are preserved.
- Customers can add locally available items without a delivery partner. New order submission/reservation and confirmation require an approved active delivery partner online with unexpired availability and a location inside the same active zone. Partner suspension, deleted delivery persona or rider-assignment pause blocks admission. Existing order status/recovery remains readable.
- No onboarded Food branch in the zone displays “Food delivery isn’t available in your area yet”. Onboarded closed, paused, suspended and menu-empty branches remain listed. Store closed disables restaurant cards, dish-search entry points, saved-store views and reopened stale details. PENDING_REVIEW is not onboarded.
- This change does not introduce an Admin store-removal workflow. Closing or suspending a store is not treated as removal.
- Canonical database submission/confirmation triggers enforce delivery availability. Matching and locked stock reservation reject unknown stock for new orders. Existing orders receive policy version 0 and retain their historical retry/recovery semantics; new orders receive policy version 1. Idempotent replays are not treated as new orders. Existing stock row locks and reservation accounting remain in place.

## Implementation

- Migration: `Backends/Dastak/supabase/migrations/20261008095639_customer_area_availability.sql`.
- Public authenticated RPCs: `dastak_v1_customer_area_availability` and `dastak_v1_customer_restaurants_area_page`. Both bind to the bearer actor and an owned address/version, not supplied actor IDs or client coordinates. Private helpers are not granted directly to client roles.
- Catalogue Edge handler exposes both operations using authenticated RPC calls. Regional restaurant pages preserve cursor paging, nearest ordering and location-scoped exact-branch lookup. Older alphabetical restaurant callers use their owned default/latest address rather than a global list.
- Reimagined uses one sparse batched stock/restaurant snapshot per location, refreshing every 30 seconds while visible, expiring after 45 seconds. No per-product API calls or external AI services. Refresh preserves a still-fresh snapshot; late replies from another address/session are ignored.

## Verification and limits

- Web: 875 tests passed; TypeScript, ESLint and production build passed. Existing large-3D-chunk warning remains.
- Edge: 30 catalogue handler tests passed; Deno checks passed.
- SQL: isolated local PostgreSQL assertions pass for owned/stale addresses, serviceability, positive/zero/unknown stock, delivery offline/expired/suspended/wrong-zone states, server rejection, closed-store visibility/pagination, grants and legacy-order handling.
- The isolated SQL harness uses synthetic PostGIS geometry/distance functions and small matching/stock source-patch fixtures, not complete matching/fulfilment end-to-end coverage. Before production application, the exact migration passed a linked native-PostGIS transaction trial and was rolled back; the subsequent application committed the migration and its history entry atomically. Six guarded source replacements each matched the expected predicate exactly once. Native helper reads and unauthenticated rejection also passed. Error-level security advisors were clean before application.
- No production checkout or purchase was attempted. Stock displayed in the UI is a short-lived snapshot; authoritative transactional checks can reject changed stock or delivery availability.

## Production next step

Release runner: `Backends/Dastak/scripts/release-customer-area.mjs verify|apply`, run from `Backends/Dastak`. It checks the exact linked project, rejects repeated/unrecorded partial application, sets lock/statement timeouts and applies only this migration in a transaction with its history entry. A blanket database push was not used; unrelated pending migrations were left untouched. The migration aborts on predicate source drift. The backend was released before Customer. Verify the Customer deployment with owned-address read-only checks and closed-store/stock/cart states before attempting any separately authorized real order.
