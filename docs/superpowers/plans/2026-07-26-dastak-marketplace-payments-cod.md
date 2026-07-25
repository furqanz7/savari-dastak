# Dastak Marketplace Payments And COD Implementation Plan

**Status:** Approved scope, queued for implementation. This document is planning only.

**Goal:** Add production-grade prepaid online payment, UPI payment on delivery,
physical cash on delivery, merchant payment guarantees, rider exposure controls,
cash remittance, refundable security deposits, reconciliation, and incident
handling to Dastak's direct merchant-to-customer marketplace.

**Scope:** Dastak merchant and restaurant orders across restaurants, groceries,
pharmacies, local retail, and other approved merchant categories. Dastak has no
dark-store operating model. Person-to-person parcels remain prepaid-only.
Ride-linked merchant orders use these payment rules only after the Savari-Dastak
bridge also reserves the worker's combined exposure.

**Supersedes:** The prepaid-only and no-COD constraints in the original Dastak
delivery-core plan. Immediate delivery remains unchanged; scheduled delivery is
still deferred.

## 1. Existing Modules To Reuse

- Merchant catalogue, quote, order, line-item, refund, and lifecycle migrations.
- Delivery Partner onboarding, availability, dispatch, and assignment lifecycle.
- Secure pickup and delivery handoff-code infrastructure.
- Existing merchant-order payment records, provider-event deduplication, balanced
  ledger transactions, and immutable ledger entries.
- `dastak-payments`, `razorpay-webhook`, `payment-ledger`,
  `merchant-orders`, and `courier-dispatch` Edge Functions.
- Customer, Merchant, Delivery Partner, and Admin web applications.
- Shared authentication, idempotency, HTTP, typed client, audit, service-zone,
  PostGIS, evidence-storage, and Razorpay helpers.
- Dastak native iOS authentication shells and shared MarketplaceInfrastructure
  clients, which will be extended rather than replaced.

## 2. Non-Negotiable Business Rules

### 2.1 Payment eligibility

Evaluate limits against the final authoritative customer-payable total, including
items, packaging, delivery, platform fees, taxes, discounts, and approved
adjustments.

- Prepaid online: available for every otherwise eligible order.
- Physical cash on delivery: initial maximum 25,000 paise (INR 250).
- UPI on delivery: initial maximum 75,000 paise (INR 750).
- Above 75,000 paise: prepaid online only.
- UPI on delivery is not labelled or represented as cash on delivery.
- All money is stored as integer paise. Floating-point money is prohibited.
- Limits are centrally configurable, owner-managed, versioned, and snapshotted
  onto each order.

Initial configuration:

```text
cod_maximum_paise = 25000
upi_on_delivery_maximum_paise = 75000
security_deposit_tiers_paise = [25000, 50000, 75000]
new_rider_maximum_active_pay_on_delivery_orders = 1
```

### 2.2 Merchant guarantee

Merchant settlement becomes guaranteed only after verified pickup:

1. The assigned rider is within the configured merchant geofence.
2. The merchant has marked the order ready.
3. The merchant verifies the assigned rider.
4. The rider scans a merchant-generated QR or enters a one-time pickup PIN.
5. The merchant confirms the correct sealed package was handed over.
6. The server records order, merchant, rider, GPS, device, timestamp, and method.

After verified pickup, merchant payment is independent of rider cash remittance.
The merchant remains payable if the rider disappears, fails to remit cash, loses
or damages the package after pickup, or the customer refuses without valid
merchant fault.

Only documented merchant fault, prohibited goods, fraud or collusion, handoff to
an unverified person, or a legal hold may hold or adjust the guarantee. Every
hold or adjustment requires evidence, an audit event, and an immutable reversing
financial entry.

### 2.3 Customer verification and completion

The first recipient code is named **Customer Verification PIN**. It proves that
the rider met the authorised recipient at the delivery location. It does not:

- mark the order delivered;
- trigger merchant settlement;
- release rider earnings;
- mark cash remitted; or
- close the delivery task.

Canonical destination flow:

```text
rider arrived
-> customer geofence verified
-> Customer Verification PIN verified
-> payment requested/confirmed
-> package handed over
-> delivery completed
```

PINs are server-generated, stored only as salted hashes, expire, have retry and
rate limits, lock after the configured failure count, and create audit events.

### 2.4 Payment-method flows

**Prepaid online**

```text
provider payment confirmed
-> merchant receives order
-> merchant accepts/prepares/marks ready
-> verified pickup
-> customer receipt verification
-> delivery completed
-> merchant and rider settle independently
```

An unpaid prepaid order cannot enter merchant preparation unless the selected
provider explicitly supports and the server records an authorised asynchronous
payment state.

**UPI on delivery**

```text
rider arrived
-> Customer Verification PIN verified
-> server creates exact-amount, order-bound payment intent
-> customer pays platform dynamic QR
-> signed provider webhook confirms payment
-> rider receives realtime confirmation
-> package handoff
-> delivery completed
```

- Never use a rider's personal UPI ID or QR.
- Screenshots and rider-entered success are never payment proof.
- Client polling may refresh state but is never final authority.
- Provider events require signature verification, replay protection,
  idempotency, unique event IDs, late-event handling, and reconciliation.
- The QR/payment intent has a configurable expiry.
- No handoff occurs until the backend confirms payment.

**Physical cash on delivery**

```text
rider arrived
-> Customer Verification PIN verified
-> authoritative exact cash amount displayed
-> rider confirms cash collected
-> customer confirms payment and receipt
-> rider cash liability recorded
-> delivery completed
```

The rider cannot reduce the amount. Any amount change must use an authorised,
audited order-adjustment workflow for unavailable items, approved substitutions,
weighed items, merchant-approved item cancellation, or platform correction.

## 3. Required Domain And Database Changes

Reuse and extend existing entities where they already provide the same invariant.
Add the equivalent of the following only where missing:

- Versioned payment-policy configuration and historical order-policy snapshots.
- Explicit fulfilment, payment, merchant-settlement, rider-account, remittance,
  incident, and appeal state machines.
- Order payment method, final-payable breakdown, and authorised adjustments.
- Payment intents and immutable provider events for prepaid and UPI-on-delivery.
- Pickup verifications and Customer Verification PIN records.
- Merchant payment guarantees, settlement ledger, settlement batches, payout
  attempts, bank references, holds, and adjustments.
- Rider cash ledger, rider earnings ledger, and platform cash-remittance records.
- Refundable rider security-deposit accounts and immutable deposit ledger.
- Rider risk limits, exposure reservations, active exposure projections, and
  assignment restrictions.
- Incidents, evidence, decisions, deposit actions, compensation, and appeals.
- Reconciliation cases and immutable configuration/audit history.

Financial truth must come from append-only balanced journals, not mutable order
columns. Corrections use reversing entries. Every ledger entry records:

- unique ID and transaction/journal ID;
- owner/account;
- order where applicable;
- account code, direction, amount in paise, and INR currency;
- reference type and ID;
- idempotency key;
- actor/system source;
- timestamp and metadata.

At minimum, journals cover customer payment clearing, rider cash receivable,
platform bank/cash, merchant payable, rider payable, refunds, platform revenue,
security-deposit liability, losses, holds, and reversals.

## 4. Explicit State Machines

Fulfilment states:

```text
created
merchant_pending
merchant_accepted
preparing
ready_for_pickup
rider_assigned
rider_at_merchant
pickup_verification_pending
picked_up
in_transit
rider_arrived
customer_verified
payment_pending
payment_confirmed
delivered
delivery_failed
return_required
returned
cancelled
```

Payment states:

```text
pending
requires_action
processing
paid
failed
partially_refunded
refunded
cash_due
cash_collected
cash_remittance_pending
cash_remitted
```

Merchant settlement states:

```text
not_eligible
guaranteed
scheduled
processing
paid
held
adjusted
failed
```

Rider states:

```text
pending_onboarding
active
cod_restricted
assignment_restricted
suspended
under_investigation
offboarded
```

Cash-remittance states:

```text
initiated
pending
confirmed
failed
rejected
reversed
```

Only domain services and transactional database functions may perform valid
transitions. Clients submit intents and cannot update these states directly.

## 5. Rider Deposit And Exposure Controls

### 5.1 Refundable deposit

Initial deposit tiers are 25,000, 50,000, and 75,000 paise. A deposit is a
refundable rider liability, never platform revenue. Track required, paid,
available, held, deducted, and refunded amounts; payment and refund references;
receipts; timestamps; and reasons.

A complaint, delay, refusal, accident, damage allegation, delayed payment, or
unverified non-delivery claim cannot automatically deduct the deposit.

Deduction workflow:

1. Open incident.
2. Collect evidence.
3. Notify rider.
4. Allow rider response.
5. Admin reviews.
6. Determine responsibility.
7. Calculate actual compensable loss.
8. Approve deduction.
9. Post ledger entry.
10. Send reasoned decision.
11. Keep appeal available.

This workflow is configurable and remains subject to jurisdiction-specific legal
review.

### 5.2 Separate exposure calculations

```text
cash_exposure =
  confirmed_cash_collected
  - confirmed_cash_remittances
  - authorised_system_offsets

goods_exposure =
  value_of_picked_up_unpaid_orders_not_completed_or_returned

combined_exposure = cash_exposure + goods_exposure
```

Per-rider controls:

- maximum physical COD amount;
- maximum UPI-on-delivery amount;
- maximum cash, goods, and combined exposure;
- maximum active pay-on-delivery orders;
- allowed merchant and product-risk categories;
- high-value permission;
- COD eligibility state.

Initial tiers:

| Tier | Deposit | Max COD order | Cash exposure | Goods exposure | Combined exposure | Active POD |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| New | 25,000 | 25,000 | 25,000 | 25,000 | 25,000 | 1 |
| Established | 50,000 | 25,000 | 50,000 | 50,000 | 50,000 | Configured |
| Trusted | 75,000 | 25,000 | 75,000 | 75,000 | 75,000 | Configured |

Trusted riders may be configured for UPI-on-delivery orders up to 75,000 paise.
A lower-deposit rider does not become eligible merely because payment will use
UPI. Assignment must atomically reserve goods exposure and, for COD, expected
cash exposure. Concurrent assignments must not exceed any limit.

## 6. Cash Remittance And Restrictions

Initial release uses gross remittance:

```text
cash collected = full customer cash amount
rider remits = full collected amount
rider earnings = paid separately
```

Riders never retain or calculate their own commission from collected cash.
Future system-calculated netting is disabled by default and requires an explicit
versioned policy.

Remittance providers are abstracted and may support approved platform UPI, bank
transfer, authorised collection points, local operations hubs, or approved cash
management partners. Each remittance records identity, rider, amount, method,
reference, evidence, timestamps, status, approver, and balanced ledger entries.

When cash limits are reached, disable new physical COD assignments while allowing
only jobs that fit other exposure limits. After an overdue deadline and grace
period: remind, notify, restrict COD, restrict all assignments, open a
reconciliation case, and escalate operations. Merchant settlement is unaffected.

If a rider disappears after pickup: freeze new assignments, reassign uncollected
work, preserve route/device/handoff evidence, open an incident, protect merchant
settlement, resolve customer refund/replacement, and record any platform loss.
Recovery from earnings or deposit requires an approved incident decision.

## 7. Backend Service Boundaries

Create or adapt these focused domain services:

- PaymentPolicyService
- PaymentIntentService and PaymentWebhookService
- PickupVerificationService and CustomerVerificationService
- DeliveryCompletionService
- RiderExposureService
- RiderCashLedgerService and RiderEarningsService
- CashRemittanceService
- MerchantGuaranteeService and MerchantSettlementService
- SecurityDepositService
- IncidentManagementService
- RefundService
- ReconciliationService
- AuditService

All public mutations require role checks and idempotency where retries are
possible. Use transactions, row/advisory locks, unique constraints, and exposure
reservations to prevent double pickup, delivery, cash collection, guarantee,
settlement, refund, remittance, and concurrent over-assignment.

Provider integration remains replaceable:

```text
createPaymentIntent
getPaymentStatus
refundPayment
verifyWebhook
```

Razorpay is the first production adapter. A deterministic mock adapter must
support success, pending, failure, timeout, duplicate webhook, invalid signature,
expiry, and late confirmation.

## 8. Role Interfaces

### Customer

- Checkout shows only eligible payment methods and explains each clearly.
- Show authoritative total, method, Customer Verification PIN, payment status,
  receipt, refund status, and support.
- UPI QR remains hidden until rider arrival and PIN validation.
- Prepaid, UPI-on-delivery, and cash confirmation states recover after refresh,
  restart, delayed webhook, and network loss.

### Delivery Partner

- Before arrival: method, amount, order value, cash/goods exposure, remaining
  capacity, and required remittance.
- UPI on delivery: platform QR, exact amount, waiting/confirmed state, and explicit
  safe-to-handover state.
- Cash: exact amount, rider collection confirmation, and customer confirmation.
- Wallet separates earnings, platform cash held, remittance, refundable deposit,
  incident holds, COD capacity, and goods exposure.

### Merchant

- Accept, prepare, mark ready, verify rider, generate pickup QR/PIN, and confirm
  sealed-package handover.
- After pickup show `Payment Guaranteed`, net settlement, expected date, status,
  bank reference, and settlement-adjustment dispute path.
- Never expose internal rider-remittance status to merchants.

### Admin and operations

- Versioned payment-policy editor and per-rider risk-limit editor.
- Cash exposure, goods exposure, overdue remittance, restriction, and zone totals.
- Merchant guarantee, settlement batches, payout retries, holds, and adjustments.
- Reconciliation across orders, intents, webhooks, cash, remittances, ledgers,
  merchant settlements, and refunds.
- Incident evidence, timeline, responsibility, financial impact, compensation,
  deposit action, decision, and appeal.
- Permission levels, recent reauthentication, and immutable audit reasons for
  sensitive actions.

Implement these interfaces in all four Dastak web experiences first, then provide
the same authoritative workflows in Dastak customer/partner, Merchant, and Admin
native iOS targets.

## 9. Refund Rules

- Refunds never depend on a rider personally returning physical cash.
- Supported configured methods include customer wallet credit, bank transfer,
  approved provider UPI refund/payout, or another audited provider method.
- Every refund records reason, amount, order, responsible party where determined,
  approver where required, settlement impact, and immutable journal entries.
- Refunds after merchant guarantee create liability/adjustment entries without
  silently deleting the merchant guarantee or rewriting paid history.

## 10. Notifications, Security, And Observability

Add notification hooks for payment request/confirmation, cash confirmation,
delivery, refund, rider assignment/arrival, pickup guarantee, settlement,
exposure/remittance restrictions, incidents, deposit decisions, and operations
alerts.

Security controls:

- merchant and customer geofence enforcement;
- hashed expiring PINs with retry/rate limits;
- device history/binding and suspicious-route hooks;
- signed provider webhooks, replay protection, and event deduplication;
- server-authoritative financial states and strict role access;
- no hard deletion of financial records;
- administrator permission levels and recent-auth checks;
- masked personal and banking data;
- no provider secrets in clients;
- duplicate-account, device-risk, and bank-risk hooks.

Structured logs, metrics, and correlation IDs cover orders, tasks, payment
intents/events, ledgers, settlements, incidents, and refunds. Track COD volume,
UPI-on-delivery success/latency, rider-held cash, overdue cash, default rate,
goods exposure, guaranteed settlement value, settlement failure, refusal,
disappearance, deposit deductions, refunds, webhook failures, and reconciliation
mismatches.

## 11. Testing And Acceptance Matrix

Test-first coverage must include policy eligibility, integer-money arithmetic,
state transitions, merchant guarantee, exposure calculations, deposits and
reversals, webhook security/idempotency, remittance, settlement, refunds,
concurrent assignment, and complete role-to-role flows.

Required deterministic scenarios:

1. Wrong Customer Verification PIN.
2. Expired PIN.
3. Customer refuses PIN.
4. Delayed UPI webhook.
5. Fake payment screenshot has no effect.
6. Duplicate webhook.
7. Payment succeeds after QR expiry.
8. Delivery attempted before payment.
9. Cash confirmed twice.
10. Customer and rider dispute cash payment.
11. Rider does not remit.
12. Rider reaches COD exposure limit.
13. Concurrent assignments would exceed exposure.
14. Rider disappears after pickup.
15. Merchant denies handoff.
16. Rider and merchant evidence conflict.
17. Merchant bank settlement fails.
18. Merchant settlement retry.
19. Refund after merchant guarantee.
20. Security-deposit deduction appeal.
21. Offboarding with cash liability.
22. Offboarding with refundable deposit.
23. Invalid webhook signature.
24. Amount changes before pickup.
25. Amount changes after pickup.
26. Ineligible COD attempt.
27. INR 250-tier rider receives INR 750 UPI-on-delivery assignment attempt.
28. Cash remittance exceeds order total.
29. Partial remittance.
30. Admin reverses an incorrect reconciliation decision.

Required suites:

- unit tests for policy, state machines, exposure, guarantee, deposit, and journals;
- integration tests for provider webhooks, cash/remittance, merchant settlement,
  refunds, incidents, and concurrency;
- end-to-end prepaid, UPI-on-delivery, COD, rider default/disappearance, incident,
  appeal, and offboarding flows;
- deterministic seed data for restaurant, grocery, local retail, three payment
  eligibility bands, all deposit tiers, limit/overdue riders, merchant settlement
  states, open incidents, and deposit appeals.

## 12. Ordered Implementation Tasks

1. Reconcile current payment schema and fix existing parcel webhook contract error.
2. Add versioned payment policy, authoritative totals, and explicit state machines.
3. Add immutable general journals and migrate existing payment-ledger invariants.
4. Add pickup verification and merchant payment guarantee.
5. Add Customer Verification PIN and post-verification delivery completion.
6. Complete prepaid provider abstraction and deterministic mock.
7. Add UPI-on-delivery payment intent, dynamic QR, webhook, and late-event handling.
8. Add physical COD collection and customer confirmation.
9. Add rider deposit, risk limits, exposure reservation, and assignment blocking.
10. Add gross cash remittance, restrictions, and reconciliation.
11. Add merchant settlement scheduling, payout attempts, holds, and retries.
12. Add incidents, evidence, decisions, deposit actions, and appeals.
13. Add refunds independent of rider cash.
14. Build Customer web flows.
15. Build Delivery Partner web flows and wallet.
16. Build Merchant web pickup-guarantee and settlement flows.
17. Build Admin policy, exposure, remittance, reconciliation, settlement, and
    incident operations.
18. Build equivalent native Dastak iOS role flows.
19. Add notifications, observability, retention, and operations alerts.
20. Run all unit, integration, concurrency, end-to-end, RLS, lint, type, build,
    accessibility, and recovery tests.
21. Add operating playbooks and Mermaid diagrams for prepaid,
    UPI-on-delivery, physical COD, merchant guarantee, cash remittance, rider
    disappearance, merchant settlement, and deposit deduction/appeal.
22. Complete professional legal, accounting, tax, payment-aggregation, escrow,
    contractor/employment, deposit, deduction, and settlement review before live
    enablement.

## 13. Completion Gate

This plan is complete only after migrations, services, four web roles, native iOS
roles, provider mock, production adapter, security controls, documentation,
observability, deterministic tests, and live configuration are verified. Final
reporting must list schema changes, functions/endpoints, interfaces, tests,
configuration, known limitations, and all remaining human legal/provider gates.
