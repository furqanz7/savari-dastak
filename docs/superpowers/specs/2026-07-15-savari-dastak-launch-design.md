# Savari And Dastak Launch Design

**Status:** Approved product design

**Date:** 2026-07-15

**Scope:** Native iOS launch for Vaniyambadi, Tamil Nadu, India. Savari provides immediate Auto and Bike rides. Dastak provides immediate local delivery. Both are designed for Tier 2 and Tier 3 South Asian markets, beginning with one controlled service area.

This document supersedes the narrower ride-only MVP direction in `docs/ride-lifecycle-mvp.md`. It is a product and technical design, not implementation work. UI and UX design are explicitly deferred until the product core and contracts below are stable.

## 1. Product Principles

- iOS only. Do not add Android, a web admin, or Vapor.
- Public marketplace: anyone can create a customer account immediately. Operational roles require owner approval.
- Immediate work only. No scheduled rides or deliveries at launch.
- 24/7 service availability within the owner-configured service area.
- Tamil and English from day one, following the device language. An in-app override can be added later.
- MapKit is the first maps provider.
- One active standalone ride or delivery assignment per relevant participant at a time. A permitted ride-linked Dastak collection is attached to its matching Savari ride and is treated as one composite assignment, not a second independent job.
- Server authority is mandatory for assignment, fare, trip state, payment, payout, approval, refund, and contact disclosure.

## 2. Applications And Backend Boundaries

The launch uses one repository and one Xcode workspace containing five native iOS app targets:

1. **Savari**: passenger mode and approved driver mode.
2. **Savari Admin**: the single full-access owner account.
3. **Dastak**: customer experience and approved Delivery Partner mode.
4. **Dastak Merchant**: approved merchant operations.
5. **Dastak Admin**: the single full-access owner account for Dastak.

The codebase may share focused Swift packages for domain types, networking, location, notifications, and observability. It must not share product data models indiscriminately or merge the apps into one oversized target. UI code is not a shared launch concern; it will be designed separately later.

Savari passenger navigation includes the Dastak customer gateway. Savari Driver mode exposes ride and eligible delivery work, not the Dastak customer catalogue. Dastak remains available as its own complete customer app.

There are two production Supabase projects:

- **Savari Supabase**: Savari identities, driver and passenger data, rides, location, service zones, rate cards, ride payments, and Savari Admin.
- **Dastak Supabase**: Dastak identities, Delivery Partners, merchants, catalogues, orders, deliveries, and Dastak Admin.

Each production project has a matching non-production project for TestFlight, payment sandbox work, provider configuration, and migration testing. Tests, seeds, sandbox payments, and experiments never use production data.

## 3. Identity, Accounts, And Roles

### 3.1 Sign-in and phone number

- Apple Sign In and Google Sign In are the only login methods at launch.
- Every user must add a phone number after sign-in.
- There is no paid SMS OTP dependency at launch. The phone is therefore not an authentication, account recovery, or payment-proof factor until an approved verification provider is added.
- A user may consent once to link their Savari and Dastak accounts. The link is created server-to-server and not by matching email or phone number, which avoids incorrect links from Apple private relay addresses or changed phone numbers.

### 3.2 Roles

- A new user is a customer by default.
- An approved Savari Driver has one active vehicle type: Auto or Bike.
- An approved Dastak Delivery Partner has one active declared method: walking, bicycle, Bike, or Auto. Bike and Auto require vehicle proof; walking and bicycle do not.
- An approved Savari Driver may also be eligible for Dastak work from Driver mode.
- A Dastak Delivery Partner is not automatically eligible to drive Savari rides.
- Merchants and pharmacies operate only after owner approval.
- The owner role is server managed in each project. Clients cannot set, elevate, or infer authorization from editable user metadata.

### 3.3 Contact privacy

- Passenger sees the assigned driver's phone number when the driver is assigned.
- Driver sees the passenger's phone number only after the server verifies that the driver has arrived within the pickup threshold.
- Participant contact data is never broadly queryable and is hidden again when the active job ends.

## 4. Savari Ride Product

### 4.1 Ride request and fare

- Passenger chooses pickup and destination within the owner-configured service area.
- The only ride types are Auto and Bike.
- The passenger sees a fixed upfront fare using a minimum fare plus a per-kilometre rate card for the selected vehicle type.
- No surge pricing, wait-time pricing, or time-based pricing is included at launch.
- Rate cards are owner configurable and versioned so a completed ride retains the rate that applied when it was priced.

### 4.2 Automatic assignment

- Savari automatically assigns the closest eligible online driver. There is no driver picker and no driver accept screen.
- Eligibility includes approved status, active vehicle type, online state, current location freshness, no active assignment, service-area fit, and reliability status.
- The assigned driver has 60 seconds to acknowledge navigation. A missed acknowledgement, driver cancellation, stale location, loss of eligibility, or timeout triggers automatic reassignment to the next eligible closest driver.
- A request made before a driver goes online remains matchable. When an eligible driver becomes online, the server considers the request in the same matching process.
- The passenger sees only verified server assignment state. The driver never receives fake local requests.
- Driver availability automatically turns off after 15 minutes without an assignment. A driver cannot manually go offline while assigned or in an active ride.

### 4.3 Ride lifecycle

The canonical lifecycle is typed and state-machine controlled. The exact storage representation can evolve, but it must preserve these meanings:

```text
requested
  -> assigned
  -> en_route_to_pickup
  -> arrived
  -> boarded
  -> in_progress
  -> payment_due (cash or direct UPI only, when needed)
  -> completed
```

Exceptional paths:

```text
requested or assigned or en_route_to_pickup -> cancelled_before_start
in_progress -> cancelled_in_trip -> payment_due -> completed
```

Rules:

- Before the passenger shares the boarding code, cancellation is free and no payment is collected.
- Driver can mark arrival only within 100 metres of pickup. The backend enforces the threshold using the latest trusted driver location.
- Passenger shares a unique boarding code. Driver enters it; the server verifies it before the ride can start.
- No fare is collected before the boarding code is verified and the ride has begun.
- Driver can complete only within 100 metres of the final destination.
- Passenger may cancel during a trip. The fare is recalculated from pickup to the cancellation location, subject to the minimum fare. Driver sees a payment-collection state and returns to waiting only after payment is resolved.
- Passenger may change the destination after the trip begins. The new destination must remain inside the service area; no driver approval is needed. The server recalculates fare using distance already travelled plus remaining route distance, and passenger confirms the revised fixed fare.
- If the passenger reaches the destination before the driver completes, the passenger may extend the trip to another service-area destination. It remains one ride and one final payment, not a new pickup.
- Passenger and driver can rate and report after completion. Active jobs include a safety action that initiates an emergency call to 112 and preserves a server-side incident record. Savari does not claim staffed emergency dispatch.

### 4.4 Ride payment methods

- Cash and direct UPI are settled directly between passenger and driver. The driver keeps 100 percent, and Savari earns no commission.
- In-app payment is offered after the ride has started and is finalized using the actual terminal fare. If in-app collection fails, the job remains `payment_due` and cash or direct UPI can be used as a fallback.
- Savari deducts its configurable commission only from verified in-app ride earnings. Launch default: 10 percent.

## 5. Dastak Delivery Product

### 5.1 Delivery types

Dastak supports all three delivery models at launch:

1. **Person-to-person parcel**: sender prepays the delivery fee in-app. There is no cash on delivery. Sender provides a pickup code and recipient provides a delivery code.
2. **Merchant order**: customer pays item amount and delivery fee in-app before assignment. Merchant accepts the order, sets preparation state, and marks it ready. Courier matching begins only after ready state.
3. **Collect with my Savari ride**: passenger purchases a merchant order in Dastak, then chooses this option only inside Dastak opened from Savari navigation while that passenger already has a matched Savari ride.

Standalone Dastak does not offer "Collect with my Savari ride." The feature is never available to an unrelated passenger or a passenger without a current matched ride.

### 5.2 Partner assignment and delivery state

- Dastak auto-assigns the closest eligible Delivery Partner using the same 60-second acknowledgement, reassignment, freshness, and reliability rules as Savari.
- Delivery rate cards use a minimum fare plus a per-kilometre rate, with separate owner-configurable rates for walking, bicycle, Bike, and Auto.
- A Delivery Partner receives the defined courier payout for the job. A Savari Driver who performs an eligible Dastak task receives that same courier payout in addition to any separate ride earnings.
- Merchant orders have an explicit merchant acceptance and ready state. Partners do not wait at a merchant before the merchant marks the order ready.
- Parcel and merchant delivery terminal states require server-verified pickup and delivery evidence, including handoff codes where applicable.

### 5.3 Ride-linked Dastak collection

- The merchant order must be paid and ready before the passenger can attach it to a ride.
- Before passenger pickup, the added merchant pickup is permitted only when the predicted pickup delay is at most five minutes.
- After passenger boarding, only the current passenger's own purchase may add a stop. No unrelated delivery can be added while a passenger is aboard.
- The merchant item amount and Dastak delivery fee remain Dastak payments. Savari ride payment remains independent. The driver can earn both amounts, but the payout rule is shared.

### 5.4 Merchant refunds

- Full refund until merchant acceptance.
- After merchant acceptance, refund only when the merchant cannot fulfil the order or the owner approves it.
- After courier pickup, delivery fee remains unless Dastak or merchant fault caused the failure.
- Refunds are tied to immutable payment and order events. They are never represented as a silent edit to order state.

### 5.5 Controlled categories

- Dastak is designed for lawful goods that fit the declared transport method. Sender declares contents and value. High-value or special goods have owner-configured controls.
- Medicine supports both OTC and prescription orders through owner-approved licensed pharmacies. The product captures and verifies prescription evidence when required, keeps invoice and fulfilment records, and excludes controlled drugs without an approved compliance flow.
- Paan Corner is a Dastak category for owner-approved, non-electronic tobacco products. Tobacco delivery requires a current 18+ self-confirmation, a versioned terms acknowledgement, merchant and delivery locations outside owner-maintained 91.44m school/college exclusion zones, and a Delivery Partner visual age check before handoff. E-cigarettes and vaping products are not in scope.
- Medicine and Paan Corner remain product scope. Before Paan Corner is released, the owner must complete merchant and product compliance evidence review, exclusion-zone coverage, age and handoff test evidence, applicable business/distribution review, and a documented current Apple App Review risk review. This is a release gate, not a scope removal or a guarantee of App Review approval. It must not be implemented as a concealed or generic runtime-activated capability.

## 6. Payments, Payouts, And Settlement

### 6.1 Razorpay Route

- One company Razorpay Route account is used for in-app marketplace payments and transfers.
- Drivers, Delivery Partners, and merchants are onboarding-controlled linked accounts. Their payout bank details, KYC material, and Razorpay identifiers are server-only.
- Backend services create orders, verify webhooks, calculate shares, hold and release transfers, process reversals, and reconcile failures. iOS clients do not hold Razorpay secret credentials and cannot create a payout.

### 6.2 Revenue model

- Cash/direct UPI Savari rides: driver keeps 100 percent; Savari earns no commission.
- In-app Savari rides: platform commission is configurable; launch default is 10 percent of verified in-app earnings.
- Dastak merchant orders: Dastak deducts a configurable merchant commission from item sales and retains a configurable part of the delivery fee. Partner gets the defined courier payout.
- Dastak parcels: customer prepays delivery fee and the partner gets the defined courier payout.

### 6.3 Global rolling holdback

All in-app Driver and Delivery Partner earnings use one cross-product payout rule:

1. A completed in-app earning becomes `pending`.
2. The next completed eligible job, including cash, direct UPI, in-app Savari, or Dastak work, releases all prior pending in-app earnings to `withdrawable`.
3. The newest in-app earning remains pending until a subsequent completed eligible job.
4. If no subsequent job occurs, the pending earning automatically releases and triggers payout after 24 hours.
5. A partner may withdraw an already released earning before the automatic 24-hour payout.

Savari and Dastak payments stay in their own product projects. A single private Settlement Coordinator in the Savari project holds only payout identity, source event references, earnings, transfer state, and the cross-product release decision. Dastak sends minimal HMAC-signed, idempotent completion events to it. There is no client-side cross-project write and no cross-project service role key in an app.

### 6.4 Payment authority and failure handling

- Payment provider webhooks, not client callback screens, are final payment and transfer authority.
- Every provider event is deduplicated using an immutable event identifier.
- Transfer and payout states are explicit: `pending`, `withdrawable`, `created`, `processing`, `paid`, `failed`, `reversed`, and `adjusted`.
- A post-payout dispute or refund creates an adjustment or approved reversal; it does not rewrite completed financial history.

## 7. Data, Security, And Location

### 7.1 State and server authority

- Each ride, order, delivery, payment, refund, and payout has a typed state machine and an append-only event stream.
- Client applications send intents. Edge Functions or private database code validate current state, actor, location, payment condition, and idempotency before one transaction changes state.
- Assignment, fare calculation, contact disclosure, start code validation, completion distance, payment, refund, approval, and payout are never direct client table updates.

### 7.2 Supabase security model

- Enable RLS on every exposed table in both projects. Policies grant only the participant, approved business role, or owner access required for the current state.
- Keep privileged database functions in non-exposed schemas. Do not expose security-definer functions through the public API.
- Use server-managed role membership and app metadata only. Never trust user-editable metadata for authorization.
- Keep service keys, Razorpay credentials, bridge secrets, Apple/Google provider secrets, APNs credentials, and owner-only operations in Edge Function secrets.
- Use private Realtime channels for active job state; participants can join only the topic for their active job. Push notifications wake the app, which re-fetches authoritative server state.

### 7.3 Storage and documents

- Driver, partner, merchant, pharmacy, prescription, receipt, age-check, and payout evidence use private storage buckets with narrow RLS policies and short-lived signed access URLs.
- Existing Savari Driver document storage uses the owner path `driver_docs/<auth.uid()>/<filename>` and must retain private-bucket, user-folder, `SELECT`, `INSERT`, and `UPDATE` coverage for upsert support.
- Merchant catalogue images can use a separate public-read bucket. Sensitive evidence never shares that bucket.

### 7.4 Location and privacy

- Exact live location is visible only to active job participants and only for the active job purpose.
- Exact route traces are retained for 90 days for safety and dispute handling, then deleted or irreversibly coarsened.
- Driver location freshness is required for online eligibility and distance-enforced status changes.
- Active contact and location data disappear from normal participant queries after terminal job state.

## 8. Owner Operations, Safety, And Trust

### 8.1 Owner apps

- Savari Admin and Dastak Admin are distinct native iOS apps for one full-access owner account.
- Sensitive actions require recent sign-in and record actor, reason, before/after values, and timestamp in an immutable audit log.
- Savari Admin controls drivers, vehicles, zones, rate cards, commission, ride refunds, suspensions, live trips, and incidents.
- Dastak Admin controls Delivery Partners, merchants, pharmacies, product controls, margins, commissions, refunds, delivery incidents, and merchant operations.

### 8.2 Approval and reliability

- Drivers, Delivery Partners, merchants, and pharmacies stay inactive until owner approval.
- Approval includes the relevant identity, selfie, vehicle, bank/payout, licence, merchant, pharmacy, and agreement evidence.
- Launch reliability defaults: three missed or unacknowledged automatic assignments in 24 hours causes a 30-minute forced offline period. Five in seven days requires owner review to return online. Passenger cancellations do not count.
- The owner may change the thresholds or override a suspension, with an audit reason.

### 8.3 Safety and support cases

- Active ride and delivery incidents create a durable safety case containing job, participant, event, and route evidence.
- Emergency action calls 112. The product does not claim a staffed emergency dispatch operation.
- Payout failures, stuck orders, repeated matching failures, expired documents, safety reports, and payment disputes create durable operational alerts rather than relying on a transient push notification.

## 9. Build Sequence

Implementation is deliberately divided into vertical slices. Each slice is complete only when its server authority, security, failure behavior, and two-sided state are verified.

1. **Foundation**: workspace boundaries, non-production projects, provider configuration, account linking, roles, approvals, service zones, rate cards, typed state definitions, migration baseline, RLS, private storage, and audit plumbing.
2. **Savari core**: request, automatic match and reassign, driver acknowledgement, arrival, boarding code, trip start, route change/extension, cancellation, payment resolution, completion, and live participant updates.
3. **Dastak core**: Delivery Partner approval, parcel delivery, merchant acceptance/ready states, delivery codes, delivery payouts, refunds, and controlled-category evidence paths.
4. **Cross-product bridge**: linked account model, Dastak inside Savari navigation, ride-linked collection eligibility, signed bridge events, and global settlement coordinator.
5. **Payments and owner operations**: Razorpay Route, webhooks, transfer holds/releases, withdrawal, refunds/reversals, Admin app capabilities, safety cases, and operational alerts.
6. **UI and UX design**: separately designed after the contracts above are stable. The existing Savari full-screen MapKit and translucent state-card language is a reference, not a mandate to preserve current implementation structure.
7. **Release hardening**: localization, accessibility, push notifications, recovery from app restart and network loss, analytics/observability, TestFlight, and pilot readiness.

## 10. Verification And Release Gates

Every slice requires:

- Fresh database setup and upgrade migration tests.
- RLS and storage-policy tests using each relevant authenticated role.
- State-machine, fare, service-area, distance-threshold, assignment, and idempotency tests.
- Integration tests for Edge Functions, signed bridge calls, webhook replay, and failure retry.
- Multi-user simulator tests, including app backgrounding, app restart, delayed Realtime, lost network, duplicate notifications, and duplicate payment events.
- Razorpay sandbox tests before live credentials are configured.
- No privileged action usable through a direct client table update.

Pilot launch gates:

- Vaniyambadi service area configured and verified.
- Small manually approved group of drivers, Delivery Partners, merchants, and pharmacies.
- Apple and Google sign-in, APNs, Maps, and Razorpay Route production configuration verified.
- Current regulatory, distribution, and App Review risk checks completed for pharmacy and Paan Corner activation, including the adult, exclusion-zone, and handoff controls.
- All owner controls, audit events, refund paths, safety reporting, and payout reconciliation tested in non-production.
- TestFlight builds installed and validated by two-sided testers.

## 11. External References To Revalidate Before Implementation

- [Razorpay Route](https://razorpay.com/docs/payments/route/?preferred-country=IN)
- [Razorpay transfers to linked accounts](https://razorpay.com/docs/payments/route/transfer-funds-to-linked-accounts/?locale=en-US)
- [Razorpay webhooks](https://razorpay.com/docs/webhooks/)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Edge Function secrets](https://supabase.com/docs/guides/functions/secrets)
- [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
- [Supabase Realtime authorization](https://supabase.com/docs/guides/realtime/authorization)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [CDSCO doorstep drug delivery notification](https://cdsco.gov.in/opencms/resources/UploadCDSCOWeb/2022/drug_rules/DR_G.S.R.%20220%28E%29%20dt_26.03.2020_Doorstep%20delivery%20of%20the%20drugs%20by%20retail%20_Section%2026B.pdf)

## 12. Explicit Deferrals

- Detailed UI and UX design, including visual language, navigation layout, screen-level copy, and component specifications.
- Android and web apps.
- Scheduled rides and scheduled deliveries.
- Surge pricing, wait-time pricing, promotions, subscriptions, and loyalty programmes.
- Phone OTP authentication until a suitable provider and budget are available.
- Any uncontrolled expansion outside the configured service area.
