# Dastak Reimagined — branding and sign-in pass

Scope: restore the previous Dastak font and Urdu wordmark, and bring the approved outside environment to Customer sign-in. SKU work is deferred. No production deployment, database changes, account changes, or real OAuth requests were made in this pass.

## Implemented

- Restored Instrument Serif from the existing licensed local font asset, and the Urdu `دستک` wordmark. Both Reimagined sign-in and the signed-in header use the same component. Urdu is directionally isolated from English.
- Retained the existing system font for interface text. This is not a new typeface or logo redesign.
- Removed development-only exterior gates that previously stripped the outside scene from production builds. Local staff/debug controls remain development-only.
- Replaced exterior source-directory texture paths with production-bundled asset URLs. Exterior geometry and textures are initialized only when outside is requested.
- Added a lightweight outside illustration while graphics load, when WebGL is unavailable, or after context loss. Sign-in does not depend on the decorative renderer.
- Removed old onboarding-container width/overflow constraints only for Reimagined signed-out presentation.
- Restored Apple/Google provider icons and provider-specific loading labels, with duplicate sign-in disabled and legal/help links retained.
- Adjusted sign-in spacing and touch targets for desktop and phone screens.

## Verification

- All 916 web tests across 136 files passed; TypeScript and targeted ESLint checks passed.
- Explicit Customer production build, including the isolated sign-in fixture, succeeded. Existing large-chunk warnings remain; this does not establish a mobile performance budget.
- Browser checked the production-built presentation, not a development-only scene. Outside rendered successfully, Instrument Serif loaded, and no browser errors/warnings were observed in the verification tab.
- All five bundled exterior texture URLs and the font returned HTTP 200 with appropriate content types.
- Checked desktop 1280×720, phone 390×844, and short/narrow phone 320×568. Phone width stayed within the viewport; short phones can scroll to legal links. Provider loading was tested with a simulated callback, not real sign-in.
- Tests cover unavailable graphics, readiness, context loss, provider callbacks/loading, Urdu direction, and old-wrapper constraints.

Preview: http://127.0.0.1:5189/reimagined-sign-in-check.html
This is an isolated presentation fixture with the actual sign-in component and onboarding wrapper. It does not access accounts, OAuth, geolocation, inventory or orders. It is not included in the normal deployment entry.

## Still separate / not claimed complete

- The UI is English-only. Urdu remains only in the approved brand wordmark; translations, RTL screens and a language selector are explicitly out of scope.
- A new standalone logo/icon asset: the user approved restoring the previous bilingual wordmark, not adopting the square cloud artwork.
- The remaining screen-by-screen UI/UX and bug audit, including authentication error/recovery presentation.
- Live deployment and real signed-out OAuth verification. The existing live session was left untouched.
- SKU and catalogue-content work remains deferred.
