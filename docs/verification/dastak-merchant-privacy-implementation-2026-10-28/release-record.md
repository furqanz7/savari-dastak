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

## Subsequent age rating, rights and reviewer-access setup

28 October 2026, Asia/Riyadh. The owner requested continuing the remaining listing
setup, confirmed that current Merchant content includes alcohol/tobacco/drug-use
references, and explicitly selected **Frequent — users encounter it regularly**.
The owner also confirmed the necessary rights to third-party content in the
selected regions and explicitly authorized saving Apple's Yes/rights answer.

- Content Rights: selected **Yes, it contains, shows, or accesses third-party
  content, and I have the necessary rights**, completed Done and saved App
  Information. The saved page reads **Yes, this app has the necessary rights to
  its third-party content**. This records the owner's declaration, not an
  independent licensing audit of every product, brand or merchant image.
- Age Ratings: User-Generated Content Yes because Merchant users publish menu
  text/images. Parental Controls, Age Assurance, Unrestricted Web Access, Social
  Media, Social Media Disabled for Users Under 13, Messaging and Chat, and
  Advertising No for the inspected native Merchant features. The private support
  link opens an external browser; no in-app general browsing or social feed was
  identified. Business-identity verification is not evidence of age assurance.
- Mature themes: profanity/crude humour and horror None; alcohol/tobacco/drug-use
  references **Frequent**, explicitly confirmed by the owner. Medical/treatment
  guidance None; Health/Wellness Topics No. Sexual/suggestive content, nudity,
  violence and weapons None. Simulated gambling and contests None; gambling and
  loot boxes No. No corresponding feature/content was identified in the inspected
  native Merchant interface. This does not certify every future merchant upload.
- Apple's calculated rating is **18+**. No lower rating or age-suitability URL was
  imposed. The Mac locked at the final Save step; after the owner unlocked it,
  Save completed. A full reload independently showed 18+ and the saved rights
  declaration together. Existing Business category and country settings were
  not changed.
- App Review history currently says **Items you submit to App Review will appear
  here**. No Merchant submission or message confirming demo acceptance was shown.
  This is not proof about separate correspondence outside the inspected page.
- Reviewer credential requirement: unchecked Sign-in required and saved, matching
  the owner-approved public demo path. Full reload independently confirms the
  checkbox off, Save disabled, Build 69 attached, Prepare for Submission, and the
  unchanged Notes explaining normal Apple/Google sign-in/business approval versus
  public Explore the demo access. No app authentication or server permission changed.
- Apple's acceptance of the demo instead of a live reviewer account remains
  unverified. Guideline 2.1 addresses prior approval for a demo replacing an account
  because of legal/security obligations. No message requesting that approval was
  sent, no reviewer account was granted and no approval is claimed.
- App Privacy remains the completed unpublished 17-type draft; no Publish,
  Add for Review, final review submission, new build, deployment or backend change.

Primary definitions checked on 28 October:
[age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/),
[review access guidance](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review),
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Owner-confirmed privacy publication and Apple demo-access request

28 October 2026, Asia/Riyadh. The owner separately and explicitly confirmed
Apple's final agreement that the saved privacy responses are accurate, comply
with App Store Review Guidelines and applicable law, and will be promptly updated
if data practices change, and authorized clicking Publish. The owner also
authorized sending the prepared demo-access request to Apple App Review.

- Opened the final **Publish Your App Privacy Responses?** dialog, presented its
  agreement to the owner, and clicked its final Publish button only after that
  confirmation. The dialog closed and App Store Connect displayed **Published a
  few seconds ago** under the signed-in owner. The declaration is published;
  this is not an App Review approval or submission.
- Apple contact route: Developer Support → App Review → Other App Review questions
  → Email. App name Sell on Dastak, app ID 6796520415, platform iOS. Related Apps
  was left blank. Existing account contact details were not changed.
- The [approved message](apple-demo-access-request.md) was entered with its subject
  prepended because the form has no separate Subject field. Selected-text readback
  matched the full approved message before sending. No actual customer records,
  credentials, identity documents or bank details were included.
- After Send message, Apple navigated to its `/submit` confirmation and displayed
  **Thanks for contacting us. Your case ID for this conversation is … We’ll review
  your message and get back to you as soon as possible.** A case ID was issued and
  reported privately to the owner; it is not committed here. No duplicate message
  or unrelated existing support case was submitted.
- The owner-authorized request asks whether the public isolated demo is acceptable
  under Guideline 2.1 and what additional resources Apple needs. Sending it is not
  acceptance of the demo by Apple. No reply or approval is claimed.
- A final attempt to reload App Privacy was blocked when the Mac locked again.
  The successful publication confirmation above was directly observed before
  that lock; no successful post-lock reload is claimed.
- No Add for Review, final app-review submission, new binary, migration, backend
  deployment, paid service or Customer listing change occurred. The latest
  independently verified version state remains Prepare for Submission with
  Build 69 attached and saved public-demo instructions.
