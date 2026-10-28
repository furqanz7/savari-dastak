# Merchant external beta and App Store submission

29 October 2026, Asia/Riyadh. App: **Sell on Dastak**, App Store Connect app ID
6796520415, bundle `com.dastak.merchant`, version 1.0 / binary 1.0.0 (69).

## Owner authority

The owner explicitly instructed: “submit to external then submit to App Store
Now”, superseding the earlier instruction to stop before submission/wait for
Apple's demo-access response. The owner also explicitly approved using the saved
App Review contact email as the Feedback Email visible to beta testers. No
testers, public invitation link or separate outbound message was requested.

The optional Header artwork was deliberately skipped at the owner's instruction.
Apple's acceptance of the isolated demo remains unverified; the owner was told
that submission does not establish acceptance of that arrangement.

## External TestFlight — completed first

- No external group existed. Created **External Testers**, initially 0 testers
  and 0 builds, and selected exact Build 69.
- Apple required separate beta-test information. Reused the saved public App
  Store description (1,600 characters) and existing review-contact fields. Values
  were read through visible native UI and held transiently; no actual contact
  email or phone is included in this record.
- Verified feedback/review email, first name, last name and phone all match the
  existing saved contact. Use of that email as tester-visible Feedback Email was
  separately confirmed by the owner.
- Beta credential requirement set off for the public demo. What to Test contains
  a short Build 69 test introduction plus the full existing demo walkthrough,
  3,212 characters. The complete visible value matched the composed text before
  submission. It explains the local fictional data, normal sign-in/approval,
  Grocery and Restaurant / Café workflows, recovery, Reset/Exit and provider/push
  limits. No real order or payout is requested.
- **Automatically notify testers unchecked**, independently read back before the
  final beta Submit for Review action. No invitations or public link were created.
- Apple accepted the submission. The external group reads **0 Testers · 1 Build**,
  exact binary **1.0.0 (69)**, **Waiting for Review**.
- A full refresh independently confirmed the same external group/build/status.
  This is a Beta App Review submission, not approval or external installation.

## App Store Review — completed afterward

- Selected the saved Merchant version 1.0. Verified Build 69, Save disabled and
  Sign-in required off, with existing demo Notes retained.
- Clicked **Add for Review**. Apple's validation completed and moved the version
  from Prepare for Submission to **Ready for Review**. The submission drawer
  contained exactly **iOS App 1.0 / 1.0.0 (69)**.
- The Mac locked before the final action. After the owner unlocked it, re-read
  the one-item drawer and clicked **Submit for Review** under the owner's explicit
  instruction. Apple displayed **1 Item Submitted** and **Draft Submissions (0)**.
- Opened the resulting iOS Submission record: **Items Submitted (1)**, exact
  **iOS App 1.0 / 1.0.0 (69)**, **Waiting for Review**. Apple displays Date Submitted
  **29 October 2026 at 12:33 AM** in the current local session.
- A full reload independently confirmed **Waiting for Review**, one item and
  the same Build 69. The final submission record remains accessible in the owner’s
  App Store Connect account; no cancellation or resubmission was performed.

## Boundaries

- Both queues are **Waiting for Review**, not In Review, approved or released.
- The previously saved automatic release on App Review approval setting was not
  changed. Final approval and resulting availability are Apple's later decisions.
- No new archive, build upload, app-source change, production migration, backend
  deployment, country/price/device change, Apple account/role grant, order, payout
  or Customer/Admin listing mutation occurred.
- Only submission verification documents were edited/committed in this follow-up.
  Known native/app/artwork working-tree changes were preserved; no test rerun is
  claimed or needed for documentation and App Store metadata-only operations.
