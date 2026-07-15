# Savari and Dastak Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the prototype layout with a clean iOS workspace and two isolated, non-production Supabase foundations that can safely support Savari and Dastak.

**Architecture:** The existing Savari app and linked Supabase project are retained as a read-only prototype archive, not migrated in place. A new workspace contains independent Savari and Dastak projects, while small local Swift packages provide only cross-product primitives. Two fresh Supabase projects use separate migration roots, private server-side schemas, authenticated Edge Functions for mutation, and read-only participant projections for clients.

**Tech Stack:** Swift 5 / iOS 17, SwiftUI, XCTest, Swift Package Manager, Supabase Swift 2.37.0, Supabase Postgres/RLS/Storage/Realtime/Edge Functions, Deno TypeScript, pgTAP, Apple Sign In, Google Sign In.

## Global Constraints

- iOS only. Do not add Android, a web app, Vapor, or a third backend.
- Use fresh Savari and Dastak non-production projects before any production project is created; never run development tests against the linked prototype project `mxpszppootpltifzvjla`.
- Keep Savari and Dastak data stores separate. Only a later signed server-to-server bridge may cross the boundary.
- Client roles are informational only. Authorization comes from server-managed membership records.
- Clients may read their authorized state, but cannot directly `INSERT`, `UPDATE`, or `DELETE` rides, deliveries, payments, payouts, approvals, or audit records.
- Sensitive evidence uses private storage. Preserve the old prototype document path only in the archived implementation; the new canonical paths are defined by the product-specific backend plans.
- UI and UX design is out of scope. Build functional application shells and testable client contracts only.
- Paan Corner is a Dastak product scope, not a disabled placeholder. Later Dastak work may support only owner-approved, non-electronic tobacco products through server-verified 18+ self-attestation, a versioned terms acknowledgement, merchant and delivery locations outside owner-maintained 91.44m school/college exclusion zones, merchant/product compliance evidence, and a Delivery Partner visual handoff check. It is a high-risk iOS release capability: no generic activation switch or concealed flow, and no pilot or TestFlight release until the Dastak release gate has documented applicable legal, distribution, and current Apple App Review risk review.
- Every state-changing Edge Function accepts an idempotency key and returns a typed error code rather than a raw database error.

## Planned Structure

```text
Apps/
  Savari/
    Savari.xcodeproj
    Savari/
    SavariTests/
    SavariAdmin/
    SavariAdminTests/
  Dastak/
    Dastak.xcodeproj
    Dastak/
    DastakTests/
    DastakMerchant/
    DastakMerchantTests/
    DastakAdmin/
    DastakAdminTests/
Backends/
  Savari/supabase/
  Dastak/supabase/
Legacy/SavariPrototype/
Packages/
  MarketplaceFoundation/
  MarketplaceInfrastructure/
  SavariDomain/
  DastakDomain/
SavariDastak.xcworkspace/
scripts/
docs/superpowers/
```

---

### Task 1: Freeze the prototype and create the clean workspace boundary

**Files:**
- Move: `Savari/` to `Legacy/SavariPrototype/Savari/`
- Move: `Savari.xcodeproj/` to `Legacy/SavariPrototype/Savari.xcodeproj/`
- Move: `supabase/` to `Legacy/SavariPrototype/supabase/`
- Create: `Legacy/SavariPrototype/README.md`
- Create: `SavariDastak.xcworkspace/contents.xcworkspacedata`
- Create: `Apps/Savari/`, `Apps/Dastak/`, `Backends/Savari/`, `Backends/Dastak/`, and `Packages/`
- Modify: `.gitignore`
- Modify: `README.md`

**Interfaces:**
- Consumes: the committed prototype at `b768fe8`.
- Produces: a workspace whose only application projects are `Apps/Savari/Savari.xcodeproj` and `Apps/Dastak/Dastak.xcodeproj`.

- [ ] **Step 1: Record the current prototype as an archive before moving it**

Create `Legacy/SavariPrototype/README.md` with this exact operational boundary:

```markdown
# Savari Prototype Archive

This directory preserves the pre-launch Savari prototype and its historical migrations.

- It is not a deployment source.
- Do not run `supabase db push`, deploy Edge Functions, or add features from this directory.
- The linked project `mxpszppootpltifzvjla` is prototype-only and must not receive launch migrations.
- The new launch implementation starts in `Apps/` and `Backends/`.
```

- [ ] **Step 2: Move the prototype and create the workspace XML**

Move the three existing roots with `git mv`; do not copy them, because the archive must retain history. Create `SavariDastak.xcworkspace/contents.xcworkspacedata` as:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version="1.0">
  <FileRef location="group:Apps/Savari/Savari.xcodeproj"/>
  <FileRef location="group:Apps/Dastak/Dastak.xcodeproj"/>
</Workspace>
```

- [ ] **Step 3: Create the two application projects with exact target membership**

In Xcode, create `Apps/Savari/Savari.xcodeproj` with iOS 17 targets `Savari`, `SavariTests`, `SavariAdmin`, and `SavariAdminTests`. Create `Apps/Dastak/Dastak.xcodeproj` with iOS 17 targets `Dastak`, `DastakTests`, `DastakMerchant`, `DastakMerchantTests`, `DastakAdmin`, and `DastakAdminTests`. Use these bundle identifiers:

```text
com.savari.app
com.savari.admin
com.dastak.app
com.dastak.merchant
com.dastak.admin
```

Set `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `SWIFT_VERSION = 5.0`, and `SUPPORTS_MACCATALYST = NO` on every app target. Add both projects to `SavariDastak.xcworkspace`; do not add `Legacy/SavariPrototype/Savari.xcodeproj`. Create and share schemes named `Savari`, `SavariAdmin`, `Dastak`, `DastakMerchant`, and `DastakAdmin` so local commands and CI see the same target set.

- [ ] **Step 4: Add deterministic ignore and root documentation rules**

Replace the Supabase ignore entry with the following `.gitignore` additions while retaining the existing Xcode ignores:

```gitignore
**/supabase/.temp/
**/supabase/.branches/
**/.env
**/.env.*
!**/.env.example
**/Secrets.xcconfig
**/.build/
```

Rewrite the root `README.md` project layout section to name `SavariDastak.xcworkspace`, `Apps/`, `Backends/`, `Packages/`, and `Legacy/SavariPrototype/`, and state that backend commands are always run from a product-specific backend directory.

- [ ] **Step 5: Verify the workspace has no prototype target dependency**

Run:

```bash
xcodebuild -list -workspace SavariDastak.xcworkspace
git diff --check
```

Expected: the workspace lists only new Savari and Dastak schemes, and `git diff --check` prints no whitespace errors.

- [ ] **Step 6: Commit the isolated workspace**

```bash
git add .gitignore README.md Legacy/SavariPrototype SavariDastak.xcworkspace Apps Backends Packages
git commit -m "chore: establish Savari Dastak workspace"
```

### Task 2: Add small, explicit shared Swift packages

**Files:**
- Create: `Packages/MarketplaceFoundation/Package.swift`
- Create: `Packages/MarketplaceFoundation/Sources/MarketplaceFoundation/Money.swift`
- Create: `Packages/MarketplaceFoundation/Sources/MarketplaceFoundation/GeoPoint.swift`
- Create: `Packages/MarketplaceFoundation/Sources/MarketplaceFoundation/IdempotencyKey.swift`
- Create: `Packages/MarketplaceFoundation/Tests/MarketplaceFoundationTests/MoneyTests.swift`
- Create: `Packages/MarketplaceInfrastructure/Package.swift`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/BackendConfiguration.swift`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/FunctionClient.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/BackendConfigurationTests.swift`
- Create: `Packages/SavariDomain/Package.swift`
- Create: `Packages/DastakDomain/Package.swift`

**Interfaces:**
- Consumes: the workspace from Task 1.
- Produces: `Money`, `GeoPoint`, `IdempotencyKey`, `BackendConfiguration`, and `FunctionClient`; product packages may depend on the first two packages but never on each other.

- [ ] **Step 1: Write foundation package tests before the types**

Create `MoneyTests.swift` with these tests:

```swift
import XCTest
@testable import MarketplaceFoundation

final class MoneyTests: XCTestCase {
    func testRupeePaiseRoundTripPreservesIntegerAmount() {
        XCTAssertEqual(Money(paise: 12_345).rupees, 123.45)
        XCTAssertEqual(Money(rupees: 123.45).paise, 12_345)
    }

    func testIdempotencyKeyRejectsEmptyValue() {
        XCTAssertNil(IdempotencyKey(rawValue: ""))
        XCTAssertNotNil(IdempotencyKey(rawValue: UUID().uuidString))
    }
}
```

- [ ] **Step 2: Run the failing package test**

Run:

```bash
swift test --package-path Packages/MarketplaceFoundation
```

Expected: FAIL because `MarketplaceFoundation` and its types do not exist yet.

- [ ] **Step 3: Implement the stable primitive types**

Create the package manifest with iOS 17 and this public API:

```swift
public struct Money: Codable, Equatable, Hashable, Sendable {
    public let paise: Int
    public init(paise: Int) { self.paise = paise }
    public init(rupees: Decimal) {
        self.paise = NSDecimalNumber(decimal: rupees * 100).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: true,
                raiseOnUnderflow: true,
                raiseOnDivideByZero: true
            )
        ).intValue
    }
    public var rupees: Decimal { Decimal(paise) / 100 }
}

public struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        precondition((-90...90).contains(latitude))
        precondition((-180...180).contains(longitude))
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct IdempotencyKey: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.rawValue = rawValue
    }
}
```

Keep product states, rates, orders, rides, and account roles out of this package.

- [ ] **Step 4: Define the generic function boundary without product payloads**

Create `BackendConfiguration` and `FunctionClient` with this contract:

```swift
public struct BackendConfiguration: Equatable, Sendable {
    public let product: String
    public let supabaseURL: URL
    public let publishableKey: String
}

public protocol FunctionClient: Sendable {
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response
}
```

The concrete Supabase implementation must attach `X-Idempotency-Key` and decode an API error payload into `FunctionClientError`; it must not expose a generic table client.

- [ ] **Step 5: Create isolated product package manifests**

Make `SavariDomain` depend on `../MarketplaceFoundation` only. Make `DastakDomain` depend on `../MarketplaceFoundation` only. Do not introduce a package dependency in either direction. Each manifest must declare:

```swift
platforms: [.iOS(.v17)]
```

- [ ] **Step 6: Verify package isolation and commit**

Run:

```bash
swift test --package-path Packages/MarketplaceFoundation
swift test --package-path Packages/MarketplaceInfrastructure
swift package --package-path Packages/SavariDomain describe
swift package --package-path Packages/DastakDomain describe
```

Expected: both test commands pass and neither product package lists the other as a dependency.

```bash
git add Packages
git commit -m "feat: add marketplace foundation packages"
```

### Task 3: Add Apple/Google sign-in, mandatory phone completion, and bootstrap-only owner provisioning

**Files:**
- Modify: `Packages/MarketplaceInfrastructure/Package.swift`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/AuthenticationClient.swift`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/AccountBootstrapClient.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/AuthenticationClientTests.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/AuthenticationTestDoubles.swift`
- Create: `Apps/Savari/Sources/Savari/Auth/SavariAuthenticationCoordinator.swift`
- Create: `Apps/Dastak/Sources/Dastak/Auth/DastakAuthenticationCoordinator.swift`
- Create: `Apps/Savari/Tests/SavariTests/AuthenticationCoordinatorTests.swift`
- Create: `Apps/Dastak/Tests/DastakTests/AuthenticationCoordinatorTests.swift`
- Create: `Apps/Savari/Supporting/Info.plist`
- Create: `Apps/Dastak/Supporting/Info.plist`
- Create: `Apps/Savari/Supporting/SignInWithApple.entitlements`
- Create: `Apps/Dastak/Supporting/SignInWithApple.entitlements`
- Modify: `Apps/Savari/Savari.xcodeproj/project.pbxproj`
- Modify: `Apps/Dastak/Dastak.xcodeproj/project.pbxproj`
- Create: `Backends/Savari/scripts/grant-initial-owner.sql`
- Create: `Backends/Dastak/scripts/grant-initial-owner.sql`

**Interfaces:**
- Consumes: Apple identity token or Google ID token, the product-specific Supabase configuration, and a required E.164 phone number after successful provider sign-in.
- Produces: one session route: `signedOut`, `needsProfile`, or `active`; only a database owner can provision the one owner membership.

**Execution dependency:** This task creates and unit-tests the client boundary with fakes. Do not run a provider integration or the owner SQL until Task 4 has created `bootstrap-account`, `private.account_memberships`, and `audit.events`. The fresh bundle identifiers require new Google OAuth registrations; never copy an OAuth client ID or reversed URL scheme from the archived prototype.

- [ ] **Step 1: Write failing session-route and bootstrap tests**

Create the following test in each product target:

```swift
func testNewProviderSessionMustCompletePhoneBeforeActiveRoute() async throws {
    let gateway = FakeAuthenticationClient(restoredRoute: .needsProfile)
    let coordinator = AuthenticationCoordinator(client: gateway)

    await coordinator.restore()

    XCTAssertEqual(coordinator.route, .needsProfile)
}

func testExistingBootstrappedAccountRestoresActiveRoute() async throws {
    let gateway = FakeAuthenticationClient(restoredRoute: .active)
    let coordinator = AuthenticationCoordinator(client: gateway)

    await coordinator.restore()

    XCTAssertEqual(coordinator.route, .active)
}
```

Create `AuthenticationTestDoubles.swift` with an actor conforming to the protocol so the test has no hidden dependency:

```swift
actor FakeAuthenticationClient: AuthenticationClient {
    let restoredRoute: AccountRoute
    init(restoredRoute: AccountRoute) { self.restoredRoute = restoredRoute }
    func signInWithApple(identityToken: String, nonce: String) async throws {}
    func signInWithGoogle(idToken: String) async throws {}
    func restoreAccount() async throws -> AccountRoute { restoredRoute }
    func bootstrapAccount(displayName: String, phoneNumber: String, key: IdempotencyKey) async throws {}
    func signOut() async throws {}
}
```

- [ ] **Step 2: Run the failing authentication tests**

```bash
swift test --package-path Packages/MarketplaceInfrastructure
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 17e'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 17e'
```

Expected: FAIL because the authentication client and coordinators do not exist.

- [ ] **Step 3: Implement the narrow authenticated session contract**

Create this public package interface:

```swift
public enum AccountRoute: Equatable, Sendable {
    case signedOut
    case needsProfile
    case active
}

public protocol AuthenticationClient: Sendable {
    func signInWithApple(identityToken: String, nonce: String) async throws
    func signInWithGoogle(idToken: String) async throws
    func restoreAccount() async throws -> AccountRoute
    func bootstrapAccount(displayName: String, phoneNumber: String, key: IdempotencyKey) async throws
    func signOut() async throws
}
```

Add the Supabase Swift dependency to `MarketplaceInfrastructure` and keep its `SupabaseClient` private inside a concrete `SupabaseAuthenticationClient`. The concrete product client sends Apple/Google tokens to that product's Supabase Auth provider, uses only a fixed self-account lookup to determine whether a profile exists, then calls the typed `bootstrap-account` function when it does not. It must never expose a generic Supabase or table client. A user cannot navigate to driver, partner, merchant, customer, or owner functionality until the required phone profile returns from the server. The UI is a functional sign-in/profile completion shell only; visual design remains deferred.

- [ ] **Step 4: Configure every app target for both providers**

Add Sign in with Apple capability to all five app targets. Add the local `MarketplaceInfrastructure` package to both app projects and compile the two customer coordinators against it. Use the product `Supporting/Info.plist` files to declare the Google URL scheme as `$(GOOGLE_REVERSED_CLIENT_ID)` for every app target. Set `GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.not-configured` as the only tracked default so the shell builds but cannot start a real Google sign-in. The actual reversed client ID belongs only in an ignored product-specific `Secrets.xcconfig` after new OAuth clients are registered for the fresh bundle identifiers. The runtime configuration must fail closed when the placeholder remains. The Savari and Dastak customer targets use their respective product configuration; the three operational targets use the appropriate product configuration but the same `AuthenticationClient` contract.

Do not make phone number a credential, recovery factor, or payment proof. Mark it `unverified` until a future budgeted OTP project is approved.

- [ ] **Step 5: Provision the initial owner without a client elevation path**

Create this parameterized SQL in each backend script:

```sql
begin;

insert into private.account_memberships (account_id, role, approved_at)
values (:'owner_id'::uuid, 'owner', now())
on conflict (account_id, role) do update set approved_at = excluded.approved_at;

insert into audit.events (actor_id, action, entity_type, entity_id, reason, after_state)
values (
  :'owner_id'::uuid,
  'bootstrap_owner_granted',
  'account_membership',
  :'owner_id'::uuid,
  'initial product owner provisioned by database administrator',
  jsonb_build_object('role', 'owner')
);

commit;
```

Run it only through an owner database connection after Task 4 has migrated the corresponding non-production project and the intended owner has created an account:

```bash
psql "$SAVARI_NONPROD_DATABASE_URL" -v owner_id="$SAVARI_OWNER_AUTH_USER_ID" -f Backends/Savari/scripts/grant-initial-owner.sql
```

There is no Edge Function, app route, RPC, or table policy that can grant `owner`.

- [ ] **Step 6: Verify sign-in routes and bootstrap ownership then commit**

```bash
swift test --package-path Packages/MarketplaceInfrastructure
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 17e'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 17e'
git add Apps Packages Backends
git commit -m "feat: add marketplace authentication bootstrap"
```

Expected: client unit tests prove the required route behavior; the provider and owner database integration checks run in Task 4 after its backend migration exists.

### Task 4: Bootstrap two fresh Supabase backend repositories and identity contracts

**Files:**
- Create: `Backends/Savari/supabase/config.toml`
- Create: `Backends/Savari/supabase/migrations/20260715090000_bootstrap_identity.sql`
- Create: `Backends/Savari/supabase/functions/bootstrap-account/index.ts`
- Create: `Backends/Savari/supabase/functions/_shared/http.ts`
- Create: `Backends/Savari/supabase/functions/_shared/auth.ts`
- Create: `Backends/Savari/supabase/functions/deno.json`
- Create: `Backends/Dastak/supabase/config.toml`
- Create: `Backends/Dastak/supabase/migrations/20260715090000_bootstrap_identity.sql`
- Create: `Backends/Dastak/supabase/functions/bootstrap-account/index.ts`
- Create: `Backends/Dastak/supabase/functions/_shared/http.ts`
- Create: `Backends/Dastak/supabase/functions/_shared/auth.ts`
- Create: `Backends/Dastak/supabase/functions/deno.json`
- Create: `Backends/Savari/supabase/tests/database/001_identity.pgtap.sql`
- Create: `Backends/Dastak/supabase/tests/database/001_identity.pgtap.sql`

**Interfaces:**
- Consumes: authenticated Apple or Google Supabase session JWT.
- Produces: `POST /functions/v1/bootstrap-account` accepting `{ displayName, phoneNumber }` and returning `{ accountId, phoneState: "unverified" }`.

- [ ] **Step 1: Create the failing pgTAP identity tests**

Use the same test body in both product directories, with the schema-specific assertions below:

```sql
begin;
select plan(5);

select has_table('public', 'accounts');
select has_table('private', 'account_memberships');
select has_column('public', 'accounts', 'phone_number');
select has_column('public', 'accounts', 'phone_verification_state');
select has_table('private', 'request_deduplication');

select * from finish();
rollback;
```

- [ ] **Step 2: Run the database tests before the migration exists**

From each product backend after `supabase start` succeeds, run:

```bash
supabase db test --local --file supabase/tests/database/001_identity.pgtap.sql
```

Expected: FAIL because the `accounts` and `account_memberships` relations do not yet exist.

- [ ] **Step 3: Create the canonical identity migration in both isolated projects**

The two migrations must use this structure, with no cross-project foreign key:

```sql
create schema if not exists private;
create schema if not exists audit;

create type public.phone_verification_state as enum ('unverified', 'verified');
create type private.membership_role as enum (
  'customer', 'savari_driver', 'dastak_partner', 'merchant', 'pharmacy', 'owner'
);

create table public.accounts (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  phone_number text not null check (phone_number ~ '^\\+[1-9][0-9]{7,14}$'),
  phone_verification_state public.phone_verification_state not null default 'unverified',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table private.account_memberships (
  account_id uuid not null references public.accounts(id) on delete cascade,
  role private.membership_role not null,
  approved_at timestamptz,
  suspended_until timestamptz,
  created_at timestamptz not null default now(),
  primary key (account_id, role)
);

create table private.request_deduplication (
  account_id uuid not null references public.accounts(id) on delete cascade,
  function_name text not null,
  idempotency_key text not null,
  request_digest text not null,
  response_body jsonb not null,
  response_status integer not null,
  created_at timestamptz not null default now(),
  primary key (account_id, function_name, idempotency_key)
);

alter table public.accounts enable row level security;
revoke all on table private.account_memberships from anon, authenticated;
revoke all on table private.request_deduplication from anon, authenticated;
grant select on public.accounts to authenticated;
revoke insert, update, delete on public.accounts from anon, authenticated;

create policy accounts_select_self on public.accounts
for select to authenticated using (id = auth.uid());
```

The `bootstrap-account` function uses the authenticated JWT to insert the account and `customer` membership through a server-only client. It rejects a missing name with `validation_failed`, an invalid E.164 number with `invalid_phone_number`, and a second bootstrap request with `account_already_exists`.

- [ ] **Step 4: Implement typed Edge Function support and account bootstrap**

Use these shared response types in each `functions/_shared/http.ts`:

```ts
export type ApiErrorCode =
  | 'authentication_required'
  | 'validation_failed'
  | 'invalid_phone_number'
  | 'account_already_exists'
  | 'idempotency_conflict'
  | 'internal_error';

export type ApiError = { error: { code: ApiErrorCode; message: string } };
export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
```

`bootstrap-account/index.ts` must require `X-Idempotency-Key`, retrieve `user.id` from the bearer token, and insert a row in `private.request_deduplication` before the account transaction. A repeat with the same key and same request returns the stored response; a different request body returns `409 idempotency_conflict`.

- [ ] **Step 5: Configure provider and secret boundaries manually in both non-production dashboards**

Enable Apple and Google providers in each non-production Supabase project. Configure distinct redirect URLs and OAuth client IDs for Savari and Dastak targets. After each new Google OAuth registration, place its reversed client ID only in the matching ignored `Secrets.xcconfig`; do not reuse the archived prototype value. Set only server secrets with:

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" --project-ref "$SUPABASE_NONPROD_PROJECT_REF"
```

Do not store the service role key in an `.xcconfig`, git-tracked file, iOS target, or test fixture.

- [ ] **Step 6: Verify identity bootstrap and commit**

Run for both backends:

```bash
supabase db reset --local
supabase db test --local --file supabase/tests/database/001_identity.pgtap.sql
deno test --allow-env supabase/functions/tests/
```

Expected: all migration and unit tests pass. Add an integration test that sends a duplicate `bootstrap-account` request and asserts the second response returns the original account ID. Then run the Savari and Dastak `AuthenticationCoordinatorTests` against a test account to verify a provider session routes to `needsProfile`, bootstrap creates the account, and a restored session routes to `active`.

```bash
git add Backends
git commit -m "feat: bootstrap isolated marketplace backends"
```

### Task 5: Establish read-only client data, audit, evidence storage, and service zones

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715091500_security_audit_zones.sql`
- Create: `Backends/Dastak/supabase/migrations/20260715091500_security_audit_zones.sql`
- Create: `Backends/Savari/supabase/tests/database/002_security_audit_zones.pgtap.sql`
- Create: `Backends/Dastak/supabase/tests/database/002_security_audit_zones.pgtap.sql`
- Create: `Backends/Savari/supabase/functions/issue-evidence-url/index.ts`
- Create: `Backends/Dastak/supabase/functions/issue-evidence-url/index.ts`
- Create: `scripts/test-backend-security.sh`

**Interfaces:**
- Consumes: account membership and an authenticated actor.
- Produces: owner-managed `service_zones`, append-only `audit.events`, private evidence URL issuance, and no client mutation grants on business tables.

- [ ] **Step 1: Write RLS and audit tests before adding policies**

In each `002_security_audit_zones.pgtap.sql`, assert the security baseline:

```sql
begin;
select plan(7);

select policies_are('public', 'accounts', array['accounts_select_self']);
select table_privs_are('authenticated', 'public', 'accounts', array['SELECT']);
select has_table('audit', 'events');
select col_is_pk('audit', 'events', 'id');
select has_table('private', 'safety_cases');
select has_table('public', 'service_zones');
select has_column('public', 'service_zones', 'boundary');

select * from finish();
rollback;
```

- [ ] **Step 2: Run the failing security tests**

```bash
supabase db test --local --file supabase/tests/database/002_security_audit_zones.pgtap.sql
```

Expected: FAIL because audit tables, zones, and restrictive grants have not been created.

- [ ] **Step 3: Create the audit and zone schema with immutable writes**

Create this shared baseline in both migrations, changing only product-specific evidence bucket names:

```sql
create extension if not exists postgis with schema extensions;

create table audit.events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.accounts(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  reason text,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default now()
);

create table private.safety_cases (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null,
  reporter_account_id uuid not null references public.accounts(id),
  incident_type text not null,
  report_text text not null check (char_length(report_text) between 1 and 1000),
  route_evidence_reference text,
  status text not null default 'open' check (status in ('open', 'under_review', 'resolved')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.service_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  boundary extensions.geometry(Polygon, 4326) not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table audit.events enable row level security;
alter table private.safety_cases enable row level security;
alter table public.service_zones enable row level security;
revoke all on audit.events from anon, authenticated;
revoke all on private.safety_cases from anon, authenticated;
revoke insert, update, delete on public.service_zones from anon, authenticated;
grant select on public.service_zones to authenticated;
```

Expose owner changes only through Edge Functions that write the before/after JSON in the same database transaction.

- [ ] **Step 4: Define private storage buckets and URL issuance**

Create private buckets `savari-evidence` and `dastak-evidence`, plus a public-read `dastak-catalogue` bucket only in Dastak. `issue-evidence-url` accepts `{ bucket, objectPath, operation }`, verifies actor ownership or owner membership, and returns a signed URL with a 300-second expiry. Reject every path not matching one of these forms:

```text
savari-driver/<auth-user-id>/<filename>
dastak-partner/<auth-user-id>/<filename>
merchant/<merchant-id>/<filename>
pharmacy/<pharmacy-id>/<filename>
prescription/<order-id>/<filename>
receipt/<delivery-id>/<filename>
```

No client receives a bucket-wide list policy, public sensitive bucket, or a signed URL longer than five minutes.

- [ ] **Step 5: Create a repeatable no-direct-mutation security check**

Implement `scripts/test-backend-security.sh` to execute the pgTAP test files and then query grants:

```bash
#!/usr/bin/env bash
set -euo pipefail

backend="$1"
cd "Backends/$backend"
supabase db test --local --file supabase/tests/database/001_identity.pgtap.sql
supabase db test --local --file supabase/tests/database/002_security_audit_zones.pgtap.sql
supabase db query "select table_name, privilege_type from information_schema.role_table_grants where grantee = 'authenticated' and privilege_type in ('INSERT','UPDATE','DELETE') order by table_name;"
```

Expected final query: only explicitly approved future client-owned upload metadata rows, never accounts, roles, zones, audits, jobs, payments, or payouts.

- [ ] **Step 6: Verify foundation security and commit**

Run:

```bash
scripts/test-backend-security.sh Savari
scripts/test-backend-security.sh Dastak
git diff --check
```

Expected: pgTAP passes in both backends and the grants review has no unauthorized mutation privilege.

```bash
git add Backends scripts
git commit -m "feat: secure marketplace foundation"
```

### Task 6: Add project-level automation and a reproducible foundation gate

**Files:**
- Create: `.github/workflows/foundation.yml`
- Create: `scripts/test-foundation.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: both local Supabase projects, Deno, Swift toolchain, and Xcode.
- Produces: one command that rejects a workspace, package, migration, or function regression before higher-level product work begins.

- [ ] **Step 1: Write the foundation gate script**

Create `scripts/test-foundation.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

swift test --package-path Packages/MarketplaceFoundation
swift test --package-path Packages/MarketplaceInfrastructure
scripts/test-backend-security.sh Savari
scripts/test-backend-security.sh Dastak
xcodebuild -workspace SavariDastak.xcworkspace -scheme Savari -sdk iphonesimulator -configuration Debug build
xcodebuild -workspace SavariDastak.xcworkspace -scheme Dastak -sdk iphonesimulator -configuration Debug build
```

- [ ] **Step 2: Run the script before CI configuration**

```bash
scripts/test-foundation.sh
```

Expected: FAIL only if a prerequisite is absent; install the missing tool or start local Supabase before proceeding. Do not weaken the script to mask a failing prerequisite.

- [ ] **Step 3: Add CI jobs that mirror the local gate**

Create `.github/workflows/foundation.yml` with four required jobs: `swift-packages`, `savari-backend`, `dastak-backend`, and `ios-build`. Pin the Xcode image and use `supabase/setup-cli@v1` plus `denoland/setup-deno@v2`. Each backend job starts only its own backend directory and runs its own migrations and Deno tests.

- [ ] **Step 4: Document exact local commands and project selection**

Add this block to `README.md`:

```bash
# Savari backend
cd Backends/Savari
supabase start

# Dastak backend
cd Backends/Dastak
supabase start

# Whole foundation gate from repository root
scripts/test-foundation.sh
```

State that `supabase link` must be executed independently inside each backend after the owner creates the corresponding non-production project.

- [ ] **Step 5: Verify and commit the foundation gate**

Run:

```bash
scripts/test-foundation.sh
git diff --check
```

Expected: every local unit, security, function, and Debug workspace build check passes.

```bash
git add .github README.md scripts
git commit -m "ci: add marketplace foundation gate"
```

## Foundation Completion Gate

Do not start the Savari or Dastak core plans until all of the following are true:

- The old prototype is excluded from the launch workspace and no new changes target it.
- Savari and Dastak local backends each reset, migrate, and pass their own pgTAP and Deno tests.
- The two product package dependency graphs do not import one another.
- Apple and Google sign-in are configured in non-production for each product.
- Accounts can be bootstrapped with a required but explicitly unverified phone number.
- The clean iOS shells route new provider sign-ins to phone completion and only then to an active product store.
- The single initial owner role was provisioned through the audited administrator-only script, not a client route.
- Every sensitive table has RLS and every protected mutation route is server-only.
