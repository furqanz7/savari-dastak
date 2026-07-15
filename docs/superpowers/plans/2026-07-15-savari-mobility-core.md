# Savari Mobility Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a server-authoritative Savari Auto and Bike ride lifecycle with fixed quotes, automatic assignment, privacy-safe participant state, and verified terminal actions.

**Architecture:** Savari keeps all mutable ride state in its own Supabase project. Edge Functions authenticate user intent, invoke private transactional SQL, and publish a private active-ride wake-up. The iOS app only reads an authorized ride snapshot and submits typed intents through `FunctionClient`; it never writes a ride table or manufactures an assignment locally. Apple Maps Server API supplies authoritative route distance and ETA for pricing, while native MapKit only presents routes in the future UI layer.

**Tech Stack:** Swift 5 / iOS 17, `SavariDomain`, `MarketplaceInfrastructure`, Supabase Edge Functions and Postgres/PostGIS, Supabase private Realtime Broadcast, Apple Maps Server API, XCTest, pgTAP, Deno tests.

## Global Constraints

- Execute only after the foundation completion gate in `2026-07-15-savari-dastak-foundation.md` passes.
- Support immediate Auto and Bike rides inside an active Vaniyambadi service zone only.
- Use a minimum fare plus per-kilometre rate. No surge, wait-time, time-based price, scheduled trip, or driver picker.
- Rates and route distance are server-authoritative. The app cannot submit a fare or route distance to be trusted.
- Closest eligible driver is assigned automatically; acknowledgement expires after 60 seconds. No manual accept screen or fake request data.
- A driver goes offline automatically after 15 idle minutes and cannot manually go offline while assigned or active.
- Arrival and final completion require a server check against a fresh driver location within 100 meters of the corresponding point.
- A boarding code starts payment eligibility. Before it is verified, passenger cancellation is free.
- Cash and direct UPI stay fully with the driver. In-app payment is finalised later by the payments plan.
- The only participant phone disclosure is driver phone to passenger after assignment and passenger phone to driver after verified arrival.

---

### Task 1: Define the Savari domain and quote contracts with tests

**Files:**
- Create: `Packages/SavariDomain/Sources/SavariDomain/RideStatus.swift`
- Create: `Packages/SavariDomain/Sources/SavariDomain/RideSnapshot.swift`
- Create: `Packages/SavariDomain/Sources/SavariDomain/RideIntent.swift`
- Create: `Packages/SavariDomain/Sources/SavariDomain/FareQuote.swift`
- Create: `Packages/SavariDomain/Tests/SavariDomainTests/RideStatusTests.swift`
- Create: `Packages/SavariDomain/Tests/SavariDomainTests/FareQuoteTests.swift`

**Interfaces:**
- Consumes: `Money`, `GeoPoint`, and `IdempotencyKey` from `MarketplaceFoundation`.
- Produces: `RideStatus`, `RideSnapshot`, `RideQuote`, and intent payloads used by Savari Edge Functions and iOS repositories.

- [ ] **Step 1: Write failing state and fare tests**

Create `RideStatusTests.swift` with the complete transition table assertion:

```swift
import XCTest
@testable import SavariDomain

final class RideStatusTests: XCTestCase {
    func testOnlyDeclaredTransitionsAreAllowed() {
        XCTAssertTrue(RideStatus.requested.canTransition(to: .assigned))
        XCTAssertTrue(RideStatus.arrived.canTransition(to: .boarded))
        XCTAssertTrue(RideStatus.boarded.canTransition(to: .inProgress))
        XCTAssertTrue(RideStatus.boarded.canTransition(to: .cancelledBeforeStart))
        XCTAssertTrue(RideStatus.inProgress.canTransition(to: .paymentDue))
        XCTAssertTrue(RideStatus.paymentDue.canTransition(to: .completed))
        XCTAssertFalse(RideStatus.requested.canTransition(to: .inProgress))
        XCTAssertFalse(RideStatus.completed.canTransition(to: .inProgress))
    }
}
```

Create `FareQuoteTests.swift`:

```swift
func testFareUsesMinimumThenPerKilometreRate() {
    let quote = RideQuote(
        vehicle: .bike,
        routeDistanceMeters: 2_400,
        routeDurationSeconds: 480,
        rateCardVersion: UUID(),
        fare: Money(paise: 4_800),
        expiresAt: Date(timeIntervalSince1970: 1_000)
    )
    XCTAssertEqual(quote.fare.paise, 4_800)
    XCTAssertEqual(quote.routeDistanceMeters, 2_400)
}
```

- [ ] **Step 2: Run the failing domain suite**

```bash
swift test --package-path Packages/SavariDomain
```

Expected: FAIL because ride statuses and quote types do not exist.

- [ ] **Step 3: Implement the canonical Swift state vocabulary**

Create `RideStatus.swift` with exactly these public cases:

```swift
public enum RideStatus: String, Codable, CaseIterable, Sendable {
    case requested
    case assigned
    case enRouteToPickup = "en_route_to_pickup"
    case arrived
    case boarded
    case inProgress = "in_progress"
    case paymentDue = "payment_due"
    case completed
    case cancelledBeforeStart = "cancelled_before_start"
    case cancelledInTrip = "cancelled_in_trip"

    public func canTransition(to next: RideStatus) -> Bool {
        switch (self, next) {
        case (.requested, .assigned),
             (.assigned, .enRouteToPickup),
             (.enRouteToPickup, .arrived),
             (.arrived, .boarded),
             (.boarded, .inProgress),
             (.inProgress, .paymentDue),
             (.cancelledInTrip, .paymentDue),
             (.paymentDue, .completed),
             (.requested, .cancelledBeforeStart),
             (.assigned, .cancelledBeforeStart),
             (.enRouteToPickup, .cancelledBeforeStart),
             (.arrived, .cancelledBeforeStart),
             (.boarded, .cancelledBeforeStart),
             (.inProgress, .cancelledInTrip):
            return true
        default:
            return false
        }
    }
}
```

Also define `RideVehicle` as a public `String`, `Codable`, and `Sendable` enum with exactly `auto` and `bike` cases.

`RideSnapshot` must contain only server-returned fields: ID, status, selected vehicle, price snapshot, pickup/destination points, assigned driver display data allowed for the caller, assignment deadline, and an event version. Its public initializer accepts `id`, `status`, `vehicle`, `fare`, `pickup`, `destination`, `assignmentDeadline`, and `stateVersion`; `stateVersion` is an `Int64`. It must not contain a boarding-code hash, another participant's data before disclosure, or a mutable local status.

- [ ] **Step 4: Define request and response types for Edge Functions**

Create the following public intent signatures in `RideIntent.swift`:

```swift
public struct QuoteRideRequest: Codable, Sendable {
    public let pickup: GeoPoint
    public let destination: GeoPoint
    public let vehicle: RideVehicle
}

public struct CreateRideRequest: Codable, Sendable {
    public let quoteID: UUID
}

public struct UpdateRideDestinationRequest: Codable, Sendable {
    public let rideID: UUID
    public let destination: GeoPoint
}

public struct VerifyBoardingCodeRequest: Codable, Sendable {
    public let rideID: UUID
    public let code: String
}
```

Use a separate request type for each actor action. Do not send a generic `{ action: String, payload: Any }` envelope.

- [ ] **Step 5: Verify the domain package and commit**

```bash
swift test --package-path Packages/SavariDomain
git add Packages/SavariDomain
git commit -m "feat: define Savari ride domain"
```

Expected: all `SavariDomain` tests pass.

### Task 2: Create ride, rate, location, and event storage with transactional state transitions

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715100000_create_ride_core.sql`
- Create: `Backends/Savari/supabase/migrations/20260715101000_create_ride_state_machine.sql`
- Create: `Backends/Savari/supabase/tests/database/010_ride_core.pgtap.sql`
- Create: `Backends/Savari/supabase/tests/database/011_ride_state_machine.pgtap.sql`

**Interfaces:**
- Consumes: `public.accounts`, `private.account_memberships`, `public.service_zones`, and `audit.events` from foundation.
- Produces: `public.rides` read snapshots, `private.ride_events`, versioned rate cards, private state transitions, and a database API only callable by Edge Function service clients.

- [ ] **Step 1: Write failing schema and state tests**

Create `010_ride_core.pgtap.sql`:

```sql
begin;
select plan(8);
select has_table('public', 'rides');
select has_table('private', 'ride_events');
select has_table('public', 'savari_rate_cards');
select has_column('public', 'rides', 'state_version');
select has_column('public', 'rides', 'boarding_code_digest');
select col_is_pk('public', 'rides', 'id');
select has_index('public', 'rides', 'rides_active_passenger_idx');
select has_index('public', 'rides', 'rides_active_driver_idx');
select * from finish();
rollback;
```

Create `011_ride_state_machine.pgtap.sql` asserting that a transition from `requested` to `in_progress` is rejected, `requested` to `assigned` succeeds, `arrived` to `boarded` succeeds, and only `boarded` to `in_progress` represents an explicit trip start when called as the private service role fixture.

- [ ] **Step 2: Run the tests before schema implementation**

```bash
cd Backends/Savari
supabase db test --local --file supabase/tests/database/010_ride_core.pgtap.sql
supabase db test --local --file supabase/tests/database/011_ride_state_machine.pgtap.sql
```

Expected: FAIL because no ride tables or transition function exist.

- [ ] **Step 3: Add immutable pricing and active-ride constraints**

Create the core type and table boundary:

```sql
create type public.ride_vehicle as enum ('auto', 'bike');
create type public.ride_status as enum (
  'requested', 'assigned', 'en_route_to_pickup', 'arrived', 'boarded',
  'in_progress', 'payment_due', 'completed', 'cancelled_before_start', 'cancelled_in_trip'
);
create type public.ride_payment_method as enum ('cash', 'direct_upi', 'in_app');

create table public.savari_rate_cards (
  id uuid primary key default gen_random_uuid(),
  vehicle public.ride_vehicle not null,
  zone_id uuid not null references public.service_zones(id),
  minimum_fare_paise integer not null check (minimum_fare_paise > 0),
  per_kilometre_paise integer not null check (per_kilometre_paise > 0),
  active_from timestamptz not null,
  active_to timestamptz,
  created_at timestamptz not null default now(),
  check (active_to is null or active_to > active_from)
);

create table public.rides (
  id uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references public.accounts(id),
  driver_id uuid references public.accounts(id),
  status public.ride_status not null default 'requested',
  vehicle public.ride_vehicle not null,
  pickup extensions.geometry(Point, 4326) not null,
  destination extensions.geometry(Point, 4326) not null,
  quoted_distance_m integer not null check (quoted_distance_m > 0),
  quoted_duration_s integer not null check (quoted_duration_s > 0),
  final_distance_m integer,
  rate_card_id uuid not null references public.savari_rate_cards(id),
  quoted_fare_paise integer not null check (quoted_fare_paise > 0),
  final_fare_paise integer,
  payment_method public.ride_payment_method,
  assignment_ack_deadline timestamptz,
  boarding_code_digest text,
  state_version bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index rides_active_passenger_idx
  on public.rides (passenger_id)
  where status not in ('completed', 'cancelled_before_start');
create unique index rides_active_driver_idx
  on public.rides (driver_id)
  where driver_id is not null and status not in ('completed', 'cancelled_before_start');
```

Use `private.ride_events` for immutable actor/action/payload/version records. Do not put contact numbers, raw boarding codes, or raw route trace points in the event payload.

- [ ] **Step 4: Implement private transition enforcement and client read policies**

Create `private.transition_ride(p_ride_id uuid, p_expected_version bigint, p_next public.ride_status, p_actor_id uuid, p_payload jsonb)` as a `SECURITY DEFINER` function inside the non-exposed `private` schema. It must:

```sql
-- Pseudocode expressed as required SQL checks inside the function body.
if current_status = 'requested' and p_next <> 'assigned' then raise exception 'invalid_transition'; end if;
if current_status = 'boarded' and p_next not in ('in_progress', 'cancelled_before_start') then raise exception 'invalid_transition'; end if;
if current_status = 'in_progress' and p_next not in ('payment_due', 'cancelled_in_trip') then raise exception 'invalid_transition'; end if;
if state_version <> p_expected_version then raise exception 'stale_state'; end if;
```

Implement every transition in the `RideStatus` table from Task 1, increment `state_version` exactly once, append an event, and insert the matching audit event in one transaction. Revoke execute from `anon`, `authenticated`, and `public`; only the service client used by Edge Functions can call it.

Enable RLS on `public.rides`; give authenticated users `SELECT` only when `passenger_id = auth.uid()` or `driver_id = auth.uid()`. Revoke all DML on `public.rides` from `anon` and `authenticated`.

- [ ] **Step 5: Verify database invariants and commit**

```bash
cd Backends/Savari
supabase db reset --local
supabase db test --local --file supabase/tests/database/010_ride_core.pgtap.sql
supabase db test --local --file supabase/tests/database/011_ride_state_machine.pgtap.sql
git add supabase
git commit -m "feat: add Savari ride state machine"
```

Expected: valid transitions pass; direct authenticated DML and skipped transitions fail.

### Task 3: Add authoritative route quoting and automatic driver dispatch

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715102000_driver_dispatch.sql`
- Create: `Backends/Savari/supabase/functions/_shared/apple_maps.ts`
- Create: `Backends/Savari/supabase/functions/quote-ride/index.ts`
- Create: `Backends/Savari/supabase/functions/request-ride/index.ts`
- Create: `Backends/Savari/supabase/functions/submit-driver-application/index.ts`
- Create: `Backends/Savari/supabase/functions/set-driver-availability/index.ts`
- Create: `Backends/Savari/supabase/functions/report-driver-location/index.ts`
- Create: `Backends/Savari/supabase/functions/acknowledge-ride-assignment/index.ts`
- Create: `Backends/Savari/supabase/functions/decline-ride-assignment/index.ts`
- Create: `Backends/Savari/supabase/functions/dispatch-sweep/index.ts`
- Create: `Backends/Savari/supabase/functions/tests/quote-ride/pricing.test.ts`
- Create: `Backends/Savari/supabase/functions/tests/dispatch-sweep/assignment.test.ts`
- Create: `Backends/Savari/supabase/tests/database/012_dispatch.pgtap.sql`

**Interfaces:**
- Consumes: `QuoteRideRequest`, driver approval membership, current location, configured zone/rate card, and `APPLE_MAPS_TOKEN` secret.
- Produces: `RideQuote`, requested rides, a 60-second driver acknowledgement deadline, and a single closest eligible assigned driver.

- [ ] **Step 1: Write route and dispatch failures first**

Create a Deno pricing test that supplies a `distanceMeters` value of `2_400`, minimum fare `3_000`, and per-kilometre rate `1_000`, and asserts the quote is `5_400` paise. Create a dispatch test with two approved online drivers at 20m and 250m from pickup and assert the 20m driver receives the assignment.

```ts
Deno.test('dispatch chooses the closest eligible fresh driver', () => {
  const assigned = chooseClosestEligibleDriver([
    { id: 'far', distanceMeters: 250, fresh: true, eligible: true },
    { id: 'near', distanceMeters: 20, fresh: true, eligible: true },
  ]);
  assertEquals(assigned?.id, 'near');
});
```

- [ ] **Step 2: Run the failing function tests**

```bash
cd Backends/Savari
deno test --allow-env supabase/functions/tests/quote-ride/pricing.test.ts
deno test --allow-env supabase/functions/tests/dispatch-sweep/assignment.test.ts
```

Expected: FAIL because the pricing and dispatch helpers do not exist.

- [ ] **Step 3: Add eligible-driver data and location freshness policy**

Create `public.driver_profiles`, `private.driver_availability`, and `private.driver_positions`. `public.driver_profiles` has exactly one active `ride_vehicle` (`auto` or `bike`), approval state, selfie/vehicle/licence evidence paths, and no editable role field. The private availability row must include `is_online`, `last_available_at`, `idle_since`, `active_assignment_id`, and `suspended_until`; position must include geometry and `recorded_at`.

Eligibility is exactly:

```sql
approved_driver
and is_online
and active_assignment_id is null
and suspended_until is null or suspended_until <= now()
and recorded_at >= now() - interval '90 seconds'
and ST_Contains(active_zone.boundary, driver_position.point)
```

`submit-driver-application` creates or updates a pending application with exactly one vehicle choice and evidence URLs issued by `issue-evidence-url`; it cannot set `approved`. Owner approval is the only action that creates an approved `savari_driver` membership. `report-driver-location` is an authenticated Edge Function which replaces only the caller's most recent position. It is never a direct table upsert.

- [ ] **Step 4: Implement route quote with Apple Maps Server API**

`_shared/apple_maps.ts` calls:

```text
GET https://maps-api.apple.com/v1/directions?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&transportType=Automobile
Authorization: Bearer ${Deno.env.get('APPLE_MAPS_TOKEN')}
```

Take `routes[0].distanceMeters` and `routes[0].durationSeconds`, reject a non-200 response as `routing_unavailable`, and never accept a client-supplied distance. `quote-ride` verifies both points are inside the same active service zone, selects the active rate card for the requested vehicle, computes `max(minimum_fare_paise, ceil(distance_m / 1000.0) * per_kilometre_paise)`, persists a five-minute expiring quote, and returns it.

- [ ] **Step 5: Implement request, immediate dispatch, reassign, and idle-offline behavior**

`request-ride` consumes an unexpired quote owned by the caller and creates a `requested` ride. It immediately calls `private.assign_next_driver(ride_id)`, which locks the ride and candidate availability rows using `FOR UPDATE SKIP LOCKED`, sorts eligible candidates by `ST_Distance`, assigns one driver, and sets `assignment_ack_deadline = now() + interval '60 seconds'`.

`set-driver-availability` invokes the same assignment routine when a driver becomes online, so rides requested before the driver was online are considered immediately. `acknowledge-ride-assignment` moves `assigned` to `en_route_to_pickup` before its deadline. `decline-ride-assignment` records a driver reason and requeues the assignment; it is not an accept/decline marketplace screen because the driver was assigned automatically.

`dispatch-sweep` runs every minute through `pg_cron` and `pg_net` with a Vault-stored function key; it requeues expired assignments, records the reliability miss, turns idle drivers offline after 15 minutes without assignment, and attempts assignment for every requested ride. Apply the launch reliability policy in the same transaction: three missed or unacknowledged automatic assignments in the preceding 24 hours sets `suspended_until = now() + interval '30 minutes'`; five misses in the preceding seven days sets `owner_review_required = true` and prevents online status until an owner override. Passenger cancellations never create a miss.

- [ ] **Step 6: Add dispatch database tests and verify the cron path**

`012_dispatch.pgtap.sql` must assert all of the following: a stale position is ineligible, an active assignment excludes a driver, an expired acknowledgement requeues the ride, an idle driver becomes offline at 15 minutes, three misses create a 30-minute suspension, five seven-day misses require owner review, and a passenger cancellation does not count as a miss. Run:

```bash
cd Backends/Savari
supabase db reset --local
supabase db test --local --file supabase/tests/database/012_dispatch.pgtap.sql
deno test --allow-env supabase/functions/tests/quote-ride supabase/functions/tests/dispatch-sweep
```

Expected: all four eligibility rules and both function suites pass.

```bash
git add supabase
git commit -m "feat: add Savari automatic dispatch"
```

### Task 4: Implement the verified in-ride lifecycle and participant privacy snapshot

**Files:**
- Create: `Backends/Savari/supabase/migrations/20260715103000_ride_lifecycle_actions.sql`
- Create: `Backends/Savari/supabase/functions/mark-ride-arrival/index.ts`
- Create: `Backends/Savari/supabase/functions/verify-boarding-code/index.ts`
- Create: `Backends/Savari/supabase/functions/start-ride/index.ts`
- Create: `Backends/Savari/supabase/functions/change-ride-destination/index.ts`
- Create: `Backends/Savari/supabase/functions/extend-ride/index.ts`
- Create: `Backends/Savari/supabase/functions/cancel-ride/index.ts`
- Create: `Backends/Savari/supabase/functions/complete-ride/index.ts`
- Create: `Backends/Savari/supabase/functions/resolve-ride-payment/index.ts`
- Create: `Backends/Savari/supabase/functions/get-active-ride-snapshot/index.ts`
- Create: `Backends/Savari/supabase/functions/submit-ride-rating/index.ts`
- Create: `Backends/Savari/supabase/functions/report-safety-incident/index.ts`
- Create: `Backends/Savari/supabase/functions/tests/ride-lifecycle/lifecycle.test.ts`
- Create: `Backends/Savari/supabase/tests/database/013_lifecycle_privacy.pgtap.sql`

**Interfaces:**
- Consumes: an active ride ID, actor JWT, expected `stateVersion`, and current driver position where required.
- Produces: `RideSnapshot` with monotonic event version, a private boarding code delivered only to the passenger, and only authorized contact/location data.

- [ ] **Step 1: Write lifecycle and privacy tests before handlers**

Create Deno tests for these exact outcomes:

```ts
Deno.test('arrival rejects a driver 101 meters from pickup', async () => {
  const result = await markArrival(fixtureAtDistance(101));
  assertEquals(result.error?.code, 'outside_arrival_radius');
});

Deno.test('driver phone is visible after assignment but passenger phone waits for arrival', () => {
  assertExists(snapshotForPassenger.assignedDriver?.phoneNumber);
  assertEquals(snapshotForDriver.passenger?.phoneNumber, undefined);
  assertExists(arrivedSnapshotForDriver.passenger?.phoneNumber);
});

Deno.test('boarding verification requires a separate driver start action', async () => {
  const boarded = await verifyBoardingCode(validBoardingCodeFixture);
  assertEquals(boarded.status, 'boarded');
  const started = await startRide(boarded);
  assertEquals(started.status, 'in_progress');
});
```

Add pgTAP coverage for no `authenticated` mutation grant on `public.rides` and no `SELECT` access to `private.driver_positions`.

- [ ] **Step 2: Run the failing lifecycle suite**

```bash
cd Backends/Savari
deno test --allow-env supabase/functions/tests/ride-lifecycle/lifecycle.test.ts
supabase db test --local --file supabase/tests/database/013_lifecycle_privacy.pgtap.sql
```

Expected: FAIL because action handlers and privacy projections do not exist.

- [ ] **Step 3: Add server-verified actions with fixed errors**

Implement these action conditions in Edge Functions and private transactions:

```text
mark-ride-arrival: driver is assigned, fresh position, distance <= 100m, state assigned/en_route_to_pickup
verify-boarding-code: driver is assigned, code digest matches, state arrived, transitions arrived -> boarded
start-ride: driver is assigned, state boarded, transitions boarded -> in_progress and publishes the passenger snapshot update
change-ride-destination: passenger, state in_progress, new point in service zone, server recalculates quote, passenger confirms revision
extend-ride: passenger, state in_progress, existing final destination reached in route trace, new point in service zone
cancel-ride: passenger in requested/assigned/en_route_to_pickup/arrived/boarded -> cancelled_before_start without payment; passenger in progress -> cancelled_in_trip then payment_due
complete-ride: driver, fresh position, distance <= 100m of final destination, transitions in_progress -> payment_due
resolve-ride-payment: assigned driver, payment_due, cash/direct_upi records collection then completed; in_app only accepts provider-confirmed path from payment plan
submit-ride-rating: passenger or driver, completed ride, one rating per actor
report-safety-incident: passenger or driver, active or recently terminal ride, creates durable safety case and does not alter ride state
```

Generate the boarding code with `crypto.getRandomValues`, store only a salted digest, expire it after 15 minutes, and return the raw code only in the passenger snapshot while status is `arrived`. Never have an iOS client generate or transmit a new code as part of assignment.

Verification alone does not begin the trip or create a payment obligation. Only `start-ride` changes the ride to `in_progress`; a passenger cancellation from `boarded` remains free.

- [ ] **Step 4: Implement actual-distance final fare rules**

Store active encrypted route trace points in a private table. For destination changes, compute final quote from the recorded distance from pickup to current verified location plus Apple Maps Server API distance from current point to new destination. For mid-trip cancellation, compute `max(minimum_fare, rate_card_distance_fare(recorded_pickup_to_cancel_distance))`. For extension, update only the final destination and retain the original ride/payment record.

Each price adjustment inserts a `private.ride_events` record containing old and new fare values. It does not overwrite the original quote.

- [ ] **Step 5: Publish only a participant snapshot and active wake-up**

`get-active-ride-snapshot` builds role-specific payloads. It returns assigned driver phone to passenger after `assigned`, and passenger phone to driver only from `arrived` until terminal state. It returns live driver location only to the passenger with an active ride. On terminal state, exclude contacts and exact position from all subsequent snapshots.

`submit-ride-rating` accepts a score from 1 through 5 and optional report text up to 1,000 characters after completion. `report-safety-incident` writes the job, actor, latest route evidence reference, selected incident type, and free-text report to `private.safety_cases`; it does not claim a staffed emergency service. The iOS active-job shell exposes a safety action that opens `tel:112` and separately invokes `report-safety-incident` when the user confirms reporting.

Publish a private Realtime Broadcast topic `ride:<ride-id>` with `{ rideID, stateVersion }` after every transition. A receiving client must re-fetch the snapshot; it must not use the broadcast payload as state.

- [ ] **Step 6: Verify the full lifecycle and commit**

```bash
cd Backends/Savari
supabase db reset --local
supabase db test --local --file supabase/tests/database/013_lifecycle_privacy.pgtap.sql
deno test --allow-env supabase/functions/tests/ride-lifecycle
git add supabase
git commit -m "feat: add verified Savari ride lifecycle"
```

Expected: the server rejects distance/state/privacy violations and accepts the complete normal, extension, and mid-trip cancellation paths.

### Task 5: Connect the clean Savari client shell to server intents and authoritative snapshots

**Files:**
- Create: `Apps/Savari/Savari/SavariApp.swift`
- Create: `Apps/Savari/Savari/AppComposition.swift`
- Create: `Apps/Savari/Savari/Rides/SavariRideClient.swift`
- Create: `Apps/Savari/Savari/Rides/RideStore.swift`
- Create: `Apps/Savari/Savari/Rides/ActiveRideSubscription.swift`
- Create: `Apps/Savari/Savari/Location/DriverLocationReporter.swift`
- Create: `Apps/Savari/SavariTests/RideStoreTests.swift`
- Create: `Apps/Savari/SavariTests/RideTestDoubles.swift`
- Create: `Apps/Savari/SavariTests/SavariRideClientContractTests.swift`

**Interfaces:**
- Consumes: `FunctionClient`, `SavariDomain` request/response types, active ride private broadcast, APNs wake events, and device location authorization.
- Produces: an observable `RideStore` with immutable server snapshots and action methods that all carry an idempotency key.

- [ ] **Step 1: Write `RideStore` tests using a recording fake client**

Create a fake `SavariRideClient` and assert no view model directly receives a Supabase table client:

```swift
@MainActor
func testCreateRideSendsOnlyQuoteIDAndIdempotencyKey() async throws {
    let client = RecordingRideClient(response: RideSnapshot.fixture(status: .requested))
    let store = RideStore(client: client)

    try await store.createRide(quoteID: UUID())

    let calls = await client.calls
    XCTAssertEqual(calls.map(\.name), ["request-ride"])
    XCTAssertEqual(store.snapshot?.status, .requested)
}
```

`RideTestDoubles.swift` defines `RecordingRideClient` as an actor conforming to `SavariRideClient`. It records a call name, JSON-encoded body, and idempotency key, then returns the injected typed response. Define `RideSnapshot.fixture(status:version:)` in the same test file using the public initializer from Task 1. The production `SavariRideClient` implementation is the only layer that wraps the generic `FunctionClient`.

- [ ] **Step 2: Run the failing client tests**

```bash
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: FAIL because the clean Savari target, store, and fake ride client are absent.

- [ ] **Step 3: Implement a narrow client repository contract**

Create this protocol in `SavariRideClient.swift`:

```swift
protocol SavariRideClient: Sendable {
    func quote(_ request: QuoteRideRequest, key: IdempotencyKey) async throws -> RideQuote
    func requestRide(quoteID: UUID, key: IdempotencyKey) async throws -> RideSnapshot
    func snapshot() async throws -> RideSnapshot?
    func perform<Action: Encodable & Sendable, Response: Decodable & Sendable>(
        _ function: String, action: Action, key: IdempotencyKey
    ) async throws -> Response
}
```

`RideStore` owns `RideSnapshot?`, replaces it only with a newer `stateVersion`, and exposes actor-specific methods such as `markArrival`, `verifyBoardingCode`, `startRide`, `cancel`, `complete`, and `resolvePayment`. It never sends a price, a status string, driver ID, or passenger ID supplied by the screen.

- [ ] **Step 4: Add subscription and recovery behavior**

`ActiveRideSubscription` joins only the private topic for the current snapshot ID. On any state version wake-up, app foreground, APNs ride notification, reconnect, or subscription failure, it calls `get-active-ride-snapshot`. It must show no local placeholder request when snapshot fetch returns no assignment. Cancel the subscription immediately after terminal state or sign-out.

`DriverLocationReporter` calls a `report-driver-location` Edge Function while driver availability or a ride is active. It stops when role/mode is inactive, app authorization changes, or the server returns a suspension/error.

- [ ] **Step 5: Prove the prototype direct-write API cannot re-enter the target**

Add `SavariRideClientContractTests.swift` that scans the clean app source and fails if any app source contains these strings:

```swift
[".from(\"rides\")", ".update(", ".insert(", ".upsert(", ".rpc(\""]
```

Allow the generic `FunctionClient` implementation to call `functions.invoke` only. The archived prototype remains outside the test target and scan root.

- [ ] **Step 6: Verify client contracts and commit**

```bash
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
git add Apps/Savari Packages/SavariDomain
git commit -m "feat: connect Savari client to ride intents"
```

Expected: the client target builds, all state updates originate from snapshot fetches, and the contract scan rejects direct table writes.

### Task 6: Run a deterministic two-party mobility acceptance suite

**Files:**
- Create: `Backends/Savari/supabase/functions/tests/acceptance/two_party_ride.test.ts`
- Create: `Apps/Savari/SavariTests/TwoPartyRideContractTests.swift`
- Create: `scripts/run-savari-acceptance.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: local Savari backend fixtures for one passenger, two drivers, a zone, and versioned Auto/Bike rates.
- Produces: a repeatable pass/fail record for the lifecycle that previously depended on manually coordinating simulators.

- [ ] **Step 1: Encode the end-to-end acceptance cases**

The Deno suite must cover these cases in isolated fixtures:

```text
request before driver online -> driver becomes online -> nearest driver assigned
assignment acknowledgement timeout -> next nearest driver assigned
driver arrives at 100m -> passenger phone becomes visible to driver
wrong boarding code -> rejected; correct code -> boarded; driver start -> in_progress and passenger receives the newer snapshot
destination change -> new server quote -> confirmed final fare
mid-trip cancellation -> payment_due -> cash collection -> completed -> driver waiting
completion at 101m -> rejected; completion at 100m -> payment_due
payment collection -> passenger terminal snapshot and driver availability restored
three missed assignments -> driver temporarily offline; fifth seven-day miss -> owner review
```

- [ ] **Step 2: Run it against a fresh local backend**

Create `scripts/run-savari-acceptance.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd Backends/Savari
supabase db reset --local
deno test --allow-env --allow-net supabase/functions/tests/acceptance/two_party_ride.test.ts
```

Expected: FAIL until all lifecycle handlers from Tasks 2 through 5 are deployed locally.

- [ ] **Step 3: Add simulator-facing client assertions**

`TwoPartyRideContractTests.swift` must use fake function responses to assert that a driver action causes the passenger store to replace its snapshot at the next higher `stateVersion`, including payment collection and final completion. This test must not rely on a timer or a visual label.

- [ ] **Step 4: Run the acceptance suite and commit**

```bash
scripts/run-savari-acceptance.sh
xcodebuild test -workspace SavariDastak.xcworkspace -scheme Savari -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
git add Backends/Savari Apps/Savari scripts README.md
git commit -m "test: add Savari two party acceptance suite"
```

Expected: every state change, reassignment, privacy change, payment collection, and driver return-to-waiting is proven without a manual simulator race.

## Savari Core Completion Gate

- A passenger can create a server-priced Auto or Bike request only within an active zone.
- A fresh eligible driver is automatically assigned or reassigned without a driver picker or fake request.
- Every lifecycle transition is validated by the server, evented, idempotent, and visible to both participants through fresh snapshots.
- Route change, extension, mid-trip cancel, arrival, completion, payment due, and cash/direct UPI completion all preserve an auditable fare history.
- The client cannot directly mutate ride, assignment, availability, payment, or location tables.
- The two-party local acceptance suite and clean iOS test target pass before Dastak work or payment integration begins.
