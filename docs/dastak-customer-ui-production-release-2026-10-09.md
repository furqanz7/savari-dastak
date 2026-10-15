# Customer UI production release — 9 October 2026

## Release

- Source commit: `fbb880d33c0fb82864ff2410dfa98b6595effe3f` (`fix(dastak): release Reimagined branding and phone UI repairs`).
- Pushed branch: `codex/dastak-v1-launch`; remote SHA independently checked.
- Vercel project: `dastak`, ID `prj_Wy48d7Vv3OXLAgulBukYHoXiXy0f`, root `Web/MarketplaceWeb`.
- Production URL: https://dastak-customer.vercel.app/
- Deployment: `dpl_C7VPivWWQCU2ERTkPESPmkFA8ks7`, READY, https://dastak-415njfz62-liquiflows-projects.vercel.app/.
- The normal production URL's HTML and browser metadata match the source SHA, `dastak-customer` variant, production environment and deployment ID. Security-header verification passed through the existing role-specific deployment script.

## Scope

Released the completed bilingual-brand-wordmark/English-UI, outside sign-in presentation, provider-loading, phone search/location/layout, address-dialog/focus, shared account-modal and light-panel contrast fixes from the three local reports. No new SKU or database work, backend deployment, account change, real order/payment, stock write or staff redesign was performed.

Preserved unrelated dirty catalogue-review files and two unused staff assets. Only the reviewed Customer UI files, local fixtures/tests, their reports and synthetic screenshots were committed. Local-only fixtures are not application entry points. The deployment script excludes environment files and unused staff assets; it targets Customer explicitly rather than relying on the web folder's Admin link.

The push also carried seven previously committed, completed changes already in branch history; it did not commit unfinished catalogue drafts or apply their database changes. Git integration started automatic previews. The three still-queued Customer/Delivery/Merchant preview deployments from this exact SHA were cancelled to avoid unnecessary build work. The already-complete Admin preview was retained. Other apps' production aliases were not changed.

## Verification

- Full web suite rerun: 137 files, 924 tests passed. Targeted ESLint passed. Vercel production install/build completed successfully. Existing large 3D bundle warning remains a performance follow-up, not fixed here.
- Safari: existing Customer session survived loading the new release. New wordmark rendered. Profile loaded and its actual editor covered the full browser content area with readable colours and a focused name field. No values were edited or saved.
- Safari's active tab changed during verification; further interaction was stopped to avoid interfering with the user's tab.
- Codex browser, live normal URL: Settings loaded notification/account controls plus Merchant/Delivery entries; the devices/sessions dialog was body-portalled, isolated the app, fitted the 390px viewport and closed without revocation. Orders/history and a read-only existing order record loaded. Payments loaded confirmed history. Both details and payment text computed as `rgb(40, 35, 29)` with system dark mode enabled.
- Live Food restaurant/menu loaded; no item was added. At 390px the checked Settings/order/Food content remained horizontally bounded. The page's 375px scroll width reflected the viewport's scrollbar rather than horizontal overflow.
- Grocery home and Food both showed the regional no-delivery-partner notice. No real checkout reservation/submission was attempted. Both cart/billing visual flows remain covered by the prior synthetic tests, not a new live end-to-end checkout certification.
- Session stayed signed in throughout the signed-in browser checks. This is not certification of indefinite session lifetime or a fresh OAuth round trip.
- Vercel's deployment-specific error query returned no logs; this static frontend result does not establish backend observability. The only captured browser console error was from Vercel's login page during a protected deployment-URL check, not from the Customer page.
- Temporary phone emulation was cleared and browser sizing restored. Agent-created verification tab was closed; user tabs were not closed or signed out.

## Explicit limits

The signed-out production UI was not browser-verified in this pass: both normal browser contexts already had sessions, and the unique deployment URL required Vercel authentication. No session was cleared and no deployment protection was weakened. Outside sign-in presentation had previously passed production-built local tests and is included in this release.

Physical-phone/Safari software-keyboard verification, destructive account actions, OAuth renewal and end-to-end fulfilment/payment remain pending. The final default-width browser screenshot also shows crowding between the wordmark and location pill at an intermediate width; this needs a separate responsive-header follow-up. Remaining UI/UX work is not declared complete. SKU work remains postponed.

Local proof: `docs/verification/dastak-customer-release-2026-10-09/live-customer-home.jpg`. This release report and live screenshot are kept locally rather than triggering another set of preview builds solely for documentation.
