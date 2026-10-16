# Customer + Delivery iOS distribution

Status: in progress. Merchant work remains deferred until this distribution work is handled.

## Confirmed baseline

- Combined app: `com.dastak.app`, Apple team `RBLBKM3W74`.
- Existing App Store Connect record: app ID `6796518603` (initially Dastak Local; the latest Safari view showed Dastak دستک).
- Version 1.0.0 Build 54 is installed on the owner's iPhone.
- Source `89181d1015143181c941380342ee1d24fc941932` passed all five hosted Foundation jobs in run [38824003188](https://github.com/furqanz7/savari-dastak/actions/runs/38824003188).
- App Store Connect currently contains old Builds 1 and 3, not Build 54. Build 3 was rejected in September under Guideline 2.1(a) because the reviewer could not access the app. Beta review notes/sign-in information were empty.
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

With explicit owner approval, only the unused downloadable iOS 18.4 runtime (`0CF8ADE5-0090-42BB-9077-A5A286D0A2AC`, approximately 8.8 GB) was removed through `simctl runtime delete`, after a dry run. It can be downloaded again through Xcode. iOS 18.5, 26.5 and 27 runtimes, simulator devices, source, installed apps, existing archives and Codex/ChatGPT data were retained. The latest check showed approximately 11 GiB available.

## Archive and upload checkpoint

- Release archive succeeded at `/Users/Furqan/Library/Developer/Xcode/Archives/2026-10-16/Dastak55.xcarchive`; version 1.0.0, Build 55, arm64, bundle `com.dastak.app`, team `RBLBKM3W74`.
- Deep strict code-signature verification passed. The archive contains the Live Activity/widget extension and app/dependency privacy manifests.
- The archive is development-signed pending App Store export. Its current APNs entitlement is `development` and `get-task-allow` is true; production signing must be verified after successful export. These archive entitlements are not claimed to be final distribution entitlements.
- App Store Connect export/upload failed before uploading with `App Store Connect Credentials Error`, `Unexpected nil property at path: 'Actor/relationships/providerId'`. Xcode's Apple Accounts settings are open and the owner has been asked to refresh the owning Apple account directly in Xcode. No credentials have been changed or recorded here.
- The signed archive is retained so export can be retried without another archive build after authentication is repaired.
- A TestFlight description and public URLs were entered in Safari but remain unsaved. Review notes and accurate sign-in/access information remain unfinished. The legacy unchecked sign-in-required setting must not be treated as truthful completed metadata.
- No Build 55 upload, tester invitation, App Review submission or public iOS release has occurred. Build 54 remains the last confirmed physical iPhone installation.

## Public privacy deployment

The Customer web artifact for the exact Build 55 source was staged, verified, then promoted without rebuilding. Deployment `dpl_DoFzNGLTcvmvZdugdky3p27pRZGi` is Ready. The public [privacy page](https://dastak-customer.vercel.app/privacy) returns HTTP 200, declares the expected source SHA / Customer variant / production environment, and serves the same JavaScript hash as the verified staged artifact. Its policy is dated 16 October 2026 and includes the optional iOS Apple WeatherKit section. CSP and `nosniff` headers remain present. Merchant, Admin and Delivery web deployments were not changed by this promotion.

## Remaining release gates

- Refresh Xcode's App Store Connect authentication; successfully export the retained archive with App Store distribution signing and verify the final entitlements.
- Validate/upload the archive and wait for Apple's processing result.
- Finish truthful TestFlight metadata, internal testing and production notification/weather checks on the distributed build.
- Resolve reviewer access to the approved Delivery workspace while retaining Apple/Google login.
- Finish App Store privacy answers, screenshots, age rating, app details and review contact/access information; select the uploaded build.
- Submit the completed version for App Review and track the actual Apple decision. Do not label an upload or a local archive as approval or public availability.

References: [Apple distribution flow](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [WeatherKit setup and included allowance](https://developer.apple.com/weatherkit/), [both WeatherKit portal settings](https://developer.apple.com/help/account/services/weatherkit/).
