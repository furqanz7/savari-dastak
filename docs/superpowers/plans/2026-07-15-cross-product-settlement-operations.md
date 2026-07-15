# Cross-Product Settlement and Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Savari and Dastak only through explicit account consent, a narrow signed ride-linked collection bridge, one private cross-product settlement coordinator, Razorpay Route server authority, and separate owner-only iOS operations apps.

**Architecture:** Savari and Dastak continue to own their product data and payment records. The Savari project contains a private Settlement Coordinator that holds payout identity and release state only. Dastak sends minimal, HMAC-signed, idempotent events to a dedicated Savari bridge function. iOS apps never hold a service key, HMAC secret, Razorpay secret, transfer endpoint, or admin authorization bypass.

**Tech Stack:** Supabase Edge Functions/Postgres/Vault/pg_cron/pg_net, Web Crypto HMAC, Razorpay Standard iOS SDK and Route API, Swift 5/iOS 17, XCTest, Deno, pgTAP.

## Global Constraints

- Complete the Savari and Dastak core plans before this plan.
- No client-side cross-project table write, no cross-project service role key in any app, and no phone/email auto-linking.
- Account linking requires explicit consent in both authenticated product sessions and uses a single-use, 10-minute nonce.
- Ride-linked collection is available only from Dastak entered through Savari navigation, only to the passenger with an active matched ride, and only for a paid and ready merchant order.
- Before passenger boarding, merchant pickup must add no more than five minutes to the predicted passenger pickup ETA. After boarding, only the passenger's own order can add a stop. Do not carry unrelated delivery work with a passenger onboard.
- A completed in-app earning is pending. The next completed eligible job releases prior pending in-app earnings. Any still-pending earning auto-releases after 24 hours.
- Cash and direct UPI Savari rides create no platform commission. Savari in-app rides use a configurable default 10% commission. Dastak product economics are configured snapshots.
- Razorpay webhook verification, not a client callback, is the final authority for payment and transfer success.
- Owner apps are separate iOS targets. The one owner account in each product must have a server membership and a sign-in no older than 15 minutes for sensitive actions.
- Paan Corner is a high-risk Dastak capability governed by the Dastak core's adult attestation, exclusion-zone, merchant/product approval, and partner visual handoff rules. Owner operations may approve or suspend individual restricted merchants/products only with evidence and an immutable audit record; they must not provide a generic category activation switch or bypass the release gate.

---

### Task 1: Implement explicit cross-product account linking and signed bridge primitives

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715120000_cross_product_linking.sql`
- Create: `Backends/Dastak/supabase/migrations/20260715120000_cross_product_linking.sql`
- Create: `Backends/Savari/supabase/functions/consume-dastak-link-nonce/index.ts`
- Create: `Backends/Savari/supabase/functions/bridge-reserve-cross-product-work/index.ts`
- Create: `Backends/Savari/supabase/functions/bridge-release-cross-product-work/index.ts`
- Create: `Backends/Dastak/supabase/functions/create-account-link-nonce/index.ts`
- Create: `Backends/Dastak/supabase/functions/consume-account-link-result/index.ts`
- Create: `Backends/Dastak/supabase/functions/bridge-sync-savari-driver-eligibility/index.ts`
- Create: `Backends/Savari/supabase/functions/_shared/bridge.ts`
- Create: `Backends/Dastak/supabase/functions/_shared/bridge.ts`
- Create: `Backends/Savari/supabase/functions/tests/bridge/link_nonce.test.ts`
- Create: `Backends/Dastak/supabase/functions/tests/bridge/link_nonce.test.ts`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/LinkedAccountClient.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/LinkedAccountClientTests.swift`
- Create: `Apps/Savari/Savari/Driver/DastakWorkClient.swift`
- Create: `Apps/Savari/SavariTests/DastakWorkClientTests.swift`

**Interfaces:**
- Consumes: independent authenticated Savari and Dastak sessions belonging to a consenting user.
- Produces: a one-to-one, server-held link between product account IDs and an HMAC signing interface used only by Edge Functions.

- [ ] **Step 1: Write failing nonce and signature tests**

Create the following Deno test in both backend function test roots:

```ts
Deno.test('link nonce is single-use and expires after ten minutes', async () => {
  const nonce = await issueLinkNonce({ accountID: 'dastak-account', now: new Date('2026-07-15T10:00:00Z') });
  assertEquals(await consumeLinkNonce(nonce.value, new Date('2026-07-15T10:09:59Z')), 'dastak-account');
  await assertRejects(() => consumeLinkNonce(nonce.value, new Date('2026-07-15T10:09:59Z')));
});
```

Add a bridge test that modifies one JSON byte after signing and expects `invalid_bridge_signature`.

Add a reservation test where a linked Savari driver with an `in_progress` ride requests Dastak standalone work and receives `active_ride_exists`; repeat a successful reservation with the same delivery event ID and assert it remains one reservation.

- [ ] **Step 2: Run the failing bridge tests**

```bash
cd Backends/Savari
deno test --allow-env supabase/functions/tests/bridge/link_nonce.test.ts
cd ../../Dastak
deno test --allow-env supabase/functions/tests/bridge/link_nonce.test.ts
```

Expected: FAIL because link nonce storage and HMAC helpers do not exist.

- [ ] **Step 3: Create explicit link records without identity auto-matching**

Create these private tables:

```sql
create table private.account_link_nonces (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id) on delete cascade,
  nonce_digest text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table private.cross_product_account_links (
  id uuid primary key default gen_random_uuid(),
  savari_account_id uuid not null unique,
  dastak_account_id uuid not null unique,
  linked_at timestamptz not null default now(),
  revoked_at timestamptz,
  link_version integer not null default 1
);
```

The Dastak table stores the nonce and Dastak account ID; the Savari table stores final link records. Never use email, phone number, display name, provider subject, or Apple relay address to find a matching account.

- [ ] **Step 4: Implement signed bridge calls with replay protection**

Both `_shared/bridge.ts` files must create/verify:

```ts
type SignedBridgeRequest<T> = {
  eventID: string;
  sentAt: string;
  body: T;
  signature: string;
};
```

Sign the UTF-8 bytes of `${eventID}.${sentAt}.${canonicalJson(body)}` using `HMAC-SHA-256` and the `SAVARI_DASTAK_BRIDGE_SECRET` held only in Edge Function secrets. Reject timestamps outside five minutes, duplicate event IDs, malformed UUIDs, invalid signatures, and a body hash that differs from the stored event hash. Persist accepted event IDs in `private.bridge_inbox` before applying the side effect.

- [ ] **Step 5: Implement mutual consent link flow**

`create-account-link-nonce` requires a Dastak JWT and returns a raw nonce once. Savari's `consume-dastak-link-nonce` requires a Savari JWT, calls the Dastak private bridge endpoint, consumes the nonce, creates the link atomically, and writes audit events in both products. `consume-account-link-result` lets Dastak update its local link read projection after the signed response.

`LinkedAccountClient` must make this a two-screen authentication flow, not a local boolean. It exposes:

```swift
public protocol LinkedAccountClient: Sendable {
    func createDastakLinkNonce() async throws -> String
    func linkDastakAccount(nonce: String, key: IdempotencyKey) async throws
    func linkedStatus() async throws -> Bool
}
```

- [ ] **Step 6: Add linked-driver eligibility and a global standalone-work reservation**

An approved Savari driver becomes eligible for Dastak work only after all three conditions are true: the account link is active, `bridge-sync-savari-driver-eligibility` verifies current Savari driver approval and active vehicle evidence, and the Dastak owner approves the linked Dastak delivery partner profile. It is not an automatic role conversion.

Before Dastak assigns a standalone delivery to a linked Savari driver, `private.assign_next_delivery` calls signed `bridge-reserve-cross-product-work`. Savari creates `private.cross_product_work_reservations` only when the driver has no active Savari ride and no existing standalone Dastak reservation. The bridge rejects `active_ride_exists` and `standalone_work_already_reserved`. On terminal delivery state, Dastak sends `bridge-release-cross-product-work` with the immutable delivery event ID. The ride-linked collection attachment from Task 2 is the only exception because it is stored as part of the existing ride, not as a second standalone reservation.

The Savari Driver mode uses `DastakWorkClient` backed by a Dastak FunctionClient only after explicit account linking and only for partner availability/job snapshots. It cannot browse the Dastak customer catalogue or make direct Dastak table calls. `DastakWorkClientTests` must assert an active Savari ride prevents setting Dastak standalone availability and a terminal Dastak job releases availability only after the signed reservation release succeeds.

- [ ] **Step 7: Verify both backend paths and commit**

```bash
cd Backends/Savari
supabase db reset --local
deno test --allow-env supabase/functions/tests/bridge
cd ../Dastak
supabase db reset --local
deno test --allow-env supabase/functions/tests/bridge
git add Backends Packages/MarketplaceInfrastructure
git commit -m "feat: add explicit Savari Dastak account links"
```

Expected: a user must prove control of both accounts, every replay/tamper attempt is rejected, and an approved linked driver cannot receive a standalone Dastak job while holding an active Savari ride.

### Task 2: Implement ride-linked merchant collection as a narrow bridge contract

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715121000_ride_linked_collection.sql`
- Create: `Backends/Dastak/supabase/migrations/20260715121000_ride_linked_collection.sql`
- Create: `Backends/Savari/supabase/functions/bridge-ride-collection-context/index.ts`
- Create: `Backends/Savari/supabase/functions/bridge-attach-collection-stop/index.ts`
- Create: `Backends/Dastak/supabase/functions/attach-order-to-savari-ride/index.ts`
- Create: `Backends/Dastak/supabase/functions/tests/bridge/ride_linked_collection.test.ts`
- Create: `Backends/Savari/supabase/functions/tests/bridge/ride_linked_collection.test.ts`
- Create: `Packages/DastakDomain/Sources/DastakDomain/RideLinkedCollection.swift`
- Create: `Packages/DastakDomain/Tests/DastakDomainTests/RideLinkedCollectionTests.swift`

**Interfaces:**
- Consumes: a linked account, a paid and ready Dastak merchant order, and an active Savari ride owned by the linked passenger.
- Produces: one composite collection attachment with a maximum pickup-delay decision, immutable bridge events, and separate Savari/Dastak money legs.

- [ ] **Step 1: Write the delayed-pickup and ownership failures**

Create tests that assert all four rules:

```ts
assertEquals(validateCollection({ delaySeconds: 301, rideStatus: 'assigned' }).error, 'pickup_delay_exceeded');
assertEquals(validateCollection({ delaySeconds: 300, rideStatus: 'assigned' }).ok, true);
assertEquals(validateCollection({ samePassenger: false, rideStatus: 'in_progress' }).error, 'ride_owner_mismatch');
assertEquals(validateCollection({ orderStatus: 'merchant_accepted', rideStatus: 'assigned' }).error, 'order_not_ready');
```

- [ ] **Step 2: Run the failing bridge collection tests**

```bash
cd Backends/Savari
deno test --allow-env supabase/functions/tests/bridge/ride_linked_collection.test.ts
cd ../Dastak
deno test --allow-env supabase/functions/tests/bridge/ride_linked_collection.test.ts
```

Expected: FAIL because collection context and attachment state do not exist.

- [ ] **Step 3: Store the composite attachment with independent financial legs**

In Savari, add `private.ride_collection_attachments` containing `ride_id`, external `dastak_order_id`, external `dastak_delivery_id`, `collection_state`, pickup detour seconds, and immutable bridge event ID. In Dastak, add `private.savari_ride_collection_links` containing `merchant_order_id`, external Savari ride ID, external Savari driver account ID, and a bridge status.

Add unique constraints on both ride/order IDs so one order cannot attach to two rides and one ride cannot contain duplicate attachments. Do not join, copy, or merge customer payment records between the product projects.

- [ ] **Step 4: Implement authoritative eligibility and stop attachment**

`bridge-ride-collection-context` returns only a signed minimal context: `{ rideID, linkedDastakAccountID, passengerIDMatches, status, driverID, pickup, currentLocation, destination, boarded }`. Dastak checks that the merchant order is `ready` and paid. It calls Apple Maps Server API to compare direct driver-to-pickup ETA against driver-to-merchant-to-pickup ETA before boarding; it rejects a detour greater than 300 seconds.

After boarding, only an order whose Dastak customer maps to the same Savari passenger may attach. The call adds the merchant stop to Savari's private route plan through `bridge-attach-collection-stop`; it rejects a second unrelated delivery and preserves the passenger's ride as the only active composite assignment.

- [ ] **Step 5: Add domain and integration assertions**

`RideLinkedCollection.swift` must make an unavailable state explicit:

```swift
public enum RideLinkedCollectionEligibility: Equatable, Sendable {
    case available(maximumPickupDelaySeconds: Int)
    case unavailable(reason: RideLinkedCollectionUnavailableReason)
}
```

The app must not show the option when there is no active linked ride, even if the user has an unlinked Dastak account. Test that a status change from `ready` back to invalid state before attachment rejects the request by version check.

- [ ] **Step 6: Verify and commit the collection bridge**

```bash
cd Backends/Savari && deno test --allow-env supabase/functions/tests/bridge
cd ../Dastak && deno test --allow-env supabase/functions/tests/bridge
swift test --package-path ../../Packages/DastakDomain
git add Backends Packages/DastakDomain
git commit -m "feat: add ride linked Dastak collection"
```

Expected: only the matched passenger's ready order may become a composite pickup; all fare and payment records remain independent.

### Task 3: Build the private Settlement Coordinator and global rolling holdback

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715122000_settlement_coordinator.sql`
- Create: `Backends/Savari/supabase/functions/bridge-record-dastak-completion/index.ts`
- Create: `Backends/Savari/supabase/functions/record-savari-completion/index.ts`
- Create: `Backends/Savari/supabase/functions/release-pending-earnings/index.ts`
- Create: `Backends/Savari/supabase/functions/request-withdrawal/index.ts`
- Create: `Backends/Dastak/supabase/functions/request-dastak-withdrawal/index.ts`
- Create: `Backends/Savari/supabase/functions/tests/settlement/rolling_holdback.test.ts`
- Create: `Backends/Savari/supabase/tests/database/030_settlement.pgtap.sql`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/SettlementClient.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/SettlementClientTests.swift`

**Interfaces:**
- Consumes: a signed, immutable completed-job event from Savari or Dastak and a payout profile reference.
- Produces: append-only earning ledger entries with `pending`, `withdrawable`, `created`, `processing`, `paid`, `failed`, `reversed`, or `adjusted` state.

- [ ] **Step 1: Write the rolling-holdback tests first**

Create Deno tests for this exact sequence:

```ts
Deno.test('second completed eligible job releases prior in-app earning only', () => {
  const first = applyCompletion(emptyLedger, { kind: 'savari_in_app', id: 'a', at: 1 });
  assertEquals(first.earnings[0].state, 'pending');

  const second = applyCompletion(first, { kind: 'dastak_cash_equivalent', id: 'b', at: 2 });
  assertEquals(second.earnings.find((entry) => entry.sourceEventID === 'a')?.state, 'withdrawable');
  assertEquals(second.earnings.find((entry) => entry.sourceEventID === 'b')?.state, undefined);
});
```

Add tests for 24-hour automatic release, duplicate bridge event no-op, and a post-payout refund producing `adjusted` rather than mutating the original `paid` row.

- [ ] **Step 2: Run the failing settlement suite**

```bash
cd Backends/Savari
deno test --allow-env supabase/functions/tests/settlement/rolling_holdback.test.ts
supabase db test --local --file supabase/tests/database/030_settlement.pgtap.sql
```

Expected: FAIL because settlement tables and release logic do not exist.

- [ ] **Step 3: Create the private ledger with immutable source references**

Create these tables in `private` schema only:

```sql
create type private.transfer_state as enum (
  'pending', 'withdrawable', 'created', 'processing', 'paid', 'failed', 'reversed', 'adjusted'
);

create table private.settlement_profiles (
  id uuid primary key default gen_random_uuid(),
  savari_account_id uuid unique,
  dastak_partner_id uuid unique,
  razorpay_linked_account_id text unique,
  payout_enabled_at timestamptz,
  created_at timestamptz not null default now()
);

create table private.earning_ledger (
  id uuid primary key default gen_random_uuid(),
  settlement_profile_id uuid not null references private.settlement_profiles(id),
  source_product text not null check (source_product in ('savari', 'dastak')),
  source_event_id uuid not null,
  source_kind text not null,
  gross_paise integer not null,
  platform_fee_paise integer not null,
  net_paise integer not null,
  state private.transfer_state not null,
  eligible_after timestamptz not null,
  created_at timestamptz not null default now(),
  unique (source_product, source_event_id)
);
```

Store every reversal/adjustment as a new row linked to the original ledger row. Revoke all client access to this schema.

- [ ] **Step 4: Implement deterministic release behavior**

`record-savari-completion` receives a server-internal completed-job event. `bridge-record-dastak-completion` verifies the signed Dastak event and stores it in the bridge inbox before any ledger change. Both call one private transaction which:

```text
1. releases all earlier pending in-app earnings for the same settlement profile to withdrawable;
2. adds a new pending ledger entry only if the current completion creates an in-app earning;
3. records a non-ledger eligible completion for cash/direct UPI jobs;
4. sets eligible_after to completion time + 24 hours;
5. writes immutable audit and settlement events.
```

`release-pending-earnings` runs every minute and releases only rows whose `eligible_after <= now()` and state is `pending`. `request-withdrawal` accepts only `withdrawable` rows owned by the authenticated Savari account. `request-dastak-withdrawal` authenticates the Dastak partner then sends a signed, idempotent bridge request to the same Savari settlement profile. A Dastak completion reports the configured courier payout as its net earning whether the worker is a Dastak-only partner or an approved Savari driver; the payout amount is never recalculated from the worker's app mode.

- [ ] **Step 5: Verify settlement correctness and commit**

```bash
cd Backends/Savari
supabase db reset --local
supabase db test --local --file supabase/tests/database/030_settlement.pgtap.sql
deno test --allow-env supabase/functions/tests/settlement
git add Backends/Savari Packages/MarketplaceInfrastructure
git commit -m "feat: add cross product settlement coordinator"
```

Expected: a Dastak-only partner has a settlement profile without a Savari Auth account, duplicate events do nothing, and payout history is never overwritten.

### Task 4: Add Razorpay Route payment and webhook authority

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715123000_razorpay_payments.sql`
- Create: `Backends/Dastak/supabase/migrations/20260715123000_razorpay_payments.sql`
- Create: `Backends/Savari/supabase/functions/create-ride-payment-order/index.ts`
- Create: `Backends/Dastak/supabase/functions/create-dastak-payment-order/index.ts`
- Create: `Backends/Savari/supabase/functions/razorpay-webhook/index.ts`
- Create: `Backends/Dastak/supabase/functions/razorpay-webhook/index.ts`
- Create: `Backends/Savari/supabase/functions/create-route-transfer/index.ts`
- Create: `Backends/Savari/supabase/functions/tests/payments/webhook.test.ts`
- Create: `Backends/Dastak/supabase/functions/tests/payments/webhook.test.ts`
- Create: `Packages/MarketplaceInfrastructure/Sources/MarketplaceInfrastructure/RazorpayCheckoutSession.swift`
- Create: `Packages/MarketplaceInfrastructure/Tests/MarketplaceInfrastructureTests/RazorpayCheckoutSessionTests.swift`

**Interfaces:**
- Consumes: server-authoritative amount, product payment state, Razorpay secret/key/webhook secret in Edge Function secrets, and a raw provider webhook body.
- Produces: client-safe checkout sessions, verified payment records, Route transfer intents, and confirmed settlement events.

- [ ] **Step 1: Write failing webhook signature and deduplication tests**

Create a test that signs a fixture raw webhook body using `RAZORPAY_WEBHOOK_SECRET`, expects first delivery to create a payment event, replays the exact body with the same provider event ID, and expects no second payment or transfer. A modified raw body with the old signature must return `invalid_webhook_signature`.

- [ ] **Step 2: Run the failing payment test suites**

```bash
cd Backends/Savari
deno test --allow-env supabase/functions/tests/payments/webhook.test.ts
cd ../Dastak
deno test --allow-env supabase/functions/tests/payments/webhook.test.ts
```

Expected: FAIL because payment and webhook handlers do not exist.

- [ ] **Step 3: Store payment and provider event data separately from job state**

Create product-local payment records with immutable `provider_order_id`, `provider_payment_id`, amount, currency, payment state, source ride/delivery/order ID, and raw provider event ID. Create a unique `private.provider_webhook_events(provider, event_id)` table. Do not rely on a client callback to mark a record paid.

For Savari, allow `create-ride-payment-order` only when a ride has a server-computed terminal fare and the passenger selects in-app payment. For Dastak, create an order before parcel assignment or merchant acceptance, using server-calculated cart/fee amounts.

- [ ] **Step 4: Implement verified provider calls and client checkout session**

The server creates the Razorpay order and returns only:

```swift
public struct RazorpayCheckoutSession: Codable, Sendable {
    public let orderID: String
    public let keyID: String
    public let amountPaise: Int
    public let currency: String
    public let receipt: String
}
```

The secret key, linked-account ID, webhook secret, and transfer credentials stay in Supabase Edge Function secrets. Integrate the current Razorpay Standard iOS SDK only in customer targets, passing the session fields to checkout. Treat its completion callback as a prompt to refetch the payment snapshot; the webhook changes business state.

- [ ] **Step 5: Implement webhook-to-settlement path and Route transfers**

Verify Razorpay's signature against the unparsed request bytes. Deduplicate provider event ID before applying the transaction. A verified capture moves the product payment to paid and invokes product completion only when its business conditions are met. A verified transfer event moves a ledger row through `created`, `processing`, `paid`, or `failed`.

`create-route-transfer` receives a private withdrawal request, calculates a transfer amount from immutable withdrawable ledger rows, and uses Razorpay Route only after the linked account is owner-approved and payout-enabled. Write an adjustment/reversal event for a later refund or dispute; never set a previous `paid` record back to another state.

- [ ] **Step 6: Run sandbox verification and commit**

Set sandbox values only with project-specific secrets, then run:

```bash
cd Backends/Savari && deno test --allow-env supabase/functions/tests/payments
cd ../Dastak && deno test --allow-env supabase/functions/tests/payments
```

Use Razorpay test-mode payment and webhook fixtures to prove capture, duplicate delivery, failure, refund, transfer, and transfer failure handling. Commit only source/tests; do not commit generated event bodies containing live data or credentials.

```bash
git add Backends Packages/MarketplaceInfrastructure
git commit -m "feat: add verified Razorpay marketplace payments"
```

### Task 5: Implement separate owner operations APIs and iOS app shells

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715124000_savari_owner_operations.sql`
- Create: `Backends/Dastak/supabase/migrations/20260715124000_dastak_owner_operations.sql`
- Create: `Backends/Savari/supabase/functions/_shared/owner.ts`
- Create: `Backends/Dastak/supabase/functions/_shared/owner.ts`
- Create: `Backends/Savari/supabase/functions/admin-approve-driver/index.ts`
- Create: `Backends/Savari/supabase/functions/admin-update-rate-card/index.ts`
- Create: `Backends/Savari/supabase/functions/admin-resolve-ride-refund/index.ts`
- Create: `Backends/Dastak/supabase/functions/admin-approve-partner/index.ts`
- Create: `Backends/Dastak/supabase/functions/admin-approve-merchant/index.ts`
- Create: `Backends/Dastak/supabase/functions/admin-resolve-order-refund/index.ts`
- Create: `Apps/Savari/SavariAdmin/SavariAdminApp.swift`
- Create: `Apps/Savari/SavariAdmin/Operations/SavariAdminClient.swift`
- Create: `Apps/Savari/SavariAdminTests/SavariAdminClientTests.swift`
- Create: `Apps/Dastak/DastakAdmin/DastakAdminApp.swift`
- Create: `Apps/Dastak/DastakAdmin/Operations/DastakAdminClient.swift`
- Create: `Apps/Dastak/DastakAdminTests/DastakAdminClientTests.swift`

**Interfaces:**
- Consumes: owner server membership, a Supabase Auth user whose `last_sign_in_at` is no more than 15 minutes old, a mandatory reason, and an immutable audit log.
- Produces: owner-only approvals, configuration revisions, suspensions, refund decisions, safety cases, and durable operational alerts.

- [ ] **Step 1: Write failing owner authorization tests**

Create Deno tests that assert a normal authenticated customer receives `owner_required`, an owner with a sign-in older than 15 minutes receives `recent_sign_in_required`, and an approved request without a non-empty reason receives `reason_required`.

- [ ] **Step 2: Run the failing owner tests**

```bash
cd Backends/Savari && deno test --allow-env supabase/functions/tests/owner
cd ../Dastak && deno test --allow-env supabase/functions/tests/owner
```

Expected: FAIL because owner guards and operations do not exist.

- [ ] **Step 3: Implement a reusable server owner guard and durable operations data**

`requireRecentOwner` checks an active `owner` row in `private.account_memberships` and verifies `auth.users.last_sign_in_at >= now() - interval '15 minutes'`. It returns a typed error instead of a boolean. Every admin function accepts a typed request whose `metadata` is `{ reason: String, expectedVersion: Int }`, locks the affected record, applies the typed body, increments its version, then inserts `audit.events` with actor, reason, before/after JSON, and timestamp.

Create `private.operational_alerts` and extend the foundation `private.safety_cases` with owner resolution fields and audit linkage. Both use explicit statuses, source entity/job, severity where applicable, and immutable audit links. No transient push message is the only record of a failed payout, stuck job, expired document, matching failure, report, or dispute.

- [ ] **Step 4: Implement product-specific owner endpoints**

Savari endpoints handle driver/vehicle evidence approval, zone/rate/commission revisions, suspension override, ride refund approval, live ride snapshot, and incident resolution. Dastak endpoints handle partner/merchant/pharmacy approval, product availability/category controls, restricted merchant/product compliance approval or suspension, restricted policy-version and exclusion-zone revision, delivery margin/commission revision, order refund approval, and incident resolution.

Restricted owner actions may approve, suspend, or revise an individual merchant, product, evidence record, or exclusion zone only after `requireRecentOwner`, a non-empty reason, an expected version, and an audit event. No endpoint may accept `activate_paan_corner`, set a global visibility flag, or bypass the Dastak server eligibility checks.

- [ ] **Step 5: Create narrow separate admin clients and tests**

`SavariAdminClient` and `DastakAdminClient` are distinct types with function-only APIs. Each test must confirm the request always includes a reason and a new app sign-in is required after 15 minutes. The targets may render only functional list/detail shells now; screen visual design remains deferred.

- [ ] **Step 6: Verify owner operations and commit**

```bash
cd Backends/Savari && deno test --allow-env supabase/functions/tests/owner
cd ../Dastak && deno test --allow-env supabase/functions/tests/owner
xcodebuild test -workspace SavariDastak.xcworkspace -scheme SavariAdmin -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme DastakAdmin -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
git add Backends Apps
git commit -m "feat: add separate marketplace owner operations"
```

Expected: only the correct recently authenticated owner can perform auditable operations in each product.

### Task 6: Verify cross-product, payment, and operations acceptance scenarios

**Files:**
- Create: `Backends/Savari/supabase/functions/tests/acceptance/cross_product.test.ts`
- Create: `Backends/Dastak/supabase/functions/tests/acceptance/cross_product.test.ts`
- Create: `Apps/Savari/SavariTests/CrossProductClientContractTests.swift`
- Create: `Apps/Dastak/DastakTests/CrossProductClientContractTests.swift`
- Create: `scripts/run-cross-product-acceptance.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: local fixture projects sharing only the test bridge secret, non-production Razorpay test keys, and owner/participant fixture accounts.
- Produces: an auditable proof of isolation, signed integration, and payout release semantics.

- [ ] **Step 1: Encode the acceptance matrix**

The suites must cover:

```text
no link -> Savari navigation cannot attach a Dastak order
link nonce replay/tamper/expiry -> rejected
linked passenger + ready paid order + <= five minute detour -> attached
ready order + > five minute detour -> rejected
passenger boarded + another customer's order -> rejected
linked Savari driver with active standalone ride -> Dastak reservation rejected
Dastak terminal delivery -> cross-product reservation released exactly once
Dastak completion signed once -> one settlement ledger entry
second eligible completion -> earlier in-app earning withdrawable
no second completion after 24h -> pending earning withdrawable
Razorpay webhook replay -> no duplicate payment/transfer
stale owner sign-in -> no rate/refund/approval action
post-payout refund -> adjustment record, not altered paid history
```

- [ ] **Step 2: Implement a two-backend local acceptance command**

Create `scripts/run-cross-product-acceptance.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

for backend in Savari Dastak; do
  (
    cd "Backends/$backend"
    supabase db reset --local
  )
done

(
  cd Backends/Savari
  deno test --allow-env --allow-net supabase/functions/tests/acceptance/cross_product.test.ts
)
(
  cd Backends/Dastak
  deno test --allow-env --allow-net supabase/functions/tests/acceptance/cross_product.test.ts
)
```

- [ ] **Step 3: Add client isolation tests**

Both iOS contract test files must scan source for the other project's Supabase URL/configuration name and fail if found. The only permitted connection is through the typed cross-product functions in the navigation/attachment feature.

- [ ] **Step 4: Run all acceptance checks and commit**

```bash
scripts/run-cross-product-acceptance.sh
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
git add Backends Apps scripts README.md
git commit -m "test: verify marketplace bridge settlement operations"
```

Expected: cross-product work is possible only through a signed, limited bridge and all payment/payout state is independent, deduplicated, and auditable.

## Cross-Product Completion Gate

- Explicit account linking requires proof of control of both product accounts and has no automatic match path.
- The ride-linked collection flow only allows the matched passenger's ready order under the five-minute and onboard rules.
- Dastak and Savari retain separate product/payment stores; the Savari private Settlement Coordinator contains only payout identity and ledger state.
- Razorpay order creation, webhooks, transfer release, failure, refund, and adjustment all execute server-side and pass sandbox replay tests.
- Owner actions are separately scoped, recently authenticated, reasoned, and immutable-audited.
- Restricted tobacco owner operations are limited to audited per-merchant, per-product, evidence, and exclusion-zone controls; no owner operation can bypass the Dastak release gate or eligibility checks.

## Source Checks Before Live Configuration

Before enabling a Razorpay live key or Apple Pay in an iOS target, re-read the current official documentation: [Razorpay Route](https://razorpay.com/docs/payments/route/?preferred-country=IN), [Razorpay iOS Standard SDK](https://razorpay.com/docs/payments/payment-gateway/ios-integration/standard/?preferred-country=IN), [Razorpay webhooks](https://razorpay.com/docs/webhooks/), and [Apple Maps Server API directions](https://developer.apple.com/documentation/applemapsserverapi/-v1-directions).
