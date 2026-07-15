# Dastak Delivery Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Dastak's separate, server-authoritative parcel and merchant delivery core with approved partner and merchant roles, prepayment state, automatic dispatch, evidence, refunds, and safe category controls.

**Architecture:** Dastak runs in its own Supabase project with independent identities, product data, delivery state, and payments. Deno Edge Functions own every order, partner, merchant, and delivery mutation. The Dastak and Dastak Merchant targets communicate only through typed function clients and read snapshots. The later Savari bridge is the sole allowed cross-product integration point.

**Tech Stack:** Swift 5 / iOS 17, `DastakDomain`, `MarketplaceFoundation`, `MarketplaceInfrastructure`, Supabase Edge Functions/Postgres/PostGIS/Storage, Deno, pgTAP, XCTest, Apple Maps Server API.

## Global Constraints

- Execute only after the foundation plan is complete. Do not add Dastak tables to the Savari project.
- Support immediate local parcel and merchant deliveries only. There is no scheduled delivery, cash on delivery, or courier waiting state.
- Dastak customers pay in-app before parcel assignment and before merchant fulfilment. The Razorpay creation and webhook authority arrive in the payments plan; this plan uses a server-owned payment-state contract.
- The nearest eligible partner is assigned automatically and has 60 seconds to acknowledge. A stale, timed-out, cancelled, or ineligible assignment is reassigned automatically.
- Delivery partners may use walking, bicycle, Bike, or Auto. Bike and Auto require owner-approved vehicle proof; walking and bicycle do not.
- Dastak drivers/partners do not become Savari drivers implicitly. Cross-product eligibility is modeled only in the bridge plan.
- Merchant orders are assigned only after the merchant accepts and marks them ready. Do not offer a partner a job while the merchant is preparing it.
- Medicine supports approved licensed pharmacies, required prescription evidence, invoice evidence, and no controlled-drug fulfilment flow.
- Paan Corner supports only owner-approved, non-electronic tobacco products. A customer must provide a current server-recorded 18+ self-attestation and versioned terms acknowledgement; the merchant and delivery locations must be outside owner-maintained 91.44m school/college exclusion zones; the merchant and each product require owner-approved compliance evidence; and the Delivery Partner must complete a visual age check before handoff. E-cigarettes and vaping products are excluded. The final iOS release requires documented applicable legal/distribution review and current Apple App Review risk review; this is not a guarantee of approval. Do not add a generic category activation switch or a concealed flow.
- Clients have no direct write privileges on orders, deliveries, merchant status, partner availability, payment/refund state, evidence review, or payouts.

---

### Task 1: Define the Dastak state, item, and partner domain packages

**Files:**
- Create: `Packages/DastakDomain/Sources/DastakDomain/DeliveryStatus.swift`
- Create: `Packages/DastakDomain/Sources/DastakDomain/DeliveryMethod.swift`
- Create: `Packages/DastakDomain/Sources/DastakDomain/Parcel.swift`
- Create: `Packages/DastakDomain/Sources/DastakDomain/MerchantOrder.swift`
- Create: `Packages/DastakDomain/Sources/DastakDomain/DeliverySnapshot.swift`
- Create: `Packages/DastakDomain/Sources/DastakDomain/DeliveryIntent.swift`
- Create: `Packages/DastakDomain/Sources/DastakDomain/RefundEligibility.swift`
- Create: `Packages/DastakDomain/Tests/DastakDomainTests/DeliveryStatusTests.swift`
- Create: `Packages/DastakDomain/Tests/DastakDomainTests/RefundEligibilityTests.swift`

**Interfaces:**
- Consumes: `Money`, `GeoPoint`, and `IdempotencyKey` from `MarketplaceFoundation`.
- Produces: delivery and merchant order state types used by Dastak Edge Functions and app repositories.

- [ ] **Step 1: Write the failing state and refund tests**

Create `DeliveryStatusTests.swift`:

```swift
import XCTest
@testable import DastakDomain

final class DeliveryStatusTests: XCTestCase {
    func testMerchantOrderCannotBeAssignedBeforeReady() {
        XCTAssertFalse(DeliveryStatus.merchantAccepted.canTransition(to: .assigned))
        XCTAssertTrue(DeliveryStatus.ready.canTransition(to: .assigned))
    }

    func testParcelRequiresPickupBeforeDelivery() {
        XCTAssertFalse(DeliveryStatus.assigned.canTransition(to: .delivered))
        XCTAssertTrue(DeliveryStatus.pickedUp.canTransition(to: .inTransit))
    }

    func testRestrictedHandoffRequiresReturnBeforeRefund() {
        XCTAssertTrue(DeliveryStatus.inTransit.canTransition(to: .returningToMerchant))
        XCTAssertFalse(DeliveryStatus.inTransit.canTransition(to: .refundPending))
        XCTAssertTrue(DeliveryStatus.returningToMerchant.canTransition(to: .refundPending))
    }
}
```

Create `RefundEligibilityTests.swift`:

```swift
func testMerchantOrderRefundRulesAreStageBased() {
    XCTAssertEqual(RefundEligibility(status: .paid).decision, .full)
    XCTAssertEqual(RefundEligibility(status: .merchantAccepted).decision, .ownerOrMerchantFailure)
    XCTAssertEqual(RefundEligibility(status: .pickedUp).decision, .deliveryFeeRetainedUnlessFault)
}
```

- [ ] **Step 2: Run the failing package tests**

```bash
swift test --package-path Packages/DastakDomain
```

Expected: FAIL because the Dastak state and refund types do not exist.

- [ ] **Step 3: Implement exact Dastak delivery states**

Create `DeliveryStatus.swift` with these cases:

```swift
public enum DeliveryStatus: String, Codable, Sendable {
    case paymentPending = "payment_pending"
    case paid
    case merchantAccepted = "merchant_accepted"
    case ready
    case assigned
    case enRouteToPickup = "en_route_to_pickup"
    case pickedUp = "picked_up"
    case inTransit = "in_transit"
    case delivered
    case cancelled
    case refundPending = "refund_pending"
    case refunded
    case returningToMerchant = "returning_to_merchant"
}
```

`canTransition(to:)` must allow `paid -> assigned` for a parcel, `paid -> merchantAccepted -> ready -> assigned` for a merchant order, and require `pickedUp -> inTransit -> delivered` for both. A restricted handoff failure must move `inTransit -> returningToMerchant -> refundPending`, never directly to `delivered`. Model delivery kind separately as `.parcel` or `.merchantOrder`; do not add product-specific booleans to the status enum.

- [ ] **Step 4: Define typed input contracts**

Create these exact request boundaries in `DeliveryIntent.swift`:

```swift
public enum DeliveryMethod: String, Codable, Sendable {
    case walking
    case bicycle
    case bike
    case auto
}

public struct CreateParcelRequest: Codable, Sendable {
    public let pickup: GeoPoint
    public let dropoff: GeoPoint
    public let declaredContents: String
    public let declaredValue: Money
    public let deliveryMethod: DeliveryMethod
}

public struct CreateMerchantOrderRequest: Codable, Sendable {
    public let merchantID: UUID
    public let lines: [MerchantOrderLine]
    public let deliveryMethod: DeliveryMethod
}

public struct MarkMerchantOrderReadyRequest: Codable, Sendable {
    public let orderID: UUID
}

public struct VerifyDeliveryCodeRequest: Codable, Sendable {
    public let deliveryID: UUID
    public let code: String
}
```

`MerchantOrderLine` contains `productID` and quantity only. The client never sends a name, unit price, category, commission, delivery fee, merchant ID override, or payout value to be trusted.

`DeliverySnapshot` exposes a public initializer for ID, status, delivery kind, selected method, immutable price snapshot, pickup/dropoff points, caller-authorized counterpart display data, assignment deadline, and `stateVersion: Int64`. It never contains a delivery-code hash, raw prescription, merchant private data, or mutable local status.

- [ ] **Step 5: Verify domain isolation and commit**

```bash
swift test --package-path Packages/DastakDomain
swift package --package-path Packages/DastakDomain describe
git add Packages/DastakDomain
git commit -m "feat: define Dastak delivery domain"
```

Expected: tests pass and the package depends on `MarketplaceFoundation`, not `SavariDomain`.

### Task 2: Create approved partner, merchant, catalog, and delivery storage

**Files:**
- Create: `Backends/Dastak/supabase/migrations/20260715110000_create_dastak_core.sql`
- Create: `Backends/Dastak/supabase/migrations/20260715111000_create_dastak_security.sql`
- Create: `Backends/Dastak/supabase/functions/submit-partner-application/index.ts`
- Create: `Backends/Dastak/supabase/functions/submit-merchant-application/index.ts`
- Create: `Backends/Dastak/supabase/functions/attest-restricted-catalogue-eligibility/index.ts`
- Create: `Backends/Dastak/supabase/functions/get-restricted-catalogue/index.ts`
- Create: `Backends/Dastak/supabase/functions/tests/restricted_catalogue/eligibility.test.ts`
- Create: `Backends/Dastak/supabase/tests/database/020_dastak_core.pgtap.sql`
- Create: `Backends/Dastak/supabase/tests/database/021_dastak_security.pgtap.sql`

**Interfaces:**
- Consumes: Dastak accounts, membership, service zones, audit, and private evidence storage from foundation.
- Produces: owner-approved `delivery_partner_profiles`, `merchant_profiles`, `pharmacy_profiles`, ordinary public catalog reads, server-filtered restricted catalog reads, and participant-only delivery reads.

- [ ] **Step 1: Write failing Dastak schema tests**

Create `020_dastak_core.pgtap.sql`:

```sql
begin;
select plan(18);
select has_table('public', 'delivery_partner_profiles');
select has_table('public', 'merchant_profiles');
select has_table('public', 'merchant_products');
select has_table('public', 'deliveries');
select has_table('private', 'delivery_events');
select has_column('public', 'deliveries', 'status');
select has_column('public', 'deliveries', 'pickup_code_digest');
select has_column('public', 'deliveries', 'delivery_code_digest');
select has_column('public', 'merchant_products', 'availability');
select has_column('public', 'merchant_products', 'category');
select has_table('public', 'dastak_rate_cards');
select has_column('public', 'dastak_rate_cards', 'per_kilometre_paise');
select has_table('public', 'restricted_product_exclusion_zones');
select has_table('private', 'restricted_product_attestations');
select has_table('private', 'restricted_product_policy_versions');
select has_column('public', 'merchant_profiles', 'restricted_product_approval_state');
select has_column('public', 'merchant_products', 'restricted_product_approval_state');
select has_column('public', 'merchant_products', 'restricted_tobacco_kind');
select * from finish();
rollback;
```

- [ ] **Step 2: Run the failing schema test**

```bash
cd Backends/Dastak
supabase db test supabase/tests/database/020_dastak_core.pgtap.sql --local
deno test --allow-env supabase/functions/tests/restricted_catalogue/eligibility.test.ts
```

Expected: FAIL because Dastak delivery tables and restricted catalog handlers do not exist.

- [ ] **Step 3: Build owner-approved business profiles and catalog rules**

Create the following core definitions:

```sql
create type public.delivery_method as enum ('walking', 'bicycle', 'bike', 'auto');
create type public.delivery_kind as enum ('parcel', 'merchant_order');
create type public.delivery_status as enum (
  'payment_pending', 'paid', 'merchant_accepted', 'ready', 'assigned',
  'en_route_to_pickup', 'picked_up', 'in_transit', 'delivered',
  'cancelled', 'returning_to_merchant', 'refund_pending', 'refunded'
);
create type public.catalog_category as enum ('general', 'otc_medicine', 'prescription_medicine', 'paan_corner');
create type public.restricted_product_approval_state as enum ('not_applicable', 'pending', 'approved', 'rejected', 'suspended');
create type public.restricted_tobacco_kind as enum ('cigarette', 'bidi', 'cigar', 'smoking_tobacco', 'other_lawful_tobacco');

create table public.dastak_rate_cards (
  id uuid primary key default gen_random_uuid(),
  delivery_method public.delivery_method not null,
  zone_id uuid not null references public.service_zones(id),
  minimum_fare_paise integer not null check (minimum_fare_paise > 0),
  per_kilometre_paise integer not null check (per_kilometre_paise > 0),
  active_from timestamptz not null,
  active_to timestamptz,
  check (active_to is null or active_to > active_from)
);

create table public.delivery_partner_profiles (
  account_id uuid primary key references public.accounts(id),
  active_method public.delivery_method not null,
  approval_state text not null check (approval_state in ('pending', 'approved', 'rejected', 'suspended')),
  vehicle_evidence_path text,
  approved_at timestamptz,
  updated_at timestamptz not null default now(),
  check (
    (active_method in ('walking', 'bicycle') and vehicle_evidence_path is null)
    or (active_method in ('bike', 'auto') and vehicle_evidence_path is not null)
  )
);

create table public.merchant_profiles (
  id uuid primary key default gen_random_uuid(),
  owner_account_id uuid not null references public.accounts(id),
  display_name text not null,
  location extensions.geometry(Point, 4326) not null,
  supported_delivery_methods public.delivery_method[] not null,
  approval_state text not null check (approval_state in ('pending', 'approved', 'rejected', 'suspended')),
  restricted_product_approval_state public.restricted_product_approval_state not null default 'not_applicable',
  restricted_product_compliance_evidence_path text,
  is_pharmacy boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.restricted_product_exclusion_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  boundary extensions.geometry(Polygon, 4326) not null,
  reason text not null check (reason in ('school', 'college')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table private.restricted_product_attestations (
  account_id uuid primary key references public.accounts(id) on delete cascade,
  terms_version text not null,
  attested_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table private.restricted_product_policy_versions (
  version text primary key,
  active boolean not null default false,
  published_at timestamptz not null default now()
);

create unique index restricted_product_policy_versions_one_active
  on private.restricted_product_policy_versions (active)
  where active;

alter table public.restricted_product_exclusion_zones enable row level security;
revoke all on public.restricted_product_exclusion_zones from anon, authenticated;
revoke all on private.restricted_product_attestations, private.restricted_product_policy_versions from anon, authenticated;
```

`merchant_products` belongs to an approved merchant, stores integer paise prices and availability, and is read-only to customers only when its merchant and product are active. Add `restricted_product_approval_state` and nullable `restricted_tobacco_kind` to this table. A `paan_corner` product requires an approved merchant and product state plus a non-null allowed tobacco kind; this enum intentionally excludes e-cigarettes and vaping products. Products outside `paan_corner` must use `not_applicable` and a null tobacco kind.

Ordinary products may use the narrow customer read policy. `paan_corner` products must never be exposed through a broad table `SELECT`. `attest-restricted-catalogue-eligibility` records only the authenticated customer's 18+ confirmation and the one active server policy version; it does not trust a client DOB or grant a bypass. `get-restricted-catalogue` accepts a delivery point, verifies a current unrevoked attestation, an active owner-approved merchant/product, and that both merchant and delivery points do not intersect an active school/college exclusion zone. It returns a minimal price/catalog snapshot, not table rows. Store the 91.44m legal buffer in the owner-maintained zone polygon, and audit every policy-version and zone revision.

In `eligibility.test.ts`, write failing cases for a missing attestation, a stale policy version, an excluded merchant/delivery point, an unapproved merchant/product, and an excluded vaping product. Include one compliant attested, approved, out-of-zone case. Run it with `deno test --allow-env supabase/functions/tests/restricted_catalogue/eligibility.test.ts` after the failing schema test and again after implementation.

The customer chooses one merchant-supported delivery method for a parcel or merchant order; the server uses the matching rate card and locks that method into the quote/order, so an upfront delivery fee cannot change merely because a different partner method later appears.

`submit-partner-application` accepts one active method and issued evidence URLs. It permits walking/bicycle without vehicle evidence and requires bike/auto evidence, but it never writes `approved`. `submit-merchant-application` accepts merchant location, licence evidence when a pharmacy is requested, and issued private evidence URLs; it never writes merchant/pharmacy approval. Dastak owner approval is the sole route to operational membership.

- [ ] **Step 4: Create deliveries and private event data with no client DML**

The `public.deliveries` row has customer, partner, merchant optional, kind, status, pickup/dropoff, rate snapshot, delivery fee, item subtotal, partner payout, payment/refund state, state version, and timestamp columns. `private.delivery_events` records immutable transition payloads and `private.delivery_positions` stores precise partner trace points.

Enable RLS. Grant customers, assigned partners, and merchant owner only the exact `SELECT` path necessary for an active delivery. Revoke all client DML from public delivery, merchant, profile, approval, event, position, and rate tables. The only direct client write allowed in this product is an object upload to the narrow private evidence path issued by the function from foundation.

- [ ] **Step 5: Add security test coverage and run it**

`021_dastak_security.pgtap.sql` must assert that `authenticated` has no DML grant on `public.deliveries`, cannot read `private.delivery_events` or `private.restricted_product_attestations`, and cannot read a `paan_corner` product through a broad customer policy. The only restricted catalog path is the function that evaluates attestation, approved merchant/product state, and exclusion zones. Run:

```bash
cd Backends/Dastak
supabase db reset --local
supabase db test supabase/tests/database/020_dastak_core.pgtap.sql --local
supabase db test supabase/tests/database/021_dastak_security.pgtap.sql --local
deno test --allow-env supabase/functions/tests/restricted_catalogue/eligibility.test.ts
```

Expected: all schema and security assertions pass.

- [ ] **Step 6: Commit the Dastak core schema**

```bash
git add Backends/Dastak/supabase
git commit -m "feat: add Dastak delivery core schema"
```

### Task 3: Implement partner availability, nearest assignment, and parcel lifecycle

**Files:**
- Create: `Backends/Dastak/supabase/migrations/20260715112000_partner_dispatch.sql`
- Create: `Backends/Dastak/supabase/functions/create-parcel/index.ts`
- Create: `Backends/Dastak/supabase/functions/_shared/apple_maps.ts`
- Create: `Backends/Dastak/supabase/functions/quote-delivery/index.ts`
- Create: `Backends/Dastak/supabase/functions/set-partner-availability/index.ts`
- Create: `Backends/Dastak/supabase/functions/report-partner-location/index.ts`
- Create: `Backends/Dastak/supabase/functions/acknowledge-delivery-assignment/index.ts`
- Create: `Backends/Dastak/supabase/functions/verify-parcel-pickup-code/index.ts`
- Create: `Backends/Dastak/supabase/functions/verify-delivery-code/index.ts`
- Create: `Backends/Dastak/supabase/functions/dispatch-deliveries/index.ts`
- Create: `Backends/Dastak/supabase/functions/report-delivery-safety-incident/index.ts`
- Create: `Backends/Dastak/supabase/functions/tests/parcel/parcel_lifecycle.test.ts`
- Create: `Backends/Dastak/supabase/functions/tests/dispatch/partner_selection.test.ts`
- Create: `Backends/Dastak/supabase/tests/database/022_partner_dispatch.pgtap.sql`

**Interfaces:**
- Consumes: a paid parcel delivery, partner approved membership, fresh position, delivery method, active zone, and customer/recipient codes.
- Produces: one assigned nearest partner, private pickup/delivery codes, and a delivered parcel with immutable evidence events.

- [ ] **Step 1: Write failing dispatch and parcel tests**

Create the partner selection unit test:

```ts
Deno.test('partner assignment excludes an unapproved bike', () => {
  const partner = choosePartner([
    { id: 'pending-bike', method: 'bike', approved: false, fresh: true, distanceMeters: 5 },
    { id: 'walking', method: 'walking', approved: true, fresh: true, distanceMeters: 30 },
  ]);
  assertEquals(partner?.id, 'walking');
});
```

Create parcel lifecycle assertions for `paid -> assigned -> en_route_to_pickup -> picked_up -> in_transit -> delivered`, wrong pickup code rejection, wrong delivery code rejection, and a delivery quote that uses a server route distance rather than a client-supplied distance.

- [ ] **Step 2: Run the failing Deno tests**

```bash
cd Backends/Dastak
deno test --allow-env supabase/functions/tests/parcel/parcel_lifecycle.test.ts
deno test --allow-env supabase/functions/tests/dispatch/partner_selection.test.ts
```

Expected: FAIL because parcel handlers and selection helpers do not exist.

- [ ] **Step 3: Implement partner eligibility and automatic dispatch**

Create private availability and position tables. An eligible partner must be approved, online, not suspended, have no active standalone delivery, have a location recorded within 90 seconds, match a permitted delivery method, and be inside the active service zone. `set-partner-availability` invokes `private.assign_next_delivery` immediately after a partner turns online. `report-partner-location` is the only location mutation path.

`quote-delivery` validates pickup/dropoff in one active zone, obtains route distance and ETA from Apple Maps Server API with the server-held `APPLE_MAPS_TOKEN`, selects the active method rate card, and returns `max(minimum_fare_paise, ceil(distance_m / 1000.0) * per_kilometre_paise)`. `create-parcel` consumes an unexpired quote owned by the caller; it never trusts a delivery fee or distance from the client.

`private.assign_next_delivery` locks the delivery and candidate availability rows, orders candidates by PostGIS distance, sets `assignment_ack_deadline = now() + interval '60 seconds'`, and writes an immutable assignment event. It never exposes an unassigned delivery pool to clients. A one-minute `dispatch-deliveries` cron call requeues expired/stale assignments and turns idle partners offline after 15 minutes. Apply the same reliability policy as Savari: three missed or unacknowledged automatic assignments in 24 hours forces 30 minutes offline; five misses in seven days requires owner review; customer cancellation never counts as a miss.

- [ ] **Step 4: Implement the pre-paid parcel actions**

`create-parcel` validates sender/dropoff in an active zone, declared contents length `1...300`, non-negative declared value, and a server-calculated fee. It creates `payment_pending`; only a provider-confirmed server call can transition it to `paid`. It generates a six-digit pickup code and delivery code using Web Crypto, stores salted digests only, and gives each raw code only to its rightful customer/recipient snapshot.

`verify-parcel-pickup-code` requires the assigned partner and moves `en_route_to_pickup -> picked_up -> in_transit`. `verify-delivery-code` requires the assigned partner and recipient code, records delivery handoff evidence, then moves `in_transit -> delivered`; it must reject a `paan_corner` merchant order with `restricted_handoff_required` so the Task 4 restricted handoff function is the sole completion path.

`report-delivery-safety-incident` accepts an active/recent delivery ID, incident type, and report text, writes a durable `private.safety_cases` reference without changing delivery state, and is paired with a functional app action that opens `tel:112`. It must not claim live staffed emergency response.

- [ ] **Step 5: Add database invariants and execute the tests**

`022_partner_dispatch.pgtap.sql` must prove a partner cannot hold two active standalone deliveries, a bike/auto partner cannot be eligible without vehicle evidence, an expired assignment is eligible for reassignment, three misses force a 30-minute suspension, five seven-day misses require owner review, and customer cancellation does not count as a miss. Run:

```bash
cd Backends/Dastak
supabase db reset --local
supabase db test supabase/tests/database/022_partner_dispatch.pgtap.sql --local
deno test --allow-env supabase/functions/tests/parcel supabase/functions/tests/dispatch
```

Expected: all parcel, partner eligibility, and reassignment tests pass.

- [ ] **Step 6: Commit parcel and dispatch support**

```bash
git add Backends/Dastak/supabase
git commit -m "feat: add Dastak parcel dispatch"
```

### Task 4: Implement merchant fulfilment, stage-based refunds, and controlled-category enforcement

**Files:**
- Create: `Backends/Dastak/supabase/migrations/20260715113000_merchant_fulfilment.sql`
- Create: `Backends/Dastak/supabase/functions/create-merchant-order/index.ts`
- Create: `Backends/Dastak/supabase/functions/merchant-accept-order/index.ts`
- Create: `Backends/Dastak/supabase/functions/merchant-mark-order-ready/index.ts`
- Create: `Backends/Dastak/supabase/functions/request-order-refund/index.ts`
- Create: `Backends/Dastak/supabase/functions/upload-prescription-evidence/index.ts`
- Create: `Backends/Dastak/supabase/functions/verify-restricted-handoff/index.ts`
- Create: `Backends/Dastak/supabase/functions/confirm-restricted-return/index.ts`
- Create: `Backends/Dastak/supabase/functions/tests/merchant/order_lifecycle.test.ts`
- Create: `Backends/Dastak/supabase/functions/tests/merchant/category_controls.test.ts`
- Create: `Backends/Dastak/supabase/functions/tests/merchant/restricted_handoff.test.ts`
- Create: `Backends/Dastak/supabase/tests/database/023_merchant_refunds.pgtap.sql`

**Interfaces:**
- Consumes: customer basket line IDs/quantities, active approved merchant/pharmacy, server payment state, merchant actor, and product category controls.
- Produces: a price-snapshotted merchant order, merchant acceptance/ready state, only-ready automatic dispatch, and immutable refund eligibility decision.

- [ ] **Step 1: Write failing merchant and category tests**

Create a test that attempts to create an order with a client-supplied price of 1 paise for a 100-rupee product and expects the stored snapshot to use the server product price. Create a test asserting `merchant_accepted` does not dispatch a partner, while `ready` does. Create category tests asserting unapproved pharmacy and missing required prescription both return `prescription_required`; a restricted catalog/order without a current attestation returns `adult_attestation_required`; a merchant or delivery point in an exclusion zone returns `restricted_location_prohibited`; an unapproved restricted merchant/product or prohibited tobacco kind returns `restricted_product_unavailable`; and an approved attested order outside the zones succeeds.

- [ ] **Step 2: Run the failing merchant tests**

```bash
cd Backends/Dastak
deno test --allow-env supabase/functions/tests/merchant/order_lifecycle.test.ts
deno test --allow-env supabase/functions/tests/merchant/category_controls.test.ts
deno test --allow-env supabase/functions/tests/merchant/restricted_handoff.test.ts
```

Expected: FAIL because merchant order handlers do not exist.

- [ ] **Step 3: Create order snapshots and controlled category schema**

Add `public.merchant_orders`, `public.merchant_order_lines`, and `private.refund_decisions`. Insert each line from the current server product price and availability in one transaction. Store item subtotal, delivery fee, partner payout, merchant commission, and margin as immutable paise snapshots.

Add `requires_prescription boolean` to products, `prescription_evidence_path` to orders, and `pharmacy_licence_evidence_path` to pharmacy profiles. A merchant profile may publish prescription products only when `is_pharmacy = true` and owner approval plus licence evidence exists. For a `paan_corner` order, `create-merchant-order` must server-check the authenticated customer's current restricted-product attestation and terms version, the active owner-approved merchant and product compliance state, the allowed non-electronic tobacco kind, and both merchant and delivery points against active exclusion zones. The client supplies neither an age result, a product price, a compliance result, nor a zone result to trust.

- [ ] **Step 4: Implement merchant state and refund decisions**

`create-merchant-order` validates the selected `deliveryMethod` against the approved merchant's supported methods, calls the server route quote, and creates `payment_pending`; provider confirmation moves it to `paid`. `merchant-accept-order` permits only the owner of the approved merchant and moves `paid -> merchant_accepted`. `merchant-mark-order-ready` moves `merchant_accepted -> ready` and calls automatic assignment. There is no partner dispatch before ready.

`request-order-refund` writes a private decision event with these exact outcomes:

```text
paid -> full refund eligible
merchant_accepted or ready -> only merchant_failure or owner_approved eligible
assigned, en_route_to_pickup, picked_up, in_transit, returning_to_merchant -> item and delivery fee remain unless fault is merchant_fault or dastak_fault
delivered -> owner review only
```

It cannot silently edit `delivery_fee_paise`, `item_subtotal_paise`, or a provider payment record.

`verify-restricted-handoff` requires the assigned partner, the recipient delivery code, and a recorded visual age-check result. It can complete a `paan_corner` handoff only when the visual check passes. A failed or uncertain check never hands over the item: the server records an immutable reason, moves the delivery to `returning_to_merchant`, and instructs the partner to return it. `confirm-restricted-return` requires the approved merchant actor, records the return evidence, then moves the order to `refund_pending` for the existing stage-based decision path. Neither function changes money directly.

- [ ] **Step 5: Verify merchant, pharmacy, and Paan controls**

`023_merchant_refunds.pgtap.sql` must assert a pgtap customer role cannot insert merchant order lines directly, no active broad customer select policy reveals `paan_corner`, and only owner functions can transition refund decisions beyond `refund_pending`. The Deno tests must prove the restricted server path rejects missing attestation, excluded locations, unapproved merchants/products, and non-allowed tobacco kinds; permits the compliant path; and prevents delivery handoff when the partner visual check fails.

Run:

```bash
cd Backends/Dastak
supabase db reset --local
supabase db test supabase/tests/database/023_merchant_refunds.pgtap.sql --local
deno test --allow-env supabase/functions/tests/merchant
```

Expected: ready state is the only merchant-dispatch entry, prices are server snapshots, and disallowed categories remain unavailable.

- [ ] **Step 6: Commit merchant core**

```bash
git add Backends/Dastak/supabase
git commit -m "feat: add Dastak merchant fulfilment"
```

### Task 5: Build function-client-only Dastak customer, partner, and merchant shells

**Files:**
- Create: `Apps/Dastak/Dastak/DastakApp.swift`
- Create: `Apps/Dastak/Dastak/AppComposition.swift`
- Create: `Apps/Dastak/Dastak/Deliveries/DastakDeliveryClient.swift`
- Create: `Apps/Dastak/Dastak/Deliveries/DeliveryStore.swift`
- Create: `Apps/Dastak/Dastak/Partner/PartnerAvailabilityReporter.swift`
- Create: `Apps/Dastak/DastakMerchant/DastakMerchantApp.swift`
- Create: `Apps/Dastak/DastakMerchant/Orders/MerchantOrderStore.swift`
- Create: `Apps/Dastak/DastakTests/DeliveryStoreTests.swift`
- Create: `Apps/Dastak/DastakTests/DeliveryTestDoubles.swift`
- Create: `Apps/Dastak/DastakMerchantTests/MerchantOrderStoreTests.swift`

**Interfaces:**
- Consumes: `FunctionClient`, `DastakDomain` intents/snapshots, private delivery wake-ups, and location authorization for partner mode.
- Produces: customer/partner and merchant stores which replace state only from server snapshots.

- [ ] **Step 1: Write failing repository tests with a recording client**

Create `DeliveryStoreTests.swift`:

```swift
@MainActor
func testMerchantOrderSendsProductIDsAndQuantitiesOnly() async throws {
    let client = RecordingDeliveryClient(response: DeliverySnapshot.fixture(status: .paymentPending))
    let store = DeliveryStore(client: client)

    try await store.createMerchantOrder(
        merchantID: UUID(),
        lines: [MerchantOrderLine(productID: UUID(), quantity: 2)],
        deliveryMethod: .bike
    )

    let calls = await client.calls
    let call = try XCTUnwrap(calls.first)
    XCTAssertEqual(call.name, "create-merchant-order")
    XCTAssertFalse(call.encodedBody.contains("price"))
}
```

`DeliveryTestDoubles.swift` defines `RecordingDeliveryClient` as an actor conforming to `DastakDeliveryClient`. It records the function name, JSON-encoded body, and idempotency key, then returns the injected typed response. Define `DeliverySnapshot.fixture(status:version:)` in this test file using the public initializer from Task 1. The production `DastakDeliveryClient` is the only layer that wraps `FunctionClient`.

- [ ] **Step 2: Run the failing iOS tests**

```bash
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme DastakMerchant -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: FAIL because targets and stores do not exist.

- [ ] **Step 3: Implement narrow client protocols and stores**

Create this customer/partner protocol:

```swift
protocol DastakDeliveryClient: Sendable {
    func createParcel(_ request: CreateParcelRequest, key: IdempotencyKey) async throws -> DeliverySnapshot
    func createMerchantOrder(_ request: CreateMerchantOrderRequest, key: IdempotencyKey) async throws -> DeliverySnapshot
    func activeDelivery() async throws -> DeliverySnapshot?
    func perform<Action: Encodable & Sendable, Response: Decodable & Sendable>(
        _ function: String, action: Action, key: IdempotencyKey
    ) async throws -> Response
}
```

`DeliveryStore` uses `DeliverySnapshot.stateVersion` as the single source of truth. `PartnerAvailabilityReporter` uses only the `set-partner-availability` and `report-partner-location` functions. `MerchantOrderStore` exposes only merchant accept, mark ready, and merchant-failure signals for orders returned by the merchant-specific snapshot.

- [ ] **Step 4: Enforce no direct backend mutations in targets**

Add source-scanning tests to `DastakTests` and `DastakMerchantTests` that reject `.from(`, `.insert(`, `.update(`, `.upsert(`, and `.rpc(` within the respective app sources. The only accepted network execution surface is `FunctionClient.invoke`.

- [ ] **Step 5: Verify iOS client contracts and commit**

```bash
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme DastakMerchant -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
git add Apps/Dastak Packages/DastakDomain
git commit -m "feat: add Dastak client contracts"
```

Expected: customer, partner, and merchant client stores compile and cannot reintroduce raw table mutation.

### Task 6: Add a multi-role Dastak acceptance suite

**Files:**
- Create: `Backends/Dastak/supabase/functions/tests/acceptance/dastak_delivery.test.ts`
- Create: `Apps/Dastak/DastakTests/DastakSnapshotPropagationTests.swift`
- Create: `scripts/run-dastak-acceptance.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: local Dastak fixtures for customer, approved partner, merchant, pharmacy, recipient, and service-zone rate card.
- Produces: deterministic proof that parcel, merchant, refund, and privacy behavior works without manual simulator timing.

- [ ] **Step 1: Encode the acceptance matrix**

The Deno test must cover:

```text
paid parcel -> nearest partner assignment -> pickup code -> delivery code -> delivered
partner acknowledgement timeout -> next eligible partner assignment
merchant payment -> merchant accepted -> no dispatch -> ready -> dispatch
merchant price tampering request -> server product price retained
refund before merchant acceptance -> full eligibility
refund after merchant acceptance -> only merchant failure or owner path
unapproved pharmacy or missing prescription -> no fulfilment
paan_corner without attestation, approved merchant/product, or valid location -> typed restricted error
compliant paan_corner order -> partner visual check required before handoff
failed/uncertain restricted visual check -> returning_to_merchant -> refund_pending, never delivered
partner completion -> customer snapshot reaches delivered with a newer state version
```

- [ ] **Step 2: Add and run the local acceptance command**

Create `scripts/run-dastak-acceptance.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd Backends/Dastak
supabase db reset --local
deno test --allow-env --allow-net supabase/functions/tests/acceptance/dastak_delivery.test.ts
```

Run it before client propagation tests. Expected: FAIL until all core functions are deployed locally.

- [ ] **Step 3: Verify server state propagation in the app target**

`DastakSnapshotPropagationTests.swift` must inject a sequence `assigned`, `picked_up`, `in_transit`, `delivered` with state versions `1...4` and verify the store ignores an out-of-order `2` after it already accepted `3`.

- [ ] **Step 4: Run the full suite and commit**

```bash
scripts/run-dastak-acceptance.sh
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Dastak -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -workspace SavariDastak.xcworkspace -scheme DastakMerchant -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
git add Backends/Dastak Apps/Dastak scripts README.md
git commit -m "test: add Dastak delivery acceptance suite"
```

Expected: separate customer, merchant, and partner transitions are verified, including the no-wait readiness rule and server-enforced restricted tobacco controls.

## Dastak Core Completion Gate

- Only owner-approved delivery partners, merchants, and pharmacies can perform their operational roles.
- A parcel needs server-confirmed prepayment, pickup evidence, and delivery evidence.
- A merchant order cannot dispatch until merchant-ready state.
- Prices, commissions, payout values, payment/refund state, and partner assignment are server snapshots.
- Pharmacy evidence paths and category eligibility are enforced server-side.
- Paan Corner is available only through the server-enforced adult attestation, exclusion-zone, owner-approved merchant/product, and partner visual handoff path; no e-cigarette or vaping product can enter that path.
- Paan Corner is not included in a release until the documented legal, distribution, and current Apple App Review risk gate has passed.
- Dastak targets can perform only typed function calls and pass the multi-role acceptance suite.
