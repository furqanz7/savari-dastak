# Savari and Dastak Hardening and Pilot Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the completed product contracts for reliable iOS operation, privacy, localization, accessibility, observability, two-sided testing, TestFlight, and a controlled Vaniyambadi pilot.

**Architecture:** Active job events use private Realtime only as a wake-up and always re-fetch an authoritative server snapshot. APNs covers background/terminated delivery; local persistence holds no privileged job state. Scheduled backend jobs enforce retention and detect operational failures. A deployment gate promotes only tested migration/function versions from non-production to production after the separate UI/UX plan has been approved and implemented.

**Tech Stack:** SwiftUI/iOS 17, XCTest/XCUITest, Core Location, MapKit, APNs, Supabase Realtime/Edge Functions/Storage/pg_cron/pg_net, pgTAP, Deno, GitHub Actions, TestFlight.

## Global Constraints

- Complete the foundation, Savari core, Dastak core, and cross-product plans first.
- Detailed UI/UX remains a separate approved planning task. This plan hardens contracts and shells; it does not invent a visual language or production screen flow.
- Publish no Android or web client. Do not add Vapor.
- Tamil and English ship together using the device language. Keep all product strings out of Swift source literals except localization keys and test fixtures.
- Exact participant location and phone data exist only for the active job purpose. Exact route trace retention is 90 days, then delete or irreversibly coarsen it.
- Push notifications contain no phone number, precise coordinate, boarding code, payment credential, prescription, or sensitive merchant item detail.
- The archived prototype never receives an update, migration, TestFlight build, or production secret.
- All deployment, sandbox, and smoke tests target non-production until the explicit pilot gate passes.
- Paan Corner may be included in the iOS pilot and TestFlight build only after its complete restricted-product release checklist is signed off. When included, it must be a real, fully tested capability with no concealed path, generic activation switch, or policy bypass; the checklist records applicable legal/distribution review and current Apple App Review risk review, not a guarantee of approval.

---

### Task 1: Make configuration, authentication restoration, and deployment selection explicit

**Files:**
- Create: `Apps/Configuration/Savari.Debug.xcconfig.example`
- Create: `Apps/Configuration/Savari.Release.xcconfig.example`
- Create: `Apps/Configuration/Dastak.Debug.xcconfig.example`
- Create: `Apps/Configuration/Dastak.Release.xcconfig.example`
- Create: `Apps/Savari/Savari/AppConfiguration.swift`
- Create: `Apps/Dastak/Dastak/AppConfiguration.swift`
- Create: `Apps/Savari/SavariTests/AppConfigurationTests.swift`
- Create: `Apps/Dastak/DastakTests/AppConfigurationTests.swift`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/SupabaseSessionRestorer.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/SupabaseSessionRestorerTests.swift`
- Create: `scripts/deploy-backend.sh`
- Modify: `.gitignore`
- Modify: `README.md`

**Interfaces:**
- Consumes: target-specific Supabase public URL/key, Apple/Google OAuth values, and non-production/production deployment environment.
- Produces: a fail-fast `AppConfiguration`, a deterministic restored session check, and a command that cannot accidentally deploy to the prototype or wrong product.

- [ ] **Step 1: Write configuration and expired-session tests**

Create tests covering three cases:

```swift
func testConfigurationRejectsMissingSupabaseURL() {
    XCTAssertThrowsError(try AppConfiguration(values: [:]))
}

func testConfigurationUsesNamedProductBackend() throws {
    let config = try AppConfiguration(values: [
        "MARKETPLACE_PRODUCT": "savari",
        "SUPABASE_URL": "https://savari.test.supabase.co",
        "SUPABASE_PUBLISHABLE_KEY": "test-publishable-key"
    ])
    XCTAssertEqual(config.product, .savari)
}

func testExpiredRestoredSessionDoesNotAuthenticateUser() async {
    let result = await FakeSessionRestorer(sessionExpired: true).restore()
    XCTAssertEqual(result, .signedOut)
}
```

Define `SessionRestoring` with `restore() async -> SessionRestoreResult`, where `SessionRestoreResult` is `.authenticated` or `.signedOut`. `FakeSessionRestorer` is a test-only conformer that returns `.signedOut` when `sessionExpired` is true. `SupabaseSessionRestorer` is the production conformer and must return `.signedOut` when Supabase emits no session or an expired session.

- [ ] **Step 2: Run the failing configuration tests**

```bash
swift test --package-path Packages/MarketplaceInfrastructure
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: FAIL because configuration and session restoration types do not exist.

- [ ] **Step 3: Implement non-secret target configuration and strict startup checks**

Each `.xcconfig.example` must include only public endpoint configuration:

```xcconfig
MARKETPLACE_PRODUCT = savari
SUPABASE_URL = https://example.supabase.co
SUPABASE_PUBLISHABLE_KEY = replace-me
GOOGLE_CLIENT_ID = replace-me.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.replace-me
```

Ignore actual `Secrets.xcconfig` files. `AppConfiguration` reads Info.plist-injected values, requires matching product names, HTTPS URL, nonempty publishable key, and a non-placeholder Google client/reversed-client pair. It must never accept a service role, Razorpay secret, bridge secret, or Apple Maps private key.

Configure Supabase Auth so the initial session behavior uses the current Supabase Swift opt-in `emitLocalSessionAsInitialSession: true`, then independently checks `session.isExpired` before routing a user into an authenticated store.

- [ ] **Step 4: Make backend deployment target explicit**

Create `scripts/deploy-backend.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

product="$1"
environment="$2"
case "$product:$environment" in
  Savari:nonprod|Dastak:nonprod|Savari:production|Dastak:production) ;;
  *) echo "usage: $0 {Savari|Dastak} {nonprod|production}" >&2; exit 64 ;;
esac

if [[ "$environment" == "production" && "${CONFIRM_PRODUCTION_DEPLOY:-}" != "$product" ]]; then
  echo "Set CONFIRM_PRODUCTION_DEPLOY=$product to deploy production" >&2
  exit 65
fi

cd "Backends/$product"
supabase db push --linked --include-all --yes
for function_dir in supabase/functions/*; do
  function_name="$(basename "$function_dir")"
  [[ "$function_name" == "_shared" || "$function_name" == "tests" ]] && continue
  supabase functions deploy "$function_name"
done
```

Keep project refs only in local Supabase link metadata. The script must never reference `Legacy/SavariPrototype`.

- [ ] **Step 5: Verify configuration and deployment safeguards**

Run:

```bash
set +e
scripts/deploy-backend.sh Savari prototype
test $? -eq 64
scripts/deploy-backend.sh Savari production
test $? -eq 65
set -e
swift test --package-path Packages/MarketplaceInfrastructure
```

Expected: the first command exits with usage code 64, the second exits with code 65 without the confirmation variable, and all configuration/session tests pass.

- [ ] **Step 6: Commit configuration hardening**

```bash
git add Apps/Configuration Apps Packages scripts .gitignore README.md
git commit -m "chore: harden marketplace configuration"
```

### Task 2: Add private Realtime wake-ups, APNs registration, and recovery from interruption

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715130000_realtime_notifications.sql`
- Create: `Backends/Dastak/supabase/migrations/20260715130000_realtime_notifications.sql`
- Create: `Backends/Savari/supabase/functions/register-device/index.ts`
- Create: `Backends/Dastak/supabase/functions/register-device/index.ts`
- Create: `Backends/Savari/supabase/functions/send-job-wake/index.ts`
- Create: `Backends/Dastak/supabase/functions/send-job-wake/index.ts`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/VersionedSnapshot.swift`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/JobWakeCoordinator.swift`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/PushTokenRegistrar.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/JobWakeCoordinatorTests.swift`
- Create: `Apps/Savari/Savari/AppDelegate.swift`
- Create: `Apps/Dastak/Dastak/AppDelegate.swift`
- Create: `Apps/Savari/SavariTests/BackgroundRideRecoveryTests.swift`
- Create: `Apps/Dastak/DastakTests/BackgroundDeliveryRecoveryTests.swift`

**Interfaces:**
- Consumes: authenticated device token, active job participant relationship, private Realtime topic, APNs payload, and a snapshot fetch closure.
- Produces: a durable device registration and a wake coordinator that re-fetches state after every background/foreground/notification/reconnect condition.

- [ ] **Step 1: Write failure-first recovery tests**

Create this generic coordinator test:

```swift
private struct TestSnapshot: VersionedSnapshot {
    let stateVersion: Int64
}

private actor SnapshotSequence {
    private var snapshots: [TestSnapshot]

    init(_ snapshots: [TestSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> TestSnapshot {
        snapshots.removeFirst()
    }
}

func testDuplicateWakeFetchesSnapshotButDoesNotApplyOlderVersion() async {
    let source = SnapshotSequence([
        TestSnapshot(stateVersion: 2),
        TestSnapshot(stateVersion: 1)
    ])
    let coordinator = JobWakeCoordinator<TestSnapshot>(fetch: { await source.next() })

    await coordinator.handleWake()
    await coordinator.handleWake()

    let version = await coordinator.currentVersion
    XCTAssertEqual(version, 2)
}
```

Define `VersionedSnapshot` in `MarketplaceInfrastructure` as a `Sendable` protocol with `var stateVersion: Int64 { get }`. `JobWakeCoordinator` is an actor generic over `Snapshot: VersionedSnapshot`, accepts an `@Sendable () async throws -> Snapshot` fetch closure, and replaces its current version only when the fetched value is newer. `RideSnapshot` and `DeliverySnapshot` conform to this protocol in their respective product packages.

Add test fixtures for app termination then APNs wake, app background then Realtime wake, network loss/reconnect, and duplicate notification. All must result in an authoritative fetch rather than a locally invented state.

- [ ] **Step 2: Run the failing recovery tests**

```bash
swift test --package-path Packages/MarketplaceInfrastructure
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: FAIL because wake coordinator and app delegates do not exist.

- [ ] **Step 3: Create participant-only Realtime and device registration policies**

Create `private.device_installations` containing account ID, app bundle, APNs token, environment, `last_seen_at`, and revocation timestamp. Only `register-device` can insert/update it. It validates that token belongs to caller and bundle is one of the exact product target identifiers.

Create Realtime policies on `realtime.messages` so a user can receive a `ride:<uuid>` or `delivery:<uuid>` topic only if they are a current participant. The broadcast payload is exactly `{ "jobID": "<uuid>", "stateVersion": <integer> }`; it contains no contact, fare, location, code, product, or payment data.

- [ ] **Step 4: Implement push and app recovery behavior**

`send-job-wake` is called only by product transition functions after the database transaction commits. It sends an APNs `content-available` payload plus a generic localized alert key; it must not disclose sensitive data in the payload. `JobWakeCoordinator` calls the active ride/delivery snapshot function on a Realtime wake, APNs wake, scene activation, connection restoration, and explicit pull-to-refresh.

`PushTokenRegistrar` re-registers after each new APNs token, user sign-in, account link change, and app reinstall. It revokes the current device token on sign-out.

- [ ] **Step 5: Verify private-topic behavior and recovery**

Add database tests that assert a nonparticipant cannot subscribe to active job topics. Run:

```bash
cd Backends/Savari && supabase db test supabase/tests/database/040_realtime_notifications.pgtap.sql --local
cd ../Dastak && supabase db test supabase/tests/database/040_realtime_notifications.pgtap.sql --local
swift test --package-path ../../Packages/MarketplaceInfrastructure
```

Expected: unauthorized topic access fails and the coordinator rejects out-of-order snapshots.

- [ ] **Step 6: Commit notification and recovery work**

```bash
git add Backends Apps Packages
git commit -m "feat: add resilient job wake recovery"
```

### Task 3: Enforce privacy retention, document access expiry, and redacted observability

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715131000_privacy_retention.sql`
- Create: `Backends/Dastak/supabase/migrations/20260715131000_privacy_retention.sql`
- Create: `Backends/Savari/supabase/functions/purge-expired-location-data/index.ts`
- Create: `Backends/Dastak/supabase/functions/purge-expired-location-data/index.ts`
- Create: `Backends/Savari/supabase/functions/tests/privacy/retention.test.ts`
- Create: `Backends/Dastak/supabase/functions/tests/privacy/retention.test.ts`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/MarketplaceLog.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/MarketplaceLogTests.swift`
- Create: `docs/operations/privacy-retention.md`

**Interfaces:**
- Consumes: finished job timestamps, encrypted/private route trace records, signed evidence URL requests, and error events.
- Produces: 90-day exact trace cleanup, terminal snapshot redaction, short-lived document access, and diagnostics that cannot print sensitive values.

- [ ] **Step 1: Write retention and logging tests**

Create retention tests with one trace at 89 days and one at 91 days. Assert only the 91-day exact coordinates are deleted or replaced by a coarse grid cell. Create a `MarketplaceLog` test that passes a raw boarding code, phone number, Razorpay payment ID, and prescription object, then asserts the rendered message contains none of them.

- [ ] **Step 2: Run the failing privacy tests**

```bash
cd Backends/Savari && deno test --allow-env supabase/functions/tests/privacy/retention.test.ts
cd ../Dastak && deno test --allow-env supabase/functions/tests/privacy/retention.test.ts
swift test --package-path ../../Packages/MarketplaceInfrastructure
```

Expected: FAIL because retention jobs and redacting log wrapper do not exist.

- [ ] **Step 3: Implement exact location retention and terminal redaction**

Create a private scheduled cleanup function that operates on completed/cancelled job trace rows whose terminal timestamp is older than 90 days. It either deletes the exact trace or replaces it with a precomputed coarse grid geometry with no reconstructable point sequence. It must never purge trace rows for an open safety case, pending chargeback, or legally retained owner review; those exceptions retain only the minimum audit linkage.

When ride/delivery status becomes terminal, snapshot functions omit participant phone, exact live location, boarding/delivery codes, and sensitive order evidence. Existing signed evidence URLs expire in 300 seconds and are not refreshable after authorization ends.

- [ ] **Step 4: Implement redacted structured logging**

Create a wrapper with this interface:

```swift
public enum MarketplaceLog {
    public static func event(_ name: String, metadata: [String: LogValue] = [:])
}

public enum LogValue: Sendable {
    case publicText(String)
    case privateText(String)
    case identifier(UUID)
    case count(Int)
}
```

`privateText` writes `.private(mask: .hash)` to `Logger`; it never reaches standard debug output. Replace the archived prototype logging only if archive code is re-opened for migration investigation; no new clean target imports `SavariLog`.

- [ ] **Step 5: Schedule, test, and document privacy cleanup**

Use Supabase Cron with Vault-held endpoint/key values to invoke each product's purge function daily. Add `docs/operations/privacy-retention.md` listing data class, purpose, retention duration, deletion/coarsening action, safety/dispute exception, and owner escalation route.

Run:

```bash
cd Backends/Savari && deno test --allow-env supabase/functions/tests/privacy
cd ../Dastak && deno test --allow-env supabase/functions/tests/privacy
```

Expected: older traces are handled correctly, open cases remain protected, and redaction tests pass.

- [ ] **Step 6: Commit privacy hardening**

```bash
git add Backends Packages docs/operations
git commit -m "feat: add privacy retention controls"
```

### Task 4: Add Tamil/English localization and accessibility test infrastructure without redesigning UI

**Files:**
- Create: `Apps/Savari/Savari/Resources/en.lproj/Localizable.strings`
- Create: `Apps/Savari/Savari/Resources/ta.lproj/Localizable.strings`
- Create: `Apps/Dastak/Dastak/Resources/en.lproj/Localizable.strings`
- Create: `Apps/Dastak/Dastak/Resources/ta.lproj/Localizable.strings`
- Create: `Apps/Savari/SavariTests/LocalizationContractTests.swift`
- Create: `Apps/Dastak/DastakTests/LocalizationContractTests.swift`
- Create: `Apps/Savari/SavariUITests/AccessibilityContractTests.swift`
- Create: `Apps/Dastak/DastakUITests/AccessibilityContractTests.swift`
- Create: `docs/operations/localization-glossary.md`

**Interfaces:**
- Consumes: stable localization keys from product stores and future UI composition.
- Produces: device-language English/Tamil resource coverage and testable accessibility identifiers, without specifying visual design.

- [ ] **Step 1: Create failing localization parity tests**

The tests must load both `.strings` files, compare key sets, and fail if either language has a missing or blank value. Seed them with the shared lifecycle keys:

```text
ride.status.requested
ride.status.in_progress
ride.status.payment_due
delivery.status.ready
delivery.status.picked_up
common.error.retry
common.action.sign_out
```

- [ ] **Step 2: Run the failing parity tests**

```bash
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: FAIL because resource bundles and tests are absent.

- [ ] **Step 3: Add English/Tamil strings and product language rules**

Add an English and Tamil value for every seeded key. Use `String(localized: "key", bundle: .module)` through a small localization adapter; do not hard-code user-visible lifecycle wording inside store/repository code. Write `docs/operations/localization-glossary.md` with fixed terms for ride, driver, delivery partner, boarding code, pickup, destination, payment due, and safety report.

- [ ] **Step 4: Add accessibility contract tests to functional shells**

When a functional screen exposes an action, it must give the control a stable identifier and VoiceOver label. The initial test set must assert access to sign-in, passenger/driver switch, current ride state, current delivery state, cancel, safety action, and sign-out. Avoid asserting geometry, colours, or copy layout; that belongs to the deferred UI plan.

- [ ] **Step 5: Verify language and accessibility contracts**

```bash
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: English/Tamil key parity and all current accessibility identifiers pass.

- [ ] **Step 6: Commit localization infrastructure**

```bash
git add Apps docs/operations
git commit -m "feat: add marketplace localization contracts"
```

### Task 5: Establish CI, simulator fault injection, and security advisor gates

**Files:**
- Create: `.github/workflows/quality-gate.yml`
- Create: `scripts/run-fault-injection.sh`
- Create: `scripts/check-supabase-advisors.sh`
- Create: `docs/operations/qa-matrix.md`
- Modify: `scripts/test-foundation.sh`

**Interfaces:**
- Consumes: product-local test suite, local simulator targets, local Supabase Docker runtime, and non-production advisor credentials.
- Produces: a repeatable CI gate with explicit network, Realtime, app-lifecycle, security, and payment replay coverage.

- [ ] **Step 1: Write the QA matrix before automation**

Create `docs/operations/qa-matrix.md` with one row for each required scenario and expected state source:

```text
Background during assignment | APNs wake then snapshot | assigned state version increases
Force quit during trip | relaunch then snapshot | in_progress preserved
Lost network during action | retry same idempotency key | one server event
Delayed Realtime event | fetch snapshot | no rollback to older version
Duplicate webhook | provider event dedup | one payment/ledger event
Driver stale location | action denied | stale_location error
```

- [ ] **Step 2: Implement the fault injection command**

Create `scripts/run-fault-injection.sh` that runs both function acceptance suites with mocked timeout/retry/replay fixtures, then runs the iOS contract suites. It must fail the shell on first unexpected success/failure:

```bash
#!/usr/bin/env bash
set -euo pipefail

scripts/run-savari-acceptance.sh
scripts/run-dastak-acceptance.sh
scripts/run-cross-product-acceptance.sh
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

- [ ] **Step 3: Add a no-warning advisor gate with explicit exception policy**

`scripts/check-supabase-advisors.sh` runs `supabase db lint --linked --output json` inside each non-production backend. Parse JSON and fail for every `ERROR` and every `WARN` except `auth_leaked_password_protection` while the product remains on a free Supabase plan. The script must print the exact exception name and state that it is a dashboard plan limitation, not a code waiver.

When a paid plan is enabled, remove the exception and require leaked-password protection to be enabled in the Supabase Auth email provider settings.

- [ ] **Step 4: Configure CI jobs and test order**

Create `quality-gate.yml` with these jobs: `format-and-diff`, `swift-packages`, `savari-db-functions`, `dastak-db-functions`, `cross-product`, `ios-unit`, `ios-ui-contract`, and `advisor-nonprod`. The advisor job runs only when protected non-production credentials are available; it must not use production secrets in pull requests.

- [ ] **Step 5: Run the local quality gate and commit**

```bash
scripts/run-fault-injection.sh
scripts/check-supabase-advisors.sh Savari
scripts/check-supabase-advisors.sh Dastak
git diff --check
```

Expected: every fault test passes and advisor output contains no unapproved warning/error.

```bash
git add .github scripts docs/operations
git commit -m "ci: add marketplace quality gates"
```

### Task 6: Prepare TestFlight and execute the controlled Vaniyambadi pilot gate

**Files:**
- Create: `docs/operations/testflight-checklist.md`
- Create: `docs/operations/vaniyambadi-pilot-gate.md`
- Create: `docs/operations/incident-runbook.md`
- Create: `docs/operations/production-secrets-inventory.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: approved UI/UX implementation, non-production TestFlight builds, manually approved pilot participants, production provider configuration, and passing quality gates.
- Produces: a written go/no-go decision with owner signatures and a rollback path.

- [ ] **Step 1: Write the TestFlight checklist**

`testflight-checklist.md` must require one build each for Savari, Savari Admin, Dastak, Dastak Merchant, and Dastak Admin with correct bundle ID, App Store Connect record, Apple/Google sign-in redirect, Maps capability, APNs environment, privacy manifest, and localization. For a Paan Corner-enabled build, it must additionally require the documented restricted-product release decision, 18+ attestation/terms version test, merchant and delivery exclusion-zone rejection test, owner-approved merchant/product evidence test, prohibited vaping product rejection test, partner visual-check success and failure/return tests, and no sensitive age detail in push/logging. It must require two-sided testers: one passenger/driver pair and one customer/partner/merchant pair.

- [ ] **Step 2: Write pilot data and safety gates**

`vaniyambadi-pilot-gate.md` must require an active polygon verified on a physical device, a small manually approved driver/partner/merchant/pharmacy cohort, current documents, safe payout profiles, sandbox-to-live Razorpay verification, owner account recent-sign-in test, emergency `112` action test, and a successful refund/adjustment reconciliation rehearsal. When Paan Corner is enabled, it must also require current merchant/product evidence, owner-maintained 91.44m school/college exclusion-zone coverage, age/terms and visual-handoff evidence, applicable legal/distribution review, and a documented current Apple App Review risk decision.

- [ ] **Step 3: Document incident and rollback actions**

`incident-runbook.md` must include one deterministic action for each event: disable new bookings, disable partner availability, suspend a participant, refund an in-app payment, create a payout adjustment, revoke a document URL, rotate bridge/Razorpay/provider secrets, and roll back an app release. State which product owner app/function records the audit event for each action.

- [ ] **Step 4: Create an owner-only secret inventory**

`production-secrets-inventory.md` lists the secret name, product project, storage location, rotation owner, rotation cadence, and verification command for Apple Maps token, Supabase service role, bridge secret, Razorpay key/webhook secret, APNs credentials, and OAuth provider secret. It must contain no secret value.

- [ ] **Step 5: Run the final non-production gate**

Run, after the deferred UI/UX plan and its implementation are complete:

```bash
scripts/test-foundation.sh
scripts/run-savari-acceptance.sh
scripts/run-dastak-acceptance.sh
scripts/run-cross-product-acceptance.sh
scripts/run-fault-injection.sh
```

Expected: all commands pass against non-production. Install the five TestFlight builds and execute every row in `qa-matrix.md` with the pilot testers before considering a production deploy.

- [ ] **Step 6: Commit the pilot runbooks**

```bash
git add docs/operations README.md
git commit -m "docs: add marketplace pilot release gates"
```

## Pilot Completion Gate

- The separately approved UI/UX plan has been implemented and tested. This hardening plan does not bypass that requirement.
- All five targets build from `SavariDastak.xcworkspace`, use their intended non-production configuration, and pass unit/UI contract tests.
- Each backend passes fresh migrations, RLS/storage tests, Edge Function tests, advisor gate, and payment sandbox replay checks.
- Two-sided real-device TestFlight tests prove background/relaunch/reconnect/idempotency recovery.
- Exact location retention, signed evidence URL expiry, contact redaction, logging redaction, and account link consent are verified.
- Vaniyambadi zone, operations runbooks, manual approvals, refunds, payouts, safety cases, and production secrets are signed off by the owner.
- Any Paan Corner-enabled Dastak iOS build passes the complete restricted-product release checklist, including age/terms, location, merchant/product evidence, visual-handoff failure/return, and current legal/distribution/App Review risk records. An unmet release gate blocks Paan Corner from that release; it does not justify a concealed capability.
