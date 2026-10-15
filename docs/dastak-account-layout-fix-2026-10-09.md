# Profile and Settings follow-up — 9 October 2026

The prior release did not resolve the user's account-screen complaint. Reproduction on the signed-in normal Customer address confirmed two remaining defects on release `a0a6be2`:

- At an 881px viewport the embedded account panel inherited two 216px grid columns. Settings actions narrowed to 174px and grew to 162–203px high, causing excessive wrapping and scrolling.
- Merchant loading used the generic `loading` class. Global `.loading span` spinner styling rotated the card's icon and entire text blocks, shrinking spans to 18px and producing horizontal overflow. This was also reproducible with synthetic data, so it is not an authentication or browser-specific issue.
- Embedded legacy screens rendered a second fixed-position skip link within a blurred glass containing block. Its supposedly hidden position was inside the viewport. The outer skip anchor also wrote an application-unrecognised hash.

## Changes

- Explicit single-column account layout at all panel sizes; container-based compact Profile formatting, fuller-width rows and separate identity-link actions.
- Merchant loading uses a namespaced card class. Only the actual loading icon animates; card text remains stationary.
- The legacy skip link remains in the standalone interface, but is omitted in embedded workspaces. Reimagined retains one keyboard-accessible shortcut that focuses main content without changing the route.
- Embedded navigation no longer scrolls the whole document; screen-change focus uses `preventScroll`.

## Verification

- Signed-in production reproduction included Profile editor open/close and Settings session dialog open/close without saving details, revoking sessions, linking identities or signing out.
- Local rendered browser check: at 881px the account column is 452px, rows are 426px wide and 68px high, rather than two narrow columns.
- At 390px, both Profile and Settings use one 330px column with no overflowing account descendants. Merchant card text and icon spans have `animation-name: none`; the small loading SVG is independent.
- Ordinary scrolling reached the final Settings action; returning to Profile reset inner scroll to zero. Phone Profile editor fits inside the viewport, uses 16px inputs, closes cleanly and restores its opening button's focus.
- Regression tests cover embedded versus standalone skip links, route-preserving skip activation, absence of document scrolling in embedded navigation, account grid rules and exclusion of the generic loading class.

## Release and final live verification

- Commit `d2cb3146345a2862cd6e9c504f3b8b827bafbfd8` pushed to `codex/dastak-v1-launch`.
- Full suite: 138 test files, 936 tests passed. TypeScript, targeted ESLint and diff checks passed.
- Customer production deployment `dpl_APE2QBRcYVh86xXBNnJUY7TzQBxY` reached READY. Release script verified the commit, Customer variant, production environment and normal alias `https://dastak-customer.vercel.app`.
- Reloaded the signed-in normal address: Settings now has one 452px column and full-width 426px actions at 881px viewport. Merchant/Delivery card spans have no animation. No embedded legacy skip link remains.
- Live Profile editor and session dialog opened and closed without account writes; focus returned to their opening buttons. Switching screens reset inner scroll without moving the page.
- With 390px device metrics, live Profile and Settings used a 330px column, page width remained 390px and account descendants had no horizontal overflow. Profile editor fit x=8..382, bottom=836 within 844px, with 16px inputs. Emulation was restored. Screenshot capture did not reflect device emulation reliably, so the proof is labelled desktop, not phone.
- Keyboard skip activation preserved `#/settings`, focused MAIN, and hid the shortcut afterward. No browser console errors were captured during final checks.
- Desktop proof: `verification/dastak-account-layout-2026-10-09/settings-live-881.jpg`.

This is a targeted correction, not a certification of all account saves or every Customer workflow. Profile saves, identity linking, session revocation and account deletion were not executed. SKU, background/staff, database and other-app production changes are out of scope. Final release evidence is a local report update, not an additional deployment-triggering commit.
