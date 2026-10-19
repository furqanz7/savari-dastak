# Merchant single-store presentation — 20 October 2026

## Requested correction

The owner clarified that Merchant has no feature for adding multiple branches
or locations and approved simplifying the interface around one store. This is
a presentation correction, not a new branch-management feature or a schema
change.

## Implemented locally

- The workspace header says **Your store**, shows the existing store name and
  business type, and provides a **Refresh store** accessibility label.
- Removed the location-switching menu and confirmation dialog, directory
  pagination button, location-list disclosure, and switching-specific notices.
- Orders, History, return receipts, order details, menu access and recovery/error
  copy refer to the store rather than asking the merchant to choose a location.
- Address/map-pin selection is still available, labelled **Pickup location** or
  **Store pickup location**. This identifies where riders collect orders; it
  does not create another store.
- Internal IDs, authorised-record discovery, saved-action pinning, per-account
  preferences, order filtering, response checks and permission gates are
  unchanged. No database-enforced one-store-per-account restriction was added.
  Existing internal records were not removed or modified.

## Verification and release boundary

`swift test --package-path Packages/DastakUI --jobs 2 --filter DastakMerchant`
passed **287 tests**, zero failures. This includes two new SwiftUI header-render
checks (one/multiple internal records, loading/access failure at narrow width)
and a new validation-copy check. Render checks run on macOS and do not establish
native iOS Dynamic Type scaling or physical-device VoiceOver acceptance.

The full `swift test --package-path Packages/DastakUI --jobs 2` suite also passed
**761 tests**, zero failures. `git diff --check` passed. Tests use local fixtures,
not production order or account mutations.

The initial new single-record test incorrectly reused a previously populated
two-record model. It was corrected to bootstrap an independent single-store
fixture; the production discovery behaviour was not altered to satisfy it.

After the owner approved proceeding, Build 64 was installed on their iPhone as
recorded below. It has not been installed on an iPad or uploaded to TestFlight.
The owner subsequently confirmed the new header/copy on iPhone as recorded below. The earlier
owner acceptance record describes the preceding installed version, not these
new header/copy changes. No administrative production writes, migrations,
deployment, commit, push or Apple distribution action was performed.

Guard: `codex/dastak-v1-launch` at
`d751fb8c9945eec4ba043b4a349b6d633251d51d`. Known unrelated Customer/release
working changes were preserved.

## Build 64 iPhone installation

- Built in Release configuration with build-number override **64** from an
  isolated extraction of the guarded HEAD plus only the ten modified Merchant
  runtime files and two regression-test files. The existing local build
  configuration was copied without changing or printing its values.
- Unrelated Customer changes and dependency-lockfile drift were excluded.
  The isolated `Package.resolved` matches HEAD, SHA-256
  `0fbc22e16491269712601ac0b61559d4be2386631bc4a2329e61cebcac24c958`.
- `xcodebuild` exited 0. Strict/deep signature verification passed. The artifact
  reports `com.dastak.merchant`, version `1.0.0 (64)`, and development APNs
  entitlement. The previously committed APNs-environment resolver is retained.
- Executable SHA-256:
  `f237b3507af21f9ce3d11da1aa1db96dc55c42ebfb1a718399eece24f2cafb2c`.
- `devicectl` installation succeeded over Merchant Build 63. A separate installed
  apps query confirmed **1.0.0 (64)** on the owner's iPhone. Normal app launch
  succeeded. No order, menu, availability or account controls were exercised.
  Customer and Delivery were not installed or replaced.
- Build, installation, version and launch evidence is retained under
  `/private/tmp/dastak-merchant-build64.YXh2Pk/`; signed app is in
  `DerivedData/Build/Products/Release-iphoneos/DastakMerchant.app`. Temporary paths
  may be cleared by macOS later; the hashes and results above are the durable
  local record.

The earlier 761-test package run was performed in the guarded worktree; it is
not claimed as a second isolated test run of the extracted build tree. The
isolated native Release build itself passed. Installation/launch is not a visual,
VoiceOver or new live-notification acceptance result. No TestFlight/App Store
upload or submission was made.

## Owner confirmation of the correction

After installation and independent version verification, the owner was asked
to check Orders and Store and confirm that the header makes sense without
suggesting branches can be added or switched. The owner answered **"yes"**.
This is owner-reported acceptance of the single-store header/copy on iPhone
Build 64, not agent-observed UI execution or a new full lifecycle, iPad,
VoiceOver or notification pass. Only this local note was updated when recording
the response; no commit, push, build, deployment or Apple distribution action
was taken.

## Follow-up: store header covered Orders / Store content

The owner subsequently reported that the Your store banner hid content in both
tabs. This reopens the placement of that header; the earlier confirmation of
the single-store wording does not establish a layout pass.

The header was mounted in a top safe-area inset on the entire TabView, outside
the child NavigationStacks. The correction removes that global placement:

- Orders and the restaurant menu place the store header as the first item of
  their page's scrolling content.
- Grocery catalogue landing/search/directory pages use it in their existing
  scrolling store-header section, replacing the duplicate storefront-name block.
- The accessibility category browser includes it in scrolling content. The
  two-column category browser reserves real VStack layout height for it above
  its two scrolling columns; it is not a floating overlay.
- Store-loading failure content is scrollable and includes its own store header,
  current error and retry action. The redundant global catalogue-failure inset
  was removed; the page retains its failure and retry controls.
- The urgent saved-action/session recovery banner remains global. Store IDs,
  permissions, command recovery and order business actions are unchanged.

The full UI package suite passed **762 tests**, zero failures, including a new
inline-layout rendering regression at widths 180, 320 and 768 with normal and
accessibility environment sizes. This checks height reservation in a local
render harness, not native navigation bars, iOS Dynamic Type scaling or a
physical-device overlap result. `git diff --check` passed.

Build 65 completed successfully in Release configuration in the same isolated
build directory, with the prior Build 64 app preserved as `Build64.app`.
Strict/deep signature verification passed; the artifact reports
`com.dastak.merchant` build **65**. The executable SHA-256 is
`968da1db3ae04603105f8ee1aa81b2a6ec2e2fa953a2b0c0fe6e2a6ea2c8effa`.
All four changed placement files match the worktree, and dependency pins remain
unchanged from the Build 64 isolated source. Native build/test logs are
`build65.log` and `build65-ui-tests.log` in the task directory.

The phone was initially reported unavailable and reconnection was requested.
After the owner confirmed it was connected and unlocked, the exact Build 65
artifact above passed signature/hash rechecks and was installed successfully
over Build 64. An independent installed-apps query confirmed **1.0.0 (65)** and
normal Merchant launch succeeded. Installation/version/launch receipts are
`install65.json`, `installed-version65.json` and `launch65.json` in the task
directory. No order, menu, availability or account controls were exercised;
Customer and Delivery were not installed or replaced.

Owner visual acceptance of the corrected placement is still pending. No commit,
push, administrative production write, deployment or TestFlight/App Store action
was performed while installing or recording this result.

## Subsequent design revision

The owner rejected the visual quality of the Build 65 presentation. The
integrated, unboxed **Build 66** header revision, rendered previews, verification
and installation boundary are recorded in the
[header polish report](verification/dastak-merchant-header-polish-2026-10-20/README.md).
The earlier wording confirmation is not acceptance of this later design.
