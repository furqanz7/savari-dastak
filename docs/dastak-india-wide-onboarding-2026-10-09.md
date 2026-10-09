# India-wide Dastak onboarding — 9 October 2026

Scope: India-wide location/onboarding readiness, not a claim of active delivery
everywhere. Solo work; no subagents, paid AI calls, paid geocoder or SKU changes.

## Behaviour

- Customer addresses already accepted locations beyond Vaniyambadi. Their
  location selector and saved-address behaviour are unchanged.
- The verified Merchant Edge handler uses the new service-only V3 submission RPC.
  Existing actor verification, evidence ownership, review and idempotency remain.
- New Grocery and Restaurant/Cafe applications are accepted at eligible Indian
  locations without requiring Admin to pre-create a city.
- The database checks the store pin against a private country outline, not a
  client-supplied country flag. Locations outside that outline are rejected.
- A valid first application establishes a bounded 10 km local service area.
  Existing areas are reused. New areas are clipped to the country outline and
  neighbouring boundaries; deliberately inactive areas are not bypassed.
- Applications remain pending. Existing Admin review provisions a branch only
  after approval, and approved branches still start closed/non-accepting.
- Existing customer gates remain unchanged: no active local Grocery merchant
  means unavailable; no merchant stock means no available items; no eligible
  online local delivery partner means cart only, not order placement.
- Food stores retain existing closed/removed visibility rules.
- No nationwide service zone, bulk city seed, automatic merchant approval,
  fabricated stock or online-partner activation was added.

## Source and accuracy

Eligibility outline: Natural Earth 1:10m admin-0 countries, pinned to v5.1.2,
public-domain data:
https://github.com/nvkelso/natural-earth-vector/blob/v5.1.2/geojson/ne_10m_admin_0_countries.geojson
https://www.naturalearthdata.com/about/terms-of-use/

This is operational eligibility data, not a legal/official border map or
parcel-level survey. Admin must still verify the exact business address and
documents. Border/coastal accuracy is limited by the source; an incorrectly
excluded legitimate location needs a reviewed coverage correction.

No additional geocoding requests were added. Existing explicit customer-driven
location lookup remains unchanged; it is not a newly scaled nationwide geocoding
service. Wider traffic requires reviewing the existing provider's usage limits.

## Verification

- 50 native PostGIS/SQL checks passed in one transaction that was rolled back.
- Tested Indian locations: Delhi, Mumbai, Bengaluru, Kolkata, Chennai, Srinagar,
  Leh, Guwahati, Itanagar, Port Blair, Kavaratti and Kanyakumari.
- Rejected sample locations in Pakistan, Nepal, Bangladesh, Sri Lanka and the UK.
- Exercised complete new-area Retail/Cafe submission, existing Admin approval,
  rejection/resubmission, closed defaults and inherited matching settings.
- Exercised replay, digest conflict, evidence failure, paused area and
  neighbouring-area isolation. Bootstrap audit records are emitted once.
- Anonymous/authenticated direct submission and private bootstrap execution
  remain denied; public wrapper is security invoker.
- Rollback proof: zero fixture accounts; exactly one original production zone;
  original boundary hash unchanged; migration objects not persisted at preflight.
- Existing merchant-handler and onboarding migration tests: 15 passed.
- Edge function type-check passed; Merchant form lint passed; web build passed.
  Existing large 3D bundle warnings are unrelated and were not changed.

## Release boundary

Only the India onboarding migration, Merchant Edge function and Merchant UI
copy are in scope. The unrelated pending catalogue-map activation migration
must remain excluded. Customer/Admin/Delivery sites do not need redeployment
for this additive server change. No Git push or real order is part of this task.

Production activation and verification will be recorded below after success.
