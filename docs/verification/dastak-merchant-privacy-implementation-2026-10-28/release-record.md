# Merchant privacy release — 28 October 2026

Timezone: Asia/Riyadh. Owner explicitly authorized the Merchant upload, privacy-only
source push and policy deployment to Customer and Merchant. App Store privacy
publication, legal declarations and review submission are excluded.

## Archive and scope

- App Store Connect TestFlight readback: Build 68 was the latest Merchant build.
- Both Merchant configurations now reserve Build 69; no other target version changed.
- Signed Release archive succeeded, bundle `com.dastak.merchant`, 1.0.0 (69),
  iPhone/iPad. Exact Merchant Support URL retained.
- Archived root `PrivacyInfo.xcprivacy` matches the new source byte for byte and
  contains 17 types. Shared Customer/Delivery manifest remains unchanged.
- `codesign --verify --deep --strict` passed.
- Executable/dSYM arm64 UUID: `FD8C97B8-0216-3EC9-A80F-594167E71DDE`.
- Executable SHA-256: `af1c16e4307148b6c5fdeb4a8d875941916037f4c5f46417e1093cc62bfe00d3`.
- Archive: `/Users/Furqan/Library/Developer/Xcode/Archives/2026-10-28/DastakMerchant Build 69.xcarchive`.
- The native archive uses the approved current working-tree baseline, including
  existing Merchant demo/support work. The source commit stages only privacy
  additions and Build 69 configuration through the Git index; unrelated existing
  native support/demo, Customer, artwork and project-formatting edits stay local.
- After the build/version/date edits, seven web content tests and seven native
  project-configuration tests passed. Earlier full suites and hosted bundle tests
  are recorded in the implementation README. Raw build logs stay local.

## Website preparation

- Privacy effective date updated to 28 October 2026 for this authorized publication.
  Existing Terms and Support dates remain 17 October 2026.
- Customer production baseline: `dpl_DETkSzFDnUUE7hFA1c6UgsM7WtsD`, source metadata
  `66951b2679cf091dfd354db8d80bda296ce137eb`.
- Merchant production baseline: `dpl_8ePDyjDq5bt17GMnpfj6a2JSPn1M`, source metadata
  `61f51b7bcf691370c121e977b95b050311988267`. That deployment predated its support-only
  commit, so its recorded activation source hashes were checked against HEAD and
  overlaid to preserve the exact live support runtime rather than reverting it.
- Separate deployment copies under ignored `DerivedData/merchant-privacy-release-2026-10-28`
  receive only approved policy files over those production baselines. They do not
  include unrelated working-tree changes. Existing Vercel project links are untouched.
- Existing production environment configuration is downloaded only into ignored
  deployment copies. No hosted secret or environment setting is changed.
- Initial local Vercel build used the project subdirectory despite its configured
  root directory and failed before compilation (`spawn sh ENOENT`). Corrected builds
  run from the isolated repository root. A local-only install-command override uses
  existing installed dependencies; no hosted project setting is changed.

Upload completion, production deployment and live route checks will be recorded
only after independently verified results.
