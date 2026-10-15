# Account navigation behaviour check — 9 October 2026

Scope: Home, Orders, Profile and Settings navigation, panel scrolling, browser Back/Forward and read-only dialog dismissal. Existing release: `d2cb3146345a2862cd6e9c504f3b8b827bafbfd8`. No application changes or production deployment in this pass.

## Direct production checks

- Signed-in normal Customer address at 881px: Settings → browser Back restored Profile (`#/account`); Forward restored Settings (`#/settings`). One Reimagined main panel, no leftover dialogs.
- Scrolled Settings to inner scroll 1036; final action bottom 700.8px was within content bottom 725px. Document scroll remained zero.
- Settings → Home → Orders reset inner scroll to zero; Orders heading and `#/orders` agreed. No document jump.
- Profile editor opened with focus inside its dialog. Cancel closed it, preserved `#/account`, and restored Edit profile focus without saving.
- At 390×844 device metrics: page width 390px, main panel width 366px. Settings PageDown moved inner scroll to 379px while document scroll stayed zero. Profile reset scroll; browser Back restored Settings with scroll zero and no dialogs.
- Phone-width Profile editor Escape closed the dialog, restored Edit profile focus and released the body scroll lock. Return Home restored `#/home`, selected Home and zero inner/document scroll.
- Temporary device metrics cleared. Final normal-width Settings had one main panel, matching heading/route and zero inner scroll. Captured browser console had no error entries.
- Browser connection reset during the initial batch; that interrupted batch was not counted as passed. Checks resumed using the current tab and shorter action sequences. Device-emulated screenshot output is unreliable in this browser, so no screenshot is claimed as phone proof.

## Automated checks

`npx vitest run src/ReimaginedCustomerRoot.test.tsx src/ReimaginedShell.test.tsx src/useReimaginedNavigation.test.ts src/DastakCustomerView.reimagined.test.tsx src/account-dialogs.test.tsx src/reimaginedResponsive.test.ts`

Result: 6 files, 91 tests passed, duration 2.37s.

## Boundaries

No newly failing navigation boundary was reproduced. This is not certification of profile saves, address mutations, identity linking, notification permissions, export, revocation, sign-out or deletion. None of those actions was executed. No SKU, background, database, environment or production configuration changed.

Proof: `verification/dastak-account-navigation-2026-10-09/settings-after-navigation.png`.

Next scoped pass: Profile editor validation and address/shopping entry controls, using synthetic local state for writes and read-only production checks.
