# Customer Settings and Food polish — 2026-10-09

## Scope and guard

- Solo execution in `.worktrees/wave1-runtime-ci`, branch `codex/dastak-v1-launch`, opening HEAD `f3ed17f650a8289d6911ec31b8aaf8dcddb2da4a`.
- Unrelated dirty documentation, catalogue tooling and unused staff assets preserved and excluded from this release.
- Customer web only. No database migration, backend deployment, Merchant/Admin deployment, SKU or background work.

## Reproduced and fixed

Five initially failing mounted tests reproduced callback-triggered session reloads, late expired responses after token rotation or sheet closure, duplicate device removal, and Food pagination incorrectly appearing above discovery/inside menus.

- Devices and sessions no longer reloads just because its parent creates a fresh callback.
- Requests are aborted/invalidated on sheet closure and token changes. Stale errors cannot expire the new/current account session or replace current device data.
- Device actions use a synchronous operation lock, not only disabled buttons; repeated clicks cannot submit twice. Failed actions preserve the device list and allow retry.
- Genuine current-session 401 responses still invoke the existing session-expiry handler. A test verifies this security behavior remains intact.
- Food pagination belongs after discovery/search results, never inside restaurant menus or dish details.
- Food loading/error/offline/empty/closed-store states have consistent readable presentation. Empty catalogue wording matches the approved area-availability wording. Closed restaurants remain visible and disabled.
- Restaurant menu intros show uploaded images when present, description, accepting status and honest distance context. No invented ratings, delivery estimates or images.
- Dish choices have aligned names and price deltas, checked-state feedback and 48px minimum rows. Required choices and cart eligibility are unchanged.
- DEV-only synthetic Food fixture gained closed-store and loading/error/offline/empty scenarios; it performs no backend or checkout requests.

## Verification before release

- Final full Customer suite: 141 files / 952 tests passed; TypeScript build and scoped ESLint passed.
- Focused mounted regression suite: 26 tests passed, including genuine session expiry and duplicate sign-out protection.
- Browser local menu/dish drill-down: required choice disabled Add; selection updated estimated dish price from 150 to 180 INR and enabled Add. No real cart/order was changed.
- Phone-width browser DOM check: viewport 390px, document width 390px; no horizontal page overflow. Browser screenshot capture scales the native view incorrectly, so this is a geometry check, not claimed visual phone proof. Temporary viewport overrides removed.
- Production user sign-in confirmed and Settings accessible. Safe opening/cancelling of account confirmations and sessions sheet checked; no sign-out, device revocation, account deletion, OAuth linking, export, notification permission or payment executed.
- Local proof: `docs/verification/dastak-settings-food-2026-10-09/food-options-local.png` (synthetic menu, not production catalogue).
- Browser empty-area scenario shows the approved unavailable wording and preserves cart messaging.

## Release

Customer-only production release completed (post-release evidence appended locally).

- Commit `1945c26dff04664e201d6523c25714c6bf5870e9` pushed to `origin/codex/dastak-v1-launch`.
- Deployment `dpl_DT95neH1cWueAmBoDxUakYuzAhHs`: READY, production, Vite/React, 75-second build.
- Normal address: https://dastak-customer.vercel.app/ ; immutable build: https://dastak-fe9y3qcgl-liquiflows-projects.vercel.app/ .
- Normal-address HTML provenance matches the commit, Customer variant, production environment and deployment ID; CSP and nosniff checks passed.
- Production tab refreshed: matching commit confirmed; account stayed signed in and Settings loaded.
- Devices and sessions finished loading without an alert; current device present. Closing restored trigger focus and cleared modal/body scroll lock. No devices removed.
- Help with an order opened Orders; Edit your Profile opened Profile. Both screens had one main heading.
- Sign-out confirmation focused Cancel; cancellation restored its trigger. Delete Customer confirmation focused Keep Customer; cancelled without entering DELETE or submitting.
- Real Food discovery showed Craft; menu and Cappuccino detail loaded with uploaded images. The current area displayed the no-delivery-partner warning; no live cart or order changed.
- Production proof: `docs/verification/dastak-settings-food-2026-10-09/food-menu-production.png`.
- Narrow Vercel error-log scan for this deployment (last 10 minutes) returned no entries. This is not comprehensive monitoring; drains configuration was not inspected.
- Three new-SHA non-production queued/building previews cancelled to save build use. Merchant preview was already READY and left intact. No other production role changed.

## Not claimed

This pass does not certify every Dastak feature or every remaining UI bug. Real account mutations and live Food ordering are not exercised by these read-only checks. Synthetic menus do not imply restaurants exist in the selected production service area.
