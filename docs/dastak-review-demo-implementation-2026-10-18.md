# Isolated Customer + Delivery demo — 18 October 2026

## Subsequent distribution checkpoint

The local implementation described below was subsequently packaged as **Build 61**, uploaded and processed for internal TestFlight. Apple reports that exact build installed on the owner's iPhone; the owner reported the three demo smoke checks passed. Build 61 and accurate demo notes are now saved for App Store version 1.0. With separate owner authorization, **Add for Review** passed and created a **Ready for Review** draft containing **1.0.0 (61)**. **Submit for Review** remains untouched. Privacy was separately published with the owner's action-time confirmation. These later observations supersede the corresponding original pending items below, not the limitations of the recorded tests. See [binary evidence](verification/dastak-testflight-build61-2026-10-18/README.md), [saved notes](dastak-build61-review-notes-2026-10-18.md) and [latest preflight](dastak-build61-final-preflight-2026-10-18.md).

## Status and authority

The owner authorized implementation after the read-only release audit. This is a local implementation checkpoint, **not an App Store approval, new TestFlight upload or review submission**. Build 60 in App Store Connect does not contain this new code. No production database, account, role, deployment or privacy declaration was changed.

Apple's original beta rejection permits a fully featured demonstration mode. Its newer reply says Apple cannot assess proposed changes and asks for a revised build. That reply is not specific approval of this implementation. Review access and final review notes must be verified against the actual distributed binary before submission.

## Entry and walkthrough

- The normal sign-in panel keeps Apple and Google and adds a visible **Explore the demo** button. The equivalent public `com.dastak.app://demo` link opens the same view; there is no hidden reviewer detection.
- The demo displays a DEMO header, Customer/Delivery switch, Guide, Reset and Exit. Reset recreates the local engine and both workspaces. Exit returns to normal sign-in without signing anyone in or changing real access.
- Shop in Grocery or Food using the existing screens, pick up the basket, change quantities, select sizes, save favourites, and edit/select sample delivery addresses. One sample SKU is unavailable to exercise out-of-stock presentation.
- Place a sample order and confirm the doorstep-payment option. It first enters **Preparing your order**. Guide → **Sample merchant: mark order ready** explicitly advances to **Assigning your rider** and exposes a sample rider offer.
- Switch to Delivery, refresh and accept the offer. Exercise start/arrival/pickup, final route, customer arrival, PIN verification, sample package photo, simulated collection and completion. Sample pickup/customer PIN: **123456**. Package count: **1**.
- The real Delivery operations model uses the same in-memory API and a separate memory-only recovery journal. It does not bypass custody, PIN, photo or collection gates. Rejections use explicit 4xx errors so a mistyped sample step does not become an indefinitely uncertain action.
- Full order, completed history and earnings presentation use synthetic records. Delivered Customer orders expose sample issue reporting. Profile editing and export are local. No actual account exists to delete or link, and no real payout destination or withdrawal can be created.
- After a delivered order, or a delivery problem after pickup, Guide → **Sample Operations: assign a return** enables the return workflow. Use the sample photo and **123456** for pickup/merchant receipt. This creates no actual return, refund or dispatch.
- Existing navigation actions (Grocery, Food, Search, Basket, Track Order) target the mounted sample Customer workspace while demo is open. Real order-notification routes are ignored by that workspace. Demo notification taps are handled only while a demo routing handler is mounted.

## Isolation boundaries

`DastakReviewDemoClient` has no network transport, URL, credentials, session loader or production client. Its `MarketplaceAuthenticatedServices` factory binds every business operation to the local actor. Unknown endpoints fail closed. Idempotent mutation receipts are bound to their original canonical request; fresh independent reads recover current sample state.

Orders, addresses, favourites, profile edits, collection state and recovery journals live in memory. Small Customer preferences use a randomly named demo-only UserDefaults suite, never the standard account preferences; it is wiped on reset/exit and never reopened by a later session. A crash does not restore a demo session. Existing production basket and recovery files are neither loaded nor deleted. The production preference behavior is preserved and covered by its existing deletion/retention tests.

Sample catalogue artwork is bundled under the reserved `review-demo/` namespace. Missing or invalid sample paths never fall through to the production Storage URL builder. No real identity/evidence document is requested for the walkthrough; sample evidence is discarded by the local uploader. Sample GPS eligibility is provided by the local engine; the demo tracker does not request location authorization or start continuous/background location. External links and phone calls are discarded within the demo view environment.

## System surfaces

Guide offers optional **local sample updates**. It requests notification presentation permission only on explicit selection and does not register a remote device token. Sample notifications say Demo and contain no real entity route. The sample Live Activity uses the real renderer with a DEMO order number and `pushType: nil`. Only its own activity and notification identifiers are ended/removed on reset or exit; generation checks prevent late callbacks from recreating them.

This demonstrates native presentation, **not remote APNs, server-driven background updates, real GPS, real calls, payment execution, OAuth linking or account deletion**. Those remain normal-account features and must not be misrepresented in review notes. Widgets continue to be navigation entry points, not fictional server data.

## Verification checkpoint

- Full DastakUI package suite: **555 tests, zero failures**. Includes Customer→Delivery model integration with in-memory journals, pickup/PIN/photo/collection/completion, terminal full order, completed history, the complete return/receipt chain, and local artwork fail-closed checks.
- Full MarketplaceInfrastructure package suite: **189 tests, zero failures** at the recorded checkpoint. Focused demo tests were rerun after local actor refinements: **4 tests, zero failures**.
- Authentication environment regression checks: **2 tests, zero failures**.
- Native iOS Release simulator build succeeded with signing disabled. An earlier iOS-only ActivityKit concurrency diagnostic was corrected with the same pre-concurrency import used by the existing production controller. macOS package tests alone were not treated as proof of iOS compilation.
- Final post-edit arm64 iOS Release simulator build also exited successfully. The final full suites remained green at 555 UI tests and 189 infrastructure tests. The dedicated simulator was returned to its original shut-down state after captures; no physical iPhone was installed or operated in this implementation pass.
- The Release binary was installed and launched in the dedicated iPhone 17 Pro simulator. The sign-in demo entry, scrollable guide, Grocery and Food were visually inspected through native simulator screenshots. Existing app-navigation links switched between the mounted sample services without signing in. Evidence: [sign-in](verification/dastak-review-demo-2026-10-18/release-signin.png), [guide](verification/dastak-review-demo-2026-10-18/release-guide.png), [Grocery](verification/dastak-review-demo-2026-10-18/release-grocery.png), [Food](verification/dastak-review-demo-2026-10-18/release-food.png). This does not claim a physical-device tap-through or verification of optional system presentations.
- `git diff --check` passed at the checkpoint. Existing unrelated release/screenshot/asset edits were preserved; nothing was committed or pushed.

Commands: `swift test --package-path Packages/DastakUI --jobs 2`, `swift test --package-path Packages/MarketplaceInfrastructure --jobs 2`, and `xcodebuild -workspace SavariDastak.xcworkspace -scheme Dastak -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/dastak-quality-derived -quiet CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build`.

## Remaining distribution gates

1. Finish native visual/manual checks on iPhone and iPad, including Reset/Exit, larger text, sample notifications and Live Activity teardown. The Simulator GUI application is not available to the Mac UI-control surface; headless native captures and model tests do not claim a manual tap-through.
2. Archive/sign a new numbered build, upload it and verify processing/compliance, then install that exact binary for smoke testing. No new build number has been assigned by this checkpoint.
3. Add accurate demo access instructions to both beta and App Store review notes, including the local-only system-surface boundary. Correct the separate beta privacy-policy URL and sign-in information. Obtain authorization before saving external listing changes.
4. Resolve owner privacy-publication/trader-assessment gates and obtain explicit authority before review submission. Do not describe Apple's generic response as specific approval.

## Draft review instructions — not saved or sent

> On the sign-in screen, tap “Explore the demo”. This publicly available, clearly labelled mode uses the actual Customer and Delivery screens with isolated sample data. Apple and Google sign-in remain available for normal use.
>
> In Customer, pick up a basket and place a sample Grocery or Food order, then confirm the doorstep-payment option. Open Guide and choose “Sample merchant: mark order ready” to advance preparation to rider assignment. Switch to Delivery, refresh and accept the offer. Pickup and customer PINs are 123456; the package count is 1. Use the sample photo action, record a simulated collection and complete the delivery. Full order details, history and the Customer tracking screen reflect the sample progress. Guide also provides an explicit sample return-assignment action after delivery or a reported post-pickup problem.
>
> No real order, dispatch, payment, payout, identity upload or account-role change occurs in demo mode. Optional notifications and Live Activities demonstrate local presentation only, not remote APNs. Real OAuth, account deletion and server-driven behavior are not simulated successes. Reset recreates the sample session; Exit returns to normal sign-in.
