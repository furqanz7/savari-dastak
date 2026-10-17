# Dastak TestFlight Build 61 — 18 October 2026

Latest listing state: the owner subsequently authorized **Add for Review**. Apple's validation completed and version 1.0 is **Ready for Review**, with **1.0.0 (61)** in the draft. **Submit for Review** was not clicked. Privacy publication and regional changes were separately authorized and are recorded in [the latest preflight](../../dastak-build61-final-preflight-2026-10-18.md). The original packaging observations below remain historical evidence.

The owner authorized packaging and uploading the isolated Customer + Delivery demo for device testing. This is not authorization to submit for App Review, publish App Privacy, change trader status, grant account access or change production data.

## Source and checks

- Authoritative worktree: `codex/dastak-v1-launch`, HEAD `a62ed1377433ee45d2761e8b59c65f318c178dba`. The existing uncommitted demo/release changes are included; unrelated files are preserved. No commit/push is claimed.
- Version remains `1.0.0`; source build number is now `61`.
- The latest prior uploaded binary was Build 60, verified in Xcode Organizer and App Store Connect. Build 60 does not contain the new demo.
- Focused demo and project-configuration checks rerun for packaging: **8 passed, zero failures**. Prior complete implementation evidence: [demo checkpoint](../../dastak-review-demo-implementation-2026-10-18.md).
- Signed Release archive command uses the existing device-derived-data folder, the Dastak scheme and `generic/platform=iOS`, with archive destination `/Users/Furqan/Library/Developer/Xcode/Archives/2026-10-18/Dastak61.xcarchive`.

## Distribution state

- Signed Release archive succeeded at `/Users/Furqan/Library/Developer/Xcode/Archives/2026-10-18/Dastak61.xcarchive`.
- Main app and widget build numbers are **61**; version **1.0.0**, main bundle `com.dastak.app`, architecture **arm64**. `codesign --verify --deep --strict --verbose=2` passed.
- All five bundled demo product images are present. The packaged backend URL and publishable-key configuration are nonempty and not placeholders (values withheld). Root privacy manifest has tracking disabled and 17 collected types; diagnostic/performance declarations remain App Functionality, linked, not tracking.
- Xcode Organizer selected archive **1.0.0 (61)** and the **App Store Connect** distribution method. Organizer confirmed **App upload complete: Dastak 1.0.0 (61) uploaded**, then showed **Uploaded to Apple**, build number **61**, at **02:01 on 18 October 2026** (local time).
- App Store Connect finished processing and listed Build 61 as **Ready to Submit**. The existing internal **Testing** group lists **1.0.0 (61)** as **Testing**, expiring in 90 days. There is no remaining compliance blocker to internal testing; no encryption declaration was selected or saved by the agent.
- The internal tester page reports **Installed 1.0.0 (61), 18 October 2026**, on **iPhone 12 / iOS 27.0.1**. This is Apple-reported installation, not an agent-observed physical-device functional pass.
- Verification finished around **02:05 IST, 18 October 2026**. No new testers, groups or invitations were created by the agent.

At the upload checkpoint, the App Store review attachment, submission and privacy publication were untouched. In a subsequently owner-authorized listing update on 18 October, **Build 61 replaced Build 60** for version 1.0 and accurate demo notes were saved and verified after reload; see [saved review notes and verification](../../dastak-build61-review-notes-2026-10-18.md). Version remains **Prepare for Submission**; submission and privacy publication remain untouched. The owner reported the three physical-device demo smoke checks done; this is user-reported, not an agent-observed pass.

## Device handoff

1. From sign-in, open **Explore the demo**. Check Customer Grocery/Food and the Delivery workspace.
2. Use the **Demo guide** to prepare a sample order and advance its sample merchant state; finish the Delivery flow using PIN **123456**, one package, sample proof and simulated collection. No real order or payment is created.
3. Check **Reset** and **Exit**: sample state clears, normal sign-in remains available, and real account data is unchanged.

Optional local notification and Live Activity presentation/teardown still require explicit device testing; production remote-push delivery is not simulated by this demo.
