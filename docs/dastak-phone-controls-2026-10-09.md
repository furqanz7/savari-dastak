# Customer phone and Settings request pass — 2026-10-09

Scope: Profile, Settings and Food phone interaction only. No SKU, background, backend schema, account deletion, live device revocation, OAuth or live ordering changes.

## Confirmed fixes

- Profile Save was unnamed in the browser accessibility tree because its label lived in a status region. Give both idle and busy states explicit accessible names.
- Settings export accepted two queued clicks before React disabled the button. Add a synchronous per-request-lifetime lock.
- An old export 401 could sign out the user after navigating to Profile, refreshing the token or unmounting the account screen. Invalidate the old lifetime and ignore both stale failures and stale successful downloads. Keep current genuine 401 handling.
- Tests reproduced all four export failures before the implementation fix.

## Verification

- Synthetic Profile at 390×520: whitespace validation appears, Cancel and Save remain reachable, Cancel restores focus to opener and unlocks body scrolling. This is a short viewport test, not a physical iPhone keyboard test.
- Signed-in production at 390×844: Settings renders its groups; Profile loads real details; editor opens and cancels without saving; repeated Settings → Profile → Home leaves no dialog, no body scroll lock and no horizontal document overflow.
- Synthetic Food at 390×844: closed restaurant visible with disabled tap; menu and options open; required option blocks Add until selected; Large adds ₹30 to ₹150 (₹180), local cart review agrees, Continue Shopping returns to menu. No hosted cart or order changes.
- Mocked Settings tests cover export retry, queued clicks, genuine/stale 401, stale success, current JSON download, eight order-alert presentation states and notification retry without a real permission request.
- Screenshots: `verification/dastak-phone-controls-2026-10-09/profile-short-viewport.png`, `food-options-phone.png` (synthetic data only).
- Temporary browser viewport overrides restored after checking.
- Full suite: 971 tests / 142 files passed. TypeScript build, scoped ESLint and `git diff --check` passed. Browser identifies the corrected Save button by name.

Release verification will be recorded after deployment. Do not interpret this bounded pass as proof that every app interaction has been audited.
