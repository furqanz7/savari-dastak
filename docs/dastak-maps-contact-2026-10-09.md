# Customer rider contact and shared interactive maps

## Delivered behaviour

- One prominent Call delivery partner action on active customer delivery tracking,
  from assignment through delivery. No GPS fix is needed to call. Completed and
  cancelled orders expose no call action. Missing phone has explicit status text.
- Fixed the literal-plus regex in the existing restricted delivery projection;
  no new phone endpoint, grants or access widening. Numbers remain valid E.164.
- Address suggestions appear after 3 characters / a 650 ms typing pause. English
  India results, bounded five-minute memory cache, cancellation and stale-result
  guards. Typing is never blocked by suggestion requests. Keyboard selection works.
- Editable map: tap the map, drag the pin, or use arrow keys on the focused pin;
  exact coordinates flow into the existing save-address APIs. Reverse lookup is
  debounced, cancellable and cannot override a newer pin or a save in progress.
  Lookup failure keeps exact coordinates and asks for building/landmark details.
- Shared Leaflet map replaces every Dastak OpenStreetMap iframe: Customer location
  and tracking, Merchant store-location onboarding and tracking, Delivery map,
  and existing Parcel address/route surfaces. Existing external directions remain.
- Zoom, recenter, metric scale, clear coloured geographic markers, resize handling
  and touch-friendly responsive controls. Displayed dashed links are explicitly
  not road-routing/ETA authority; live/last-known location rules unchanged.

## Cost and provider limits

No paid service/subscription or AI API was added. Leaflet 1.9.4 is lazy-loaded.
OpenStreetMap standard tiles retain attribution, browser caching and a map-only
strict-origin referrer; the application's overall no-referrer policy stays intact.
Photon supplies autocomplete/reverse lookups: public demo usage must remain
reasonable, can be throttled and has no availability SLA. A dedicated geocoder
and tile provider should be configured before substantial traffic. Not suitable
to claim guaranteed nationwide street/house-number coverage from public OSM data.

References: [Nominatim autocomplete prohibition](https://operations.osmfoundation.org/policies/nominatim/),
[Photon usage and availability limits](https://github.com/komoot/photon#demo-server),
[OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/).

## Verification

- Native SQL preflight uses the actual restricted projection definition with
  temporary table copies. All seven active mission phases return a valid phone
  without GPS; malformed numbers/unassigned/unknown missions fail closed; direct
  anon/authenticated grants remain denied. Entire transaction rolls back.
- Browser verified real Photon suggestions for Mysore, selection, touch-size
  layout at 390 x 844, exact coordinate changes after dragging and keyboard edits,
  loaded OSM tiles with strict-origin referrers, and no errors in a fresh tab.
- Browser testing caught and fixed a marker-focus/redraw loop: stable coordinate
  signatures, tooltip cleanup and no-op blur state updates prevent feedback.
- Screenshot uses a synthetic public Mysore point, not a personal address.
- No real phone call, order, payment or delivery assignment was created. Calling
  still needs the device's phone app (or configured desktop call handler).
- Admin has no embedded map using these components and needs no UI redeployment.
- Security advisor ERROR scan: no issues found. Lower-severity findings were not
  asserted clean. Existing 30 km availability, rider gates and fees are unchanged.

## Production release

- All 148 frontend test files / 1,040 tests passed; TypeScript, changed-component
  ESLint and local production build passed. Existing 3D large-chunk warnings remain.
- Only `20261009134004_repair_customer_rider_phone.sql` applied to linked Dastak.
- Native contact projection harness passed before and after release.
- Source release `1e2c92facd5df7047b5560f4cb2100cbc55b3b67`:
  - Customer READY: `dpl_DfqK5CFWHcg2Hq1p6xHNPJZvcf3H` at https://dastak-customer.vercel.app/
  - Merchant READY: `dpl_6o8p5b2heZR1m5htx6rZN63yNHXS` at https://dastak-merchant.vercel.app/
  - Delivery READY: `dpl_8r9BcYzCTxp3vJeYt9j7FQn1yoaW` at https://dastak-delivery.vercel.app/
- Production HTML verified each role's SHA, variant, production environment and
  deployment identity. Customer/Merchant CSP allows map tiles and Photon requests;
  overall no-referrer remains intact.
- Error-level release-log scans had no entries; this is not a signed-in production
  order/calling test, nor an assessment of monitoring/drains configuration.
- Existing 30 km rule still present and unrelated catalogue activation remains
  unapplied. Existing dirty documents/assets were preserved. No Git push performed.
- Temporary local verification pages, test browser tabs and migration staging
  copies removed; browser viewport reset. Screenshot retained in verification docs.
