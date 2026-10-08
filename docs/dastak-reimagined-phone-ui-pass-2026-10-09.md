# Dastak Reimagined — phone UI pass, 2026-10-09

Scope: English-only UI, phone layout and address-dialog usability. Urdu remains only in the previously approved brand wordmark. SKU/content classification, background redesign, production deployment, database/account writes and real OAuth/order requests are excluded.

Guard: worktree `wave1-runtime-ci`, branch `codex/dastak-v1-launch`, HEAD `9c754a787fad0ec7a4612865657d168d0d02362f`. Existing branding/sign-in edits and catalogue review artifacts were preserved.

## Findings and fixes

1. **Location list ran off-screen.** At 390×844 with ten synthetic addresses, the panel extended from y=68 to y=1193.86, making management controls unreachable. It now scrolls within a bounded panel (y=68 to y=658.80); its close heading remains sticky. Browser interaction successfully reached and opened management.
2. **Fixed address sheets were nested inside backdrop-filter panels.** Both address book and editor now render through a body portal, retaining customer styling. The browser confirmed the backdrop fills 390×844 and the portal is a body child. No address mutation was invoked. Regression tests preserve request-key reuse and offline write prevention.
3. **Modal keyboard isolation needed to include body siblings.** The shared modal hook now isolates sibling application roots, restoring their original state on close. The editor now uses the same focus trap/scroll lock/close focus as the book. Tests cover both portalled dialogs and focus return; browser Escape closed the book and restored the management button.
4. **Search relied on fixed pixel offsets.** A zero-height anchor positions search eight pixels below the actual heading, preserving the centre shelves while typing. Verified at 390×844, 320×568 and desktop 1280×800. At desktop, heading bottom was 192.375 and search top 200.375. At 320×568, heading bottom was 305.977 and search top 313.977.
5. **Short-phone navigation covered content after page scrolling.** At 320×568, focusing search scrolled the document while navigation stayed fixed over the title. Navigation now scrolls with other top controls in the existing short-height mode. Browser screenshot confirms the title is unobstructed.
6. **Phone branding overlapped navigation slightly.** At 390×844 the brand ended at y=65.79 while navigation began at y=62. Smaller phone English/Urdu brand sizes now end at y=47.40, leaving separation without changing the font or wordmark.

Address-dialog buttons now have a minimum 44px target and the book's close header stays visible while scrolling.

## Verification

- All 920 tests in 136 files passed.
- Targeted ESLint passed for edited components, hook, tests and DEV fixture.
- TypeScript and production build passed; the existing large-chunk warning remains.
- `git diff --check` passed.
- Browser fixture: `/reimagined-feature-check.html?phone-audit`, actual UI components with synthetic catalogue/address data and an inert background. No live session, delivery address, inventory or order was changed. No API credentials were used.
- Browser: search typing retained quick picks; Escape restored search-button focus; opening and dismissing the saved-address dialog worked; final browser warning/error log was empty. Temporary viewport overrides were reset.
- Screenshot evidence: `verification/dastak-phone-ui-2026-10-09/search-320.jpg`, `search-390.jpg`, `addresses-390.jpg`.

## Still to verify

This batch does not certify all application screens. Orders, Payments, Profile, Settings, Food-specific screens and the full checkout flow still need a dedicated phone visual pass with their real presentation components and safe data. This local fixture intentionally does not represent signed-in account/server behaviour. Physical-device keyboard/safe-area behaviour and current Safari rendering were not tested in this pass.

No push, deployment or production mutation occurred.
