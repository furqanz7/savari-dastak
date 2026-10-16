# Customer + Delivery iOS distribution

Status: in progress. Merchant work remains deferred until this distribution work is handled.

## Confirmed baseline

- Combined app: `com.dastak.app`, Apple team `RBLBKM3W74`.
- Existing App Store Connect record: Dastak Local, app ID `6796518603`.
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

WeatherKit is isolated to the combined app's new `CustomerPartner.entitlements`; Merchant/Admin retain their existing entitlements. The native privacy manifest declares optional unlinked coarse location, and the public privacy-policy source explains the weather processing. The policy source must be deployed before submission.

WeatherKit was enabled and saved under the existing App ID's Capabilities on Apple's portal. The owner has been asked to check the separate App Services WeatherKit setting because Safari coordinate interaction was unavailable. Provisioning profiles must be refreshed after this capability change.

The corrected WeatherKit code passed the host compiler, but the local test build failed while linking with `errno=28` (disk full); no successful test execution or new iOS build is claimed. The disposable simulator derived data and failed host test output were cleared, preserving source, installed apps, existing archives and the signed Build 54 product. At the latest check only approximately 1 GB remained free. The owner is freeing at least 8 GB before the archive proceeds.

A TestFlight description was entered into the existing form but remains unsaved. Attempts to reach the policy/review fields were blocked by the Mac locking. No new beta build has been uploaded, no tester invitations have been sent and no App Review submission or public release has occurred.

## Remaining release gates

- Confirm storage, run the focused weather/privacy checks and compile the new native code for iOS.
- Confirm both WeatherKit portal settings and refresh signing profiles.
- Create a Release archive; inspect bundle IDs, entitlements, extensions, privacy manifests, version and production configuration.
- Validate/export/upload the archive and wait for Apple's processing result.
- Finish truthful TestFlight metadata, internal testing and production notification/weather checks on the distributed build.
- Resolve reviewer access to the approved Delivery workspace while retaining Apple/Google login.
- Finish App Store privacy answers, screenshots, age rating, app details and review contact/access information; select the uploaded build.
- Submit the completed version for App Review and track the actual Apple decision. Do not label an upload or a local archive as approval or public availability.

References: [Apple distribution flow](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [uploading builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [WeatherKit setup and included allowance](https://developer.apple.com/weatherkit/), [both WeatherKit portal settings](https://developer.apple.com/help/account/services/weatherkit/).
