# Local Trending release — 14 October 2026

Grocery Home now receives real local popularity through the existing authenticated, address-version-bound area-availability request. Both native Customer and Reimagined Customer web display the returned products through their existing grouped cards, exact-size picker, wishlist, stock controls and basket pickup flow.

## Ranking and privacy

- Delivered orders from the last 30 days, within 30,000 metres of the selected delivery address (same 1 mm geodesic-boundary tolerance as service availability).
- Count distinct completed orders per genuine product family, then latest delivery and stable family key. Quantity does not let one bulk order dominate. Cancelled, old, remote, unlocated and refunded lines do not rank.
- Require an available exact pack at a currently eligible nearby merchant. Retain other active, verified-image sizes in that family's picker. Exclude controlled categories from this ordinary Grocery discovery flow.
- Return only current public catalogue product projections. No customer, address, order identifier or popularity-count data is returned.
- Private ranking helpers have no EXECUTE grant to app roles. Existing address ownership/version, stock, rider, pause and service-area functions retain their guards.
- iOS refreshes area data while active and on foreground; web reuses its batched refresh. Failed, expired and changed-location/session data cannot supply the trending shelf. An empty successful ranking is distinct from missing/error data.

## Verification

- Disposable PostgreSQL logic fixture/assertions pass. This fixture uses point geometry as a stand-in and is not presented as PostGIS distance verification.
- Actual linked PostGIS schema migration dry-run passed inside BEGIN/ROLLBACK with protected-function checks; ranking execution measured approximately 33 ms for the sampled area.
- 474 native DastakUI tests pass, including ranked exact-product resolution, clearing on failures/stale data, empty-vs-missing history and duplicate-SKU rejection.
- 1,059 web tests across 148 files pass; ESLint passes. Focused cases include every size beyond the twelfth pack staying in one product card, ranking order, duplicate rejection, and stale/session/offline clearing.
- Simulator preview showed the Trending heading, product cards, one Milk card with two sizes, detail actions and existing basket controls. Sample ranking is explicitly labelled; no live order or basket mutation was used for this visual check.
- Simulator and signed iPhone Build 25 succeeded; signature and diff checks passed. Build 25 installed on physical iPhone and independently confirmed in device inventory. After the user unlocked the phone, normal production launch succeeded. Device Hub visibly showed real Aavin Full Cream Milk and Aavin Delite Milk cards under Trending in your city, with the existing catalogue Quick picks also loaded. No preview flags, order, basket or wishlist changes were used. Physical screen evidence: `/tmp/dastak-local-trending-iphone-live.png`. Device Hub did not support remote scrolling in this check; visual verification covers the visible Home shelf, not a physical-device purchase or size-picker interaction.

Evidence logs: `/tmp/dastak-local-trending-database.log`, `/tmp/dastak-local-trending-preflight.log`, `/tmp/dastak-local-trending-tests.log`, `/tmp/dastak-local-trending-web-all-tests.log`, `/tmp/dastak-local-trending-web-lint.log`, `/tmp/dastak-local-trending-simulator.log`, `/tmp/dastak-local-trending-device.log`.

## Activation

Applied only `20261013233951_customer_local_trending.sql`, transactionally with its matching migration-history entry. The unrelated pending `20260929191745_activate_reference_catalogue_browse_map.sql` was not applied. No order, inventory, merchant, fee or payment records were changed.

Live database verification finds nine existing saved-address areas with results. Sample default-area rankings return Aavin Full Cream Milk, Aavin Delite Milk and Aavin Nice Toned Milk. This is real delivered-order history, not a seeded ranking. Privacy/ownership and migration checks are in `/tmp/dastak-local-trending-live-verification.log` and `/tmp/dastak-local-trending-security-verification.log`.

Customer web is live at https://dastak-customer.vercel.app/ using deployment `dpl_5M8K1iyk8ktCnSNUWuzgbFxtjKnc` (https://dastak-9lmd6se7a-liquiflows-projects.vercel.app). Only Customer was deployed. The staged artifact's initial unauthenticated probe encountered deployment protection; authenticated `vercel curl` verified the production variant, metadata and security headers without changing protection. That exact artifact was promoted; normal-domain HTML independently confirms its deployment ID and `dastak-customer` variant.

Deployment is from the working-tree source based on HEAD `94f531d679e6dcca1bd588ab63c5000b1eb2c620`, not a new commit. No Git commit/push was performed. Deployment logs: `/tmp/dastak-local-trending-web-deploy.log`, `/tmp/dastak-local-trending-web-promote.log`.
