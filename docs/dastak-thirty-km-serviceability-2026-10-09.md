# Dastak 30 km customer availability

## Rule

Public web access is unchanged. After the customer chooses an owned delivery
address, Grocery requires an active approved retail/convenience merchant within
30 km. Food requires an onboarded, Admin-visible Restaurant/Cafe within 30 km.
These are independent checks. Both unavailable panels say:
"This area is not serviceable yet."

Closed/paused/suspended onboarded restaurants remain visible but cannot accept
orders. Only Admin removal excludes their listing. Pending applications are not
onboarded. A missing provider location cannot qualify.

Inventory, pickup quotes, new-order Wave 1/Wave 2 merchant eligibility, Food
submission and new-policy recovery use the same 30 km merchant radius. The
distance is geodesic, not driving distance; a one-millimetre tolerance preserves
the inclusive boundary under floating-point projection round trips. Existing
legacy policy-0 order matching/recovery retains its prior radius/zone rules.

Delivery availability and rider assignment are unchanged, including their
existing zone, approval, governance, online expiry and operational pause checks.
Nearby merchants do NOT create delivery coverage. Available inventory can be
added to cart without a rider; new submission/payment admission remains blocked
without an eligible local rider. Delivery fees and the 2% platform fee are
unchanged. Existing service-zone geometries and country onboarding are unchanged.

## Verification before release

- All 147 frontend test files / 1,032 tests passed.
- Changed Customer files passed ESLint; TypeScript/Vite production build passed.
- 34 native PostGIS checks passed against the linked schema in one rolled-back
  transaction: 0/29,999/30,000/30,001 metres; independent Grocery/Food; closed and
  removed cafes; positive/zero inventory; pickup quote; actual Wave 1/Wave 2
  evaluator; legacy zone guard; stale-address rejection; private RPC grants;
  and new-order no-rider rejection.
- Verifier also compared function hashes: delivery availability, rider offer pool
  and delivery tariff functions did not change.
- Supabase security advisor at ERROR level reported no issues. This does not
  claim there are no lower-priority warnings.
- No live order was submitted, paid or dispatched. Test accounts, merchants,
  inventory, zones, addresses and CREATED orders were rolled back.
- No signed-in browser/order lifecycle test is claimed by these checks.

## Scoped artifacts

- Migration: `20261009131135_customer_thirty_km_serviceability.sql`
- Native verifier: `node Backends/Dastak/scripts/verify-thirty-km-serviceability.mjs preflight`
- Post-release verifier: same command without `preflight`.
- Only Customer UI needs redeployment; shared database rule serves both interfaces.
- Unrelated pending catalogue activation migration and existing dirty docs/assets
  are excluded from this change.
