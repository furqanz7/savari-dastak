# Merchant push environment correction — Build 63

19 October 2026, Asia/Kolkata. The owner passed Grocery/Food operational checks on Build 62 but reported that no Merchant notifications arrived. Notification acceptance therefore failed; prior UI and lifecycle passes were not a push-delivery sign-off.

**Outcome:** Build 63 compiled, passed strict/deep signature verification, was installed over Build 62 and launched on the owner's iPhone. The installed version independently reports `1.0.0 (63)`. A subsequent read-only server check confirms a newly active **sandbox** Merchant registration, last seen at `2026-10-18T21:17:45.517327Z`; the prior production registration remained at its older timestamp. The owner subsequently confirmed fresh notification arrival and all three foreground/background/closed-app notification checks. This is owner-reported acceptance, not an automated device observation or an exactly-once delivery guarantee for every future event.

## Confirmed cause and diagnosis scope

Build 62 was compiled in Release configuration but development-signed. Its actual signed entitlement and embedded provisioning profile both specify `aps-environment = development`. The shared registration helper instead selected `production` from the absence of `DEBUG`. That registered a sandbox token for the production APNs endpoint.

Read-only production metadata confirmed all eight required Merchant routes enabled and the outbox worker scheduled. The four observed recent Merchant delivery attempts (opportunity, preparation started, rider assigned, rider arrived) were `DEAD_LETTER`, with APNs HTTP 400 / `BadDeviceToken`, and their token registration specified production. No raw device tokens, account/order identifiers, notification content or credentials were printed. This identifies the environment mismatch; it is not a claim that every future notification or Food event has been independently tested.

## Local correction

- `DastakAPNSEnvironment` reads the XML entitlement plist within the current app's embedded provisioning profile, using Foundation only. Development resolves to sandbox; distribution resolves to production. A present unreadable, malformed, oversized or unknown profile is refused instead of silently guessing.
- Store/TestFlight installations without an embedded profile use production APNs. A sandbox StoreKit receipt is not mistaken for sandbox APNs. Simulator selection remains sandbox, independently of compiler configuration.
- The resolver does not call private Security APIs, load any user provisioning files, refresh StoreKit receipts or make network requests. It reads only the app's own bundle. This profile parsing is routing configuration, not an authorization mechanism.
- Merchant registration refuses an unknown environment with visible failure state and no token-registration request. Existing account checks, fresh Apple callbacks, topic, timeouts and bounded recovery are unchanged.
- The shared notification helper and Live Activity registration use the same resolver. Live Activity registration skips an unresolvable environment rather than registering a wrong host. Existing Customer/Delivery binaries are not replaced by the Merchant installation; this correction would apply when they are next rebuilt.
- No database migration, function deployment, secret/provider setting or route change is required. No existing token row is rewritten, old alert replayed or synthetic order/notification created. The corrected app uses its normal signed-in fresh-token registration path.

## Verification

- **25 focused tests passed**: seven resolver tests and 18 Merchant registration tests, including the three new request/fail-closed cases.
- **758 UI/model tests passed**, zero failures. Existing shared Customer/Delivery topic tests remain green.
- An optimized executable compiled **without `DEBUG`** resolved Build 62's actual CMS-wrapped development profile to sandbox, a production profile and absent Store profile to production, and malformed data to refusal.
- Logs: `/tmp/dastak-merchant-build63-notification-tests.log`, `/tmp/dastak-merchant-build63-ui-tests.log`; independent Release harness under `/private/tmp/dastak-merchant-push63.HJ0yVl`.

## Build and acceptance status

Build 63 was prepared from the isolated, previously verified app/package source plus exactly the four runtime correction files. The earlier eight dependency pins remain frozen; unrelated working-tree Customer fixtures, artwork and release files are excluded. The implementation/install phase made no source commit/push. After successful owner acceptance, the owner separately authorized a checkpoint containing only these four runtime files, two regression-test files and this report/receipt. The Git commit containing this report identifies that checkpoint. No runtime source was changed after the installed Build 63 hashes were recorded. The earlier Build 62 app is retained separately before reuse of its task build cache.

The signed artifact is `/private/tmp/dastak-merchant-push63.HJ0yVl/Build63.app`, with executable SHA-256 `33df46fc9cb8c0d6a4a55134d923a89dc0cbe51a4f864737b32f9dda30536303`. The signed `aps-environment` remains `development`, and the optimized resolver independently confirms sandbox from this exact profile. The app configuration matches Dastak production. Native build log: `/tmp/dastak-merchant-build63-iphone.log`; native install/version/launch receipts are retained alongside the artifact.

Permanent machine-readable [correction receipt](evidence/dastak-merchant-push-environment-fix-2026-10-19.json). Registration alone was not counted as proof of notification presentation. The owner first confirmed a fresh notification arrived, then replied **"All three notification checks passed"** after the following requested checks:

1. Background notification delivery/tap reaches the correct location and request/order, or the appropriate queue when no exact target exists.
2. Closed-app notification delivery/tap preserves its destination through launch/authentication.
3. Foreground events update the appropriate queue without relaunch or duplicate alerts for the same observed event.

These three tested conditions are now recorded as owner-confirmed passes on Build 63. This does not independently measure every alert type, future timing/retries or all account/device combinations. Old dead letters were not silently replayed. The old incorrectly registered production row was not manually deleted, rewritten or re-enabled; normal existing provider-error handling remains responsible for its later rejection. Customer/Delivery were not installed or replaced. Broader iPad/accessibility acceptance and Merchant distribution remain separate.

References checked during this correction: [Apple APNs entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment), [Apple troubleshooting guidance](https://developer.apple.com/library/archive/technotes/tn2265/_index.html), [Apple provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles). The Supabase skill informed the read-only, metadata-only diagnosis and separation between token registration and verified delivery.
