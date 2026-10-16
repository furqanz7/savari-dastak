# Customer + Delivery iOS distribution

Status: in progress. Merchant work remains deferred until this distribution work is handled.

## Confirmed baseline

- Combined app: `com.dastak.app`, Apple team `RBLBKM3W74`.
- Existing App Store Connect record: app ID `6796518603` (initially Dastak Local; the latest Safari view showed Dastak دستک).
- The owner confirmed installing version 1.0.0 Build 55 through TestFlight.
- Source `89181d1015143181c941380342ee1d24fc941932` passed all five hosted Foundation jobs in run [38824003188](https://github.com/furqanz7/savari-dastak/actions/runs/38824003188).
- App Store Connect contains old Builds 1 and 3 and now records Build 55's upload as Complete. Build 3 was rejected in September under Guideline 2.1(a) because the reviewer could not access the app. Beta review notes/sign-in information were empty.
- The owner wants reviewers to use the existing Apple/Google sign-in options. No password login, approval bypass, review identity or demonstration mode has been added.
- Newly signed-in users do not automatically become approved Delivery partners. Reviewer access to assigned Delivery work remains an unresolved review prerequisite; explanatory notes alone do not prove that Apple can test it.

## Release configuration inspection

Release resolves the configured production backend and a publishable client key. No credentials are recorded here. Swift optimization is `-O`; Debug-only sample launch routes are excluded from Release. The notification client selects the production APNs environment in Release. The deployed notification worker supports per-registration production/sandbox routing.

The Mac has one usable local Apple Development identity. Apple's portal also lists an existing cloud-managed Distribution certificate. Export/upload must demonstrate valid App Store signing and a production APNs entitlement; a locally installed Debug build is not distribution evidence.

## Build 55 preparation

The owner approved using Apple WeatherKit within the membership's included allowance. The app now requests current weather with the native SDK, sends rounded two-decimal coordinates, keeps the opt-in and 15-minute throttling, cancels requests when the outside scenery becomes inactive, and falls back to device-clock scenery after a 12-second deadline or failure. Freshness/range validation and late-response guards are retained. Apple Weather attribution and a source link accompany the scenery and Settings controls.

WeatherKit is isolated to the combined app's new `CustomerPartner.entitlements`; Merchant/Admin retain their existing entitlements. The native privacy manifest declares optional unlinked coarse location, and the public privacy policy explains the weather processing.

WeatherKit was enabled and saved under the existing App ID's Capabilities on Apple's portal. The owner confirmed completing the separate App Services WeatherKit setting. The resulting archive's provisioning entitlement includes WeatherKit; actual WeatherKit service access still needs verification on the distributed build.

The initial local host test failed while linking with `errno=28` (disk full). Build 55 source `3d26a2df9cf2d92bd33826c68b1e12e8737637b7` subsequently passed all five hosted Foundation jobs in run [38827379170](https://github.com/furqanz7/savari-dastak/actions/runs/38827379170): Swift packages, iOS build, Dastak backend, Savari backend and Dastak web. This is hosted test/build evidence, not a claim that live WeatherKit requests have been exercised.

With explicit owner approval, only the unused downloadable iOS 18.4 runtime (`0CF8ADE5-0090-42BB-9077-A5A286D0A2AC`, approximately 8.8 GB) was removed through `simctl runtime delete`, after a dry run. It can be downloaded again through Xcode. iOS 18.5, 26.5 and 27 runtimes, simulator devices, source, installed apps, existing archives and Codex/ChatGPT data were retained. The post-cleanup checkpoint showed approximately 11 GiB available; subsequent archives and simulator compilation consumed part of that space.

## Archive and upload checkpoint

- Release archive succeeded at `/Users/Furqan/Library/Developer/Xcode/Archives/2026-10-16/Dastak55.xcarchive`; version 1.0.0, Build 55, arm64, bundle `com.dastak.app`, team `RBLBKM3W74`.
- Deep strict code-signature verification passed. The archive contains the Live Activity/widget extension and app/dependency privacy manifests.
- The original archive is development-signed, but Organizer successfully re-signed the uploaded package with Apple Distribution for team `RBLBKM3W74`. Deep strict code-signature verification of that distribution package passed. Its final entitlements include `aps-environment=production`, `get-task-allow=false`, `beta-reports-active=true`, Apple sign-in and WeatherKit.
- The command-line App Store Connect export/upload failed twice with `App Store Connect Credentials Error`, `Unexpected nil property at path: 'Actor/relationships/providerId'`. The owner correctly noted that Xcode was already signed in; live inspection confirmed the account and team membership, and App Store Connect showed Account Holder/Admin access. The exact cause of the command-line-specific failure was not established.
- Using Xcode's native Archives Organizer with the same retained Build 55 archive succeeded without signing out, removing credentials or changing certificates. Organizer displayed `Dastak 1.0.0 (55) uploaded`; ContentDelivery logged `UPLOAD SUCCEEDED with no errors`.
- Safari independently showed Build Uploads → 1.0.0 (55) → Complete, created 16 October 2026 at 6:22 AM. A subsequent inspection confirmed Build 55 as Ready to Submit in the main list and Testing in the existing internal group, with 90 days remaining. This is internal TestFlight availability, not App Review approval.
- A TestFlight description and public URLs were entered in Safari but remain unsaved. Review notes and accurate sign-in/access information remain unfinished. The legacy unchecked sign-in-required setting must not be treated as truthful completed metadata.
- Build 55 upload is complete. No new tester invitation, App Review submission or public iOS release has occurred.

## Build 55 owner acceptance and Build 56 footer polish

The owner reported passing sign-in/session persistence, Grocery/Food browsing, Delivery navigation, widgets, shortcuts and notification/Live Activity settings on the TestFlight build. The owner also explicitly confirmed production notification delivery, Live Activity stage progression and correct order opening/completion for **both Grocery and Food**. These are owner-run acceptance results, not agent-observed delivery timings or server traces.

The owner's 06:44 sign-in screenshot showed rain scenery with Apple Weather attribution. Source inspection confirms that attribution is populated only after a successful, validated weather response and attribution fetch. This supports successful WeatherKit operation on TestFlight, although it does not independently establish current local weather accuracy. The screenshot also exposed attribution crowding the consent footer and weak mark contrast.

The owner approved a narrowly scoped Build 56 polish: move attribution from a fixed backdrop overlay into the Customer sign-in footer's existing gap, pair Apple's light mark with a dark backing over scenery, keep the data-source link, and preserve the normal-size sign-in panel/scenery. The footer grows for larger text and reserves space during new-customer setup as well. The Google label fits its button at the tested accessibility size. The footer hook defaults to absent for other apps. A Debug-only, noninteractive fixture exercises the actual sign-in layout without using saved sessions, live location or commerce.

Build 56 verification:

- Normal text and Accessibility 3 sign-in layouts visually inspected in the dedicated simulator; attribution and consent/links remain separate. Normal-text new-customer setup also retains a separate credit beneath the form. These are isolated layout fixtures, not live weather/account tests.
- Local design-system tests passed: eight XCTest tests (including two new footer/environment isolation cases) plus eight Swift Testing tests. A hosted run exposed an existing haptic test's 80 ms scheduling assumption; only the test was changed to wait for the callback with a bounded timeout. No production haptic behavior changed.
- Exact source `b4a5389e20fcf07626037a8797dbcad49ed8a0aa` passed all five hosted Foundation jobs in run [38836892060](https://github.com/furqanz7/savari-dastak/actions/runs/38836892060). An earlier unrelated Savari CI attempt timed out starting local Storage; the final exact-source run passed without backend changes.
- Final Release archive succeeded at `/Users/Furqan/Library/Developer/Xcode/Archives/2026-10-16/Dastak56.xcarchive`. The Release binary excludes the Debug sign-in fixture.
- Organizer confirmed `Dastak 1.0.0 (56) uploaded`; ContentDelivery reported `UPLOAD SUCCEEDED with no errors`. The re-signed distribution package passed deep/strict signature verification, app and widget both report Build 56, and final entitlements retain production APNs, WeatherKit and `get-task-allow=false`.
- Safari initially showed Build 56 uploaded at 7:23 AM with **Missing Compliance**. After the owner reported completing the encryption questionnaire, a live refresh confirmed Build 56 **Ready to Submit**, assigned to Testing, with 90 days remaining. The existing internal group uses Automatic for Xcode Builds.
- A live inspection of that internal group's tester record subsequently showed **Installed 1.0.0 (56), 16 October 2026**, on the owner's iPhone 12 running iOS 27.0.1. Internal availability and installation are therefore confirmed; this is not external beta review or App Store approval.
- The owner subsequently confirmed that the corrected Build 56 footer looks good on the installed TestFlight app. The footer acceptance gate is closed.
- The App Encryption Documentation questionnaire was opened read-only by the agent; no answer was selected or saved by the agent. The owner completed the declaration directly. The archive does not include `ITSAppUsesNonExemptEncryption`; no encryption behavior or declaration key was changed as part of the footer polish. The owner's exact questionnaire selection has not been independently inspected.

## Public privacy deployment

The Customer web artifact for the exact Build 55 source was staged, verified, then promoted without rebuilding. Deployment `dpl_DoFzNGLTcvmvZdugdky3p27pRZGi` is Ready. The public [privacy page](https://dastak-customer.vercel.app/privacy) returns HTTP 200, declares the expected source SHA / Customer variant / production environment, and serves the same JavaScript hash as the verified staged artifact. Its policy is dated 16 October 2026 and includes the optional iOS Apple WeatherKit section. CSP and `nosniff` headers remain present. Merchant, Admin and Delivery web deployments were not changed by this promotion.

## Remaining release gates

- Finish truthful TestFlight metadata. Build 55 functional acceptance and Build 56 footer acceptance are recorded above.
- Resolve reviewer access to the approved Delivery workspace while retaining Apple/Google login.
- Finish App Store privacy answers, screenshots, age rating, app details and review contact/access information; select the uploaded build.
- Submit the completed version for App Review and track the actual Apple decision. Do not label an upload or a local archive as approval or public availability.

References: [Apple distribution flow](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [WeatherKit setup and included allowance](https://developer.apple.com/weatherkit/), [both WeatherKit portal settings](https://developer.apple.com/help/account/services/weatherkit/).

## App Store listing preparation checkpoint

The next Safari inspection could not be completed: the computer-use connection continued returning another Safari window and rejected actions as a changed application, including after reconnection. No App Store Connect fields were changed or saved during this attempt. This is a tooling/window-selection blocker, not a build failure or a confirmed App Store Connect rejection.

Local draft copy, privacy declaration cross-check notes and the screenshot plan are in `docs/dastak-app-store-listing-draft-2026-10-16.md`. These are preparation artifacts, not claims that the live listing is complete. Build 56 remains the intended release candidate. Reviewer Delivery access remains unresolved; no additional access or review bypass has been created.

## Build 57 compact weather credit

The owner requested a quieter weather attribution after accepting Build 56. The credit now pairs the retained Apple Weather mark with a short **Data sources** link in a compact row, removes the extra scenery sentence, and reduces the backing/padding. It retains the SDK-provided legal destination, correct light/dark mark selection, a 44-point minimum link target and one descriptive accessibility label. A stacked alternative is available when horizontal space is insufficient. Weather requests, permissions, account behavior and commerce are unchanged.

- The Build 57 Debug simulator build passed (`/tmp/dastak57-simulator-build.log`).
- All 16 local design-system tests passed: eight XCTest and eight Swift Testing (`/tmp/dastak57-design-tests.log`). These are regression tests, not proof of a live WeatherKit response.
- Normal and Accessibility 3 sign-in layouts were visually inspected through Device Hub using the existing isolated, noninteractive fixture. Mark/link remain separate from consent and legal links. The fixture uses the fallback mark and sample rainy scenery; no live location, real sign-in or order was used. Proof: `/tmp/dastak57-weather-credit-normal.png` and `/tmp/dastak57-weather-credit-large.png`.
- The first Release archive attempt failed with **IO failure on output stream: No space left on device** (`/tmp/dastak57-archive.log`). At that checkpoint no Build 57 archive/upload was complete; the successful retry and upload are recorded below. Build 56 remains the last verified installed TestFlight version.
- A scoped storage audit found that ordinary Xcode DerivedData is approximately 874 MB, npm cache 428 MB and SwiftPM cache 221 MB; clearing those alone would not provide the requested archive headroom. After explicit owner approval, the unused downloadable iOS 18.5 runtime (8,837,333,817 bytes, identifier `91BB1B74-243C-46A6-847F-FFE129094EF1`) was removed with `simctl runtime delete`, following a dry run and a fresh check that no devices used it. A subsequent runtime list confirms only iOS 26.5/27 and tvOS 18.5 remain; the Mac reported approximately 7 GiB available. The removed runtime can be downloaded again through Xcode. No other cache, runtime, archive or personal file was removed; the physical iPhone app, source, archives, Codex and ChatGPT remain untouched by cleanup.
- The compact-credit code is committed and pushed as `5d52251587c4681b2a42d3bc839df2cc87ff5a8a`. All five hosted Foundation jobs passed for that exact source at [38888803220](https://github.com/furqanz7/savari-dastak/actions/runs/38888803220): Swift packages, iOS build, Dastak backend, Savari backend and Dastak web.
- The Release archive retry succeeded (`/tmp/dastak57-archive-retry.log`) at `/Users/Furqan/Library/Developer/Xcode/Archives/2026-10-16/Dastak57.xcarchive`. Deep/strict signature verification passed; app/widget both report Build 57, the identifier/team match the retained app record, and the Release binary excludes the Debug footer fixtures.
- Organizer confirmed **Dastak 1.0.0 (57) uploaded**. ContentDelivery logged **UPLOAD SUCCEEDED with no errors** in `/var/folders/tx/3mqqzxlx7wq9jwfq95jyk18c0000gp/T/Dastak_2026-10-16_16-19-17.799.xcdistributionlogs`. The re-signed distribution package passed deep/strict signature verification and retains production APNs, WeatherKit, Apple sign-in and `get-task-allow=false`. Proof: `/tmp/dastak57-upload-complete.png`.
- Safari independently showed Build Uploads → 1.0.0 (57) → **Processing**, created 16 October 2026 at 4:21 PM. This confirms upload receipt, not internal availability, installation or App Review approval.
- A subsequent Safari inspection showed Build 57 **Missing Compliance** after processing completed. The owner was asked to complete Manage → encryption questionnaire, as for Build 56. No declaration was selected or saved by the agent. Proof of the live status: `/tmp/dastak57-missing-compliance.png`. Internal availability and installation are not yet confirmed.

Pending: obtain the owner's Build 57 encryption declaration and confirm compliance/internal availability and installation before replacing the installed Build 56 in the acceptance checklist. Then obtain owner acceptance of the compact credit. App Store listing/reviewer-access gates remain as above.

The Safari connection subsequently worked after opening App Store Connect from Organizer. A read-only inspection of Distribution showed an existing **iOS App Version 1.0 / Prepare for Submission**, English (U.K.) localization, empty promotional text/description/keywords/support/marketing/copyright/review-contact/notes fields, no selected build, and **Sign-in required** checked. Automatic release after approval is currently selected; this was not changed. Screenshot slots and other app-level questionnaires still require inspection. No listing field was edited, no Add for Review action was taken, and no public release was submitted during this check.
