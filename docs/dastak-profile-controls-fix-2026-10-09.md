# Customer Profile controls — 2026-10-09

Scope: profile editor, saved-address management, Wishlist and Payments. Worktree `wave1-runtime-ci`, branch `codex/dastak-v1-launch`, opening HEAD `d2cb3146345a2862cd6e9c504f3b8b827bafbfd8`. Unrelated dirty edits preserved. Solo execution, no new dependencies.

## Reproduced and fixed

- Profile submit handler previously called Save even while busy when a submit event reached it. Added handler guard, beyond disabled controls.
- Nested address-delete confirmation previously retained focus behind the confirmation. It now uses the existing layered modal hook, initially focuses Keep address, contains keyboard focus, makes background controls inert, and restores the delete opener on Escape without dismissing the address book.
- Deletion callbacks previously resolved after caught failures, so the confirmation treated failure as success and closed. Callers now return an explicit boolean result; confirmation closes only after success. Reported failures remain visible for retry, unexpected rejections are contained, and pending duplicate deletion calls are blocked. Existing Reimagined retry idempotency keys remain stable.

No API endpoint, database, authentication, checkout, SKU or environment configuration changes. Shared component compatibility updated in legacy Customer and Reimagined callers. Other role deployments excluded.

## Verification

- Initial new regression checks: 3 failures demonstrated busy-submit, incorrect initial focus and premature confirmation dismissal.
- Final complete frontend test suite: **140 files, 945 tests passed**.
- `npx tsc -b`, targeted ESLint and `git diff --check` passed.
- Browser, synthetic local preview: confirmation focuses Keep address; background is inert. Escape removes only confirmation, restores Delete Preview address 1 focus, leaves parent dialog open and body scroll locked. No delete request sent.
- Screenshot: `verification/dastak-profile-controls-2026-10-09/address-confirmation-local.png` (local synthetic data).
- Signed-in production before release, read-only: Profile Manage opens saved addresses; close restores Manage focus. Payments opens Payments at `#/payments`. Wishlist opens Your Wishlist at `#/wishlist`, each in one main panel.
- Real profile saves, address additions/edits/deletions, payments, session revocation and sign-out deliberately not executed. Request failure/success paths use mocked local tests.

## Release

Customer-only production deployment pending at commit time. Final release evidence will be appended after provenance and signed-in browser verification; it is not a claim that the entire Dastak audit is complete.

### Verified release (local evidence appended after deployment)

- Committed and pushed `f3ed17f650a8289d6911ec31b8aaf8dcddb2da4a`.
- Customer production READY: `dpl_6o1Ddu8sAuReiTgccFN12iQdWnqj`, Vite build 96 seconds, unique URL `https://dastak-l5mxsrjnk-liquiflows-projects.vercel.app`.
- Normal address `https://dastak-customer.vercel.app` serves matching commit, Customer variant, production environment and deployment ID. CSP frame-ancestors and nosniff checks passed.
- Signed-in browser reload loaded the new SHA and Wishlist. Profile saved-address manager opens and closes with restored opener focus; profile editor opens and Cancel returns to Profile with body unlocked. Payments loads with one main heading; no captured console errors.
- No live account edits, address writes or payment transactions performed. Failure/retry and form-submit paths were verified with local tests, not a real production mutation.
- All four automatic non-production builds for this exact push were cancelled while queued/building to avoid redundant builds. No other role production deployment changed. Production error-rate monitoring/log drains were not audited in this targeted pass.
