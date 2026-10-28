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

## Completed upload and production verification

- Privacy source commit `30dddedf46818942b8da79af5758ae4eeec3f537` was pushed to
  `origin/codex/dastak-v1-launch`. The unrelated working-tree edits were preserved.
- Xcode reported **Uploaded with warnings** at 18:54. Its warnings concerned
  skipped account validation/expired credentials and an auxiliary
  `asset-description-…xml` upload. These warnings are retained as a limitation;
  a clean Xcode validation is not claimed. Independently, App Store Connect
  accepted the binary, completed processing, and initially showed Missing
  Compliance. The owner completed Apple's questionnaire directly. A fresh
  TestFlight readback confirms **Build 69 — Ready to Submit**, expiry in 90 days,
  existing Testers group and 1 invite. No install/session is reported.
- Existing version build attachment, App Store privacy publication, review
  submission and Customer listing remain untouched.
- Fresh corrected Vercel builds completed successfully. Their generated build
  metadata contains no error. The initially rejected prebuilt attempts carried
  stale failure metadata from the first directory mistake; that generated
  metadata was discarded and both builds rerun before successful uploads.
- Before promotion, the uploaded `/privacy` HTML and compiled policy JavaScript
  were retrieved through authenticated Vercel curl and matched local artifacts
  byte for byte. Existing security headers and route configuration were retained.
- Both exact verified artifacts were promoted. Final canonical-domain inspection
  independently confirms READY and the following deployment IDs:

| Site | Deployment | Immutable artifact |
|---|---|---|
| Customer | `dpl_PuTjCkbj6feqEiQfRXqVMcufAVC5` | https://dastak-xrzz22ccg-liquiflows-projects.vercel.app |
| Merchant | `dpl_8dqmvukvziLyEmcforZt9c2wkjRr` | https://dastak-merchant-ldejguqrg-liquiflows-projects.vercel.app |

- Live https://dastak-customer.vercel.app/privacy and
  https://dastak-merchant.vercel.app/privacy each return HTTP 200. Their HTML and
  compiled policy scripts match the exact verified artifacts; both have the
  28 October effective date and correct site variant. Both Terms/Support routes
  and Merchant's `/merchant-support` also return 200. Detailed hashes and route
  results: [live-policy-checks.json](live-policy-checks.json).
- Fresh Safari readback of Merchant's public page confirms the effective date,
  verification, operations, financial, device recovery, demo, support and retention
  sections render. The agent-created policy tab was closed afterward. No support
  request or account/order operation was submitted.
- Deployment-scoped Vercel error scans, last 30 minutes, limit 20, returned zero
  entries for both artifacts. This bounded static-site check is not a claim of
  exhaustive monitoring, configured drains, or backend/provider health.
- No migration, backend deployment, hosted environment change, paid service,
  personal-file cleanup or simulator-runtime deletion was performed.

## Subsequent version and App Privacy draft preparation

28 October 2026, Asia/Riyadh. After the owner requested continuing, the stated
scope was to attach Build 69 and enter the approved privacy details as a draft,
stopping before privacy publication and review submission.

- Sell on Dastak / app ID `6796520415`: replaced only the version 1.0 draft's
  Build 68 attachment with Build 69 and saved. Navigating away and returning
  independently read back Build 69 with Save disabled. Version remains
  **Prepare for Submission**.
- Saved App Privacy's Privacy Policy URL as
  `https://dastak-customer.vercel.app/privacy`, matching the native configuration
  and the verified live shared policy. User Privacy Choices URL was left blank.
- Saved Yes for data collection and exactly the 17 approved data types. For each
  type, selected App Functionality as the sole purpose, linked to identity Yes,
  and tracking No. No advertising, analytics, personalization or other purpose
  was selected. Search History and Purchases were not selected.
- A full Safari reload independently showed **17 data types collected**, exactly
  matching the approved set, 17 App Functionality cards, 17 identity-linked cards,
  zero remaining Set Up entries and no Used for Tracking entries. Publish is now
  enabled but **was not clicked**. The declaration remains unpublished.
- Safari's last Other Data Types link was exposed as a merged text block and
  coordinate input returned `noWindowsAvailable`. After other native/keyboard
  attempts, the owner opened that one setup dialog directly; the agent completed
  its approved purpose/linkage/tracking answers and verified the saved state.
  No hidden browser API or page-script workaround was used.
- Read-only App Information check still shows **Set Up Age Ratings** and
  **Set Up Content Rights Information**. Business category is saved. These
  questionnaires were not answered or saved in this slice.
- Review access still has Sign-in required checked and blank credential fields,
  alongside existing demo Notes. This mismatch was identified and left unchanged;
  no reviewer account, credential, permission grant or claim of Apple approval for
  demo access was introduced.
- No Publish, Add for Review, final submission, legal acceptance, new binary
  upload, deployment or Customer listing mutation occurred in this follow-up.
  Only this verification record was changed locally; existing app/artwork edits
  remain preserved.
