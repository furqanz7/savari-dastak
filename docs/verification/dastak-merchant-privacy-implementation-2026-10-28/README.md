# Merchant privacy implementation — local verification

28 October 2026, Asia/Riyadh. Owner approved the proposed policy/mappings and
explicitly approved using the changed current project as baseline while
preserving existing edits. Local implementation and tests only: no push,
deployment, upload, privacy publication, legal acceptance or review submission.

## Source changes

- `Web/MarketplaceWeb/src/publicInformation.ts`: approved Merchant summary,
  authentication, verification/pin, store, financial, local-recovery, demo,
  support, recipients, account/privacy and retention copy. Existing
  Customer/Delivery payment/weather sections and Terms/Support content retained.
  The privacy update date is intentionally unchanged pending actual publication.
- `Apps/Dastak/Supporting/Merchant/PrivacyInfo.xcprivacy`: Merchant-only root
  manifest with 17 unique types; all linked, App Functionality, no tracking.
  Adds the approved Other Data Types mapping; excludes Purchase History,
  Product Personalization and Search History. Keeps UserDefaults reason CA92.1.
- Xcode resource wiring changes only Merchant's existing privacy build-file
  reference to the new resource. It still packages as `PrivacyInfo.xcprivacy`.
  Customer/Delivery/Admin remain on the existing shared manifest.
- Web content, native configuration and hosted bundle tests cover the change.

## Baseline protection

Branch `codex/dastak-v1-launch`; HEAD
`21aaaf1f86b9383e7c0f3aa075857ef553cdfe8b` unchanged at start. Captured 23 dirty
tracked-file hashes before editing. Only the project and two native test files
among those baseline files changed in this slice. CustomerPartner-Info.plist,
existing Customer/Delivery/native/artwork edits were preserved.

Parsed Xcode-project comparison shows exactly three changed/added objects:
Merchant privacy PBXBuildFile `A60000000000000000000003`, new PBXFileReference
`A60000000000000000000005`, and Supporting PBXGroup membership. All other project
objects, build settings and top-level keys remain semantically identical to the
approved current baseline. No target/build-version change was made.

Shared Customer/Delivery manifest SHA-256 unchanged:
`fa14c2a20f0dec88f874da877d3392eaaa75c9cdead4b752991cd895039fd10b`.

## Checks

- Property-list lint: Merchant manifest and Xcode project valid.
- Focused web content/style tests: 2 files, 9 tests passed.
- Native project configuration tests: 7 passed, including exact Merchant types,
  non-tracking purposes, reason API and per-target manifest isolation.
- Full web suite: **154 files, 1,115 tests passed**.
- Production web build: TypeScript and Vite passed. Existing large-chunk warning
  remains; this is not a new policy-content error or performance certification.
- Full infrastructure package suite: **197 tests passed** (includes the seven
  focused configuration tests above; do not count those twice).
- Release iOS 26.5 simulator hosted tests: **2 passed, TEST SUCCEEDED**. These
  verify the actual Merchant app bundle's Support URL and packaged manifest,
  including all 17 types, purposes, uniqueness and exclusion of Customer
  Purchase History/personalization and Search History. No signed device archive
  or physical-device installation is claimed.
- The compiled app resource independently contains Other Data Types and none
  of Purchase History, Product Personalization or Search History. Its root
  resource name is `PrivacyInfo.xcprivacy`, not a renamed alternate manifest.
- Parsed content comparison against HEAD: Terms and Support identical; six
  protected privacy sections identical; all 17 approved added/replacement
  paragraphs present. No UI layout/CSS was changed; no visual screenshot review
  is claimed by this content-only slice.
- `git diff --check` passed. The final baseline check found no unexpected edits
  to pre-existing dirty files and no removed project objects. Existing shared
  manifest hash remains unchanged. Nothing is staged.
- Simulator started Shutdown and was Shutdown again when tests finished;
  no simulator device or runtime was deleted. Media-framework warnings appeared
  during launch but both hosted tests passed.

Hosted test log is retained locally as `merchant-hosted-tests.log` in this
directory and is excluded from the source commit; the result bundle below is
the full local test artifact.
Pre-edit dirty-file hashes: [pre-edit-hashes.json](pre-edit-hashes.json).
Xcode result bundle:
`/Users/Furqan/Library/Developer/Xcode/DerivedData/SavariDastak-gyyxvwviaaexfscffckrmnhadjzr/Logs/Test/Test-DastakMerchant-2026.10.28_18-13-26-+0300.xcresult`.

## Distribution boundaries

Existing uploaded Build 68 has not changed. This modified manifest requires a
new archive/build number before upload. No build number was reserved in this
slice. App Store privacy answers and public policy pages remain unchanged.
Before a separately approved public deployment, update only the privacy page's
effective date to the actual publication date, test and verify both public
privacy routes. A local test is not a production/deployment or App Review result.

## Separately approved release follow-up

The owner subsequently approved uploading the next Merchant build and committing/
pushing only this privacy implementation, tests and verification, then deploying
the policy to Customer and Merchant. App Store privacy publication and review
submission remain excluded. See [release record](release-record.md).
