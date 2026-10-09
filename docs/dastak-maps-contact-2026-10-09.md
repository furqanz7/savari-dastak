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

Release status and final test totals are recorded after deployment below.
