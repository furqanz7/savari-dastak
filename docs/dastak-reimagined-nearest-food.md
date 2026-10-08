# Nearest-first Food — implementation and release, 2026-10-08

Status: production rollout completed. The single migration and catalogue Edge
Function are applied to linked Dastak, and Customer is live on the normal URL.

## Behaviour

- Food entry reads the existing saved-address resource. The selected address (or
  saved default) supplies the origin; no GPS prompt, address write or device
  location transfer is added. With no saved location, existing catalogue order
  remains available and the UI explains that it is not nearest-first.
- The new authenticated `customerRestaurantNearestPage` operation sends only
  address ID/version, search, page size and cursor. The private RPC verifies the
  actor and address ownership, then measures straight-line branch distance with
  PostGIS geography. Raw address or branch coordinates are not returned.
- The server ranks all eligible restaurants before selecting at most 100 menus.
  Distance/name/branch-ID cursors preserve equal-distance ties across pages.
  Missing branch locations sort last and display Distance unavailable, not 0m.
  Global restaurant/dish search uses the same distance ordering.
- Address changes abort old requests, hide stale results immediately and start a
  fresh cursor. A changed saved-address version is rejected by the server.
  Cached suggestions, explicit Load more and exact-branch reorder lookup remain;
  neither cart, checkout eligibility nor order/payment submission is changed.
- Older alphabetical endpoints are untouched. Distances are not road distance,
  delivery estimates or proof of serviceability. No artificial trending is added.

## Evidence and limitations

- Final gates: **854 web tests / 127 files**, **27 catalogue Edge tests**, ESLint,
  TypeScript, Edge runtime type check and production build passed. The build
  retains the existing warning about large graphics chunks.
- Web unit/integration tests cover address propagation, waiting for the location
  read, stale-response cancellation, distance sorting, unknown-location labels,
  invalid/mismatched responses, query pagination and unchanged shopping.
- Catalogue Edge tests validate authenticated forwarding and reject mixed address
  cursors, invalid distances, oversized pages and malformed input.
- `supabase/tests/run_customer_food_pages.sh` executes the old and new migrations
  in an isolated disposable PostgreSQL cluster. The new assertions cover 205
  restaurants (including equal names/distances), one-row pages through missing
  locations, search beyond the old cap, changed origin, address ownership/version,
  actor guards, closed/paused visibility and function grants.
- **PostGIS is absent on this Mac.** The new SQL harness explicitly uses a
  deterministic distance stand-in; it verifies SQL paging/security logic, not
  real geographic calculations or compatibility against the complete linked
  schema. This limitation was resolved by the linked real-PostGIS checks below.
- A 390×844 Codex-browser preview shows 350m, 2.5km and unknown-location cards in
  the correct order; menu category filtering retains it. This is synthetic data,
  not production evidence. Screenshot: `/tmp/dastak-nearest-food-mobile-2026-10-08.png`.
- No commerce/account data writes, live orders/payments, subagents or model-generation APIs.
  Known large graphics chunks remain outside this pass; staff assets untouched.

## Approved production rollout

- Verified linked PostGIS 3.3.7 in `extensions`, actual branch/address geometry
  columns, address versions, menu builder and caller-bound active-customer guard.
- Installed the exact migration in a rollback-only transaction and exercised the
  public wrapper as `authenticated` with an existing saved customer origin. Real
  geographic distance, nonempty response, distance order, anonymous denial,
  authenticated grant, stale address rejection, other-owner address rejection and
  actor mismatch checks passed. The test transaction rolled back its DDL.
- Read-only plan inspection of the eligible branch distance ordering returned one
  live eligible restaurant, an in-memory 25KB sort and 56.619ms total execution on
  this sample. This is not evidence of performance at a larger production scale.
- Applied only migration `20261008084004` and its history in one transaction;
  verified anonymous execution false and authenticated execution true. Unrelated
  pending `20260929191745` was not replayed or marked applied.
- Deployed only `dastak-v1-catalogue` to linked project `zmtsolkfxlrxepshnjdf` before
  publishing Customer; its status is ACTIVE, version 25. Pre/post-release advisors returned six existing
  warnings (public authenticated security-definer functions and leaked-password
  protection), not a clean whole-platform audit; those are outside this rollout.
- Customer project/root/variant guard and remote branch guard passed. Existing
  unrelated untracked RPM staff assets remain excluded from commit/deployment.

Release sequence:

1. Verify the linked branch/address geometry columns, PostGIS and actor guard
   read-only; exercise the migration against real PostGIS in an isolated test
   transaction/environment and inspect privileges/query plan.
2. Apply only `20261008084004_customer_food_nearest_pages.sql` to linked Dastak.
   This creates read-only functions/grants, not order/inventory/account updates.
   Do not replay unrelated pending catalogue-map migrations.
3. Release `dastak-v1-catalogue`, then commit/push and deploy Customer with the
   guarded Customer deployment script. Do not release the frontend first.
4. Verify the normal production URL, selected-location distances, search/paging,
   address change and no-location fallback without commerce/account mutations.

## Customer release and live evidence

- Pushed feature commit `d1a2db2af754fbd59556d0c13ff38dad45971161` to
  `origin/codex/dastak-v1-launch`. Deployed Customer only via the guarded script.
- Vercel deployment `dpl_7xQDYBy7jzokjPwTN8s9VjnTGkRK` is READY / production,
  unique URL `https://dastak-pstpphddz-liquiflows-projects.vercel.app`, normal alias
  `https://dastak-customer.vercel.app`. Vite build: 59.20s; existing large-chunk
  warning remains. Normal alias HTML and browser metadata matched the feature SHA,
  Customer variant and deployment ID; required CSP/nosniff headers passed.
- Signed-in production Food displayed Nearest first and Craft at 1m from the
  selected saved Home origin. Explicit Espresso search returned Craft with its
  distance plus Espresso; Hot drinks filtering retained Craft and its distance.
- A 390×844 production check showed the restaurant and distance without document
  horizontal overflow. Proof: `/tmp/dastak-nearest-food-production-mobile-2026-10-08.png`.
  The temporary viewport override was reset afterwards.
- This account has only one saved address and the database currently exposes one
  eligible restaurant. Live address switching, multi-page/tie ranking and no-saved-
  address fallback were not exercised; isolated tests cover those paths. No saved
  default, address, cart, order, inventory, account or payment was changed.
- Browser captured no warning/error entries. Vercel's deployment-scoped error log
  query for the last 10 minutes returned no entries; this is not proof about all
  Supabase runtime traffic. Log drains and whole-platform monitoring were not
  configured or audited in this release.

Genuine city trending, missing owned Food images and operational end-to-end
verification remain separate tasks; this does not complete the whole-platform audit.
