# Reimagined account and order workspaces — 2026-10-08

Owner approved the next presentation pass after the feature-restoration release. Scope: separate Profile/Settings and consistent Orders, tracking, receipts, payment history and support, reusing established controllers. Background/staff, catalogue inventory, authentication, database and payment policies are unchanged.

## Implemented

- `CatalogueView` has an explicit optional account pane. Profile renders identity/contact information, saved places, shopping shortcuts and partner-workspace access. Settings renders notification preferences, help/safety, policies, data export, devices/sessions, identity linking, sign-out and Customer deletion. Controls keep their existing handlers and confirmations. Without a pane, the previous full Account screen is unchanged.
- Reimagined selects the pane from its global navigation. Cross-links select the other global pane. Account order shortcuts and payment-history records route into global Orders; a nested Payments view updates the panel title. Closing a deep-linked record clears the initial record identity.
- Orders and payment history use inner headings and Reimagined styling rather than duplicating the shell heading. Order details render in the scrolling panel as an accessible region. The underlying list is hidden/inert while the record is shown; global navigation stays available. Back returns to the list and restores its focus/scroll when there is an originating list control.
- `useModalDialog` remains enabled by default. Only inline order records opt out of isolation/scroll locking; other account/security/confirmation dialogs retain their existing modal behavior. Escape closes an idle record, not an active support/cancellation sub-flow.
- Tracking, delivery PIN, server totals, receipt download, issue evidence validation, cancellation, returns/refunds and reordering keep their existing data/actions. Recovered-order confirmation stays inside the panel with unchanged version/idempotency rules and UPI/Cash on Delivery.
- Fixed legacy sheet-header negative margins, the short-screen page minimum width and order-filter sizing that caused horizontal overflow. Overrides are scoped to Reimagined.

## Verification

- Full web suite: **797 passed, zero failed**. TypeScript, ESLint, whitespace checks and production build passed. Existing large 3D chunk warnings remain.
- New tests cover separate panes, unchanged legacy Account, inline versus modal semantics, navigation/body isolation, receipt/support affordances, payment headings/amounts, pane propagation and global record navigation.
- Browser checks used actual components rendered to a static synthetic preview on localhost. At 390×844 and 320×568, Profile/Settings, Orders, order details and Payments were inspected; the identified header/filter/min-width issues were corrected. Final short-phone Orders measured page width/scroll width 305/305 and panel width/scroll width 240/240. No captured browser console errors.
- Evidence: `/tmp/dastak-reimagined-profile-2026-10-08.png`, `/tmp/dastak-reimagined-settings-2026-10-08.png`, `/tmp/dastak-reimagined-order-record-2026-10-08.png`.
- Static preview intentionally does not run effects or account requests; actions are not interactive and synthetic loading states are not evidence of production failures. Regression tests cover the interactive wiring. No production account/security/support/order/payment action was performed.

## Status and limits

Local implementation only: no commit, push, deployment or migration in this pass. Production remains the earlier `9850a79` release until explicitly deployed. This is presentation parity, not certification of real checkout/merchant/delivery/payment fulfilment. Parcel/Print, city trending, menu-loading limits and old mixed-order rebuilding remain as documented separately.

## Production release preparation — 2026-10-08

Owner's follow-up “go ahead” authorizes pushing and deploying the completed workspace pass to Customer production. The local-only checkpoint above remains historical. Release checks rerun the full suite, lint and TypeScript; the completed production build is retained as evidence. Deployment uses the guarded Customer archive workflow, excluding the two untracked RPM avatars. Merchant/Admin/Delivery and database migrations are out of this release. Actual SHA, READY status and live normal-address verification are reported in the deployment handoff; production checks are read-only.
