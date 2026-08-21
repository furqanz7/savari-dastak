# DASTAK V1 — CODEX MASTER HANDOFF

> Authoritative implementation brief for Dastak v1. Read this entire file before modifying code.

## 0. AUTHORITY AND CHANGE CONTROL

### Source-of-truth order
If anything conflicts, use this priority:
1. Locked Dastak v1 decisions in this handoff.
2. State-machine rules.
3. Backend command/API rules.
4. Retail matching-engine rules.
5. Database/concurrency invariants.
6. RBAC/privacy rules.
7. Event/notification rules.
8. App UX/state rules.
9. Admin/configuration rules.
10. Existing code/UI.

Existing code is not the product truth.

### Future discussion meta-rule
All future Dastak discussion is exploratory/off-record by default. Do not add, remove, reinterpret or override a locked v1 decision unless the product owner explicitly asks to **lock** that new decision or otherwise clearly makes it authoritative. Newer explicitly locked decisions override older proposals.

### Codex rules
Before implementation:
- Read this entire file.
- Audit the existing backend, schema, iOS, Web, Merchant, Delivery and Admin code.
- Produce a gap map: `REUSABLE`, `MUST CHANGE`, `MISSING`, `CONFLICTS WITH V1`.
- Do not simplify product behavior because current code is easier.
- Do not invent new business actions.
- Do not expose generic business-state edit APIs.
- Do not make Admin a backdoor around business invariants.
- Prefer additive/staged migrations and preserve historical data.
- Never fabricate historical events that never occurred.

---

# 1. NON-NEGOTIABLE PRODUCT INVARIANTS

- Retail customers see Dastak canonical SKUs, not retail merchants/storefronts.
- Food & Beverages is Restaurant/Cafe-led and customer-visible.
- One customer order may contain Food & Beverages + Retail.
- Maximum one Restaurant/Cafe fulfilment per customer order.
- Retail Wave 1 = full-basket candidates only, simultaneous opportunity, first valid backend acceptance wins, 3-minute authoritative backend window.
- Wave 1 failure automatically starts Wave 2. No customer Retry button.
- Wave 2 supports split retail fulfilment across at most 3 retail merchants.
- One retail order line is never quantity-split across merchants.
- Retail merchants physically check the exact SKU and full requested quantity before accepting/confirming.
- A winning/selected merchant physically reserves those exact units before customer payment.
- The complete submitted basket must be 100% secured before payment.
- No partial pre-payment checkout.
- Prepaid only. No COD / Pay on Delivery.
- No substitutions in v1.
- No scheduled orders. ASAP/on-demand only.
- Customer may cancel before payment. No self-service cancellation after payment.
- Merchant preparation begins only after confirmed customer payment.
- Merchant chooses promised prep time when accepting/confirming.
- Prep countdown starts only after payment.
- Merchant may mark Ready early.
- Merchant may not extend promised prep time after payment.
- 00:00 does not automatically make a fulfilment Ready; it becomes Running Late until explicit Ready.
- Ready for Pickup is irreversible back to Preparing.
- Merchant must declare package count and capture required in-app evidence photo(s) before Ready.
- Early rider matching starts when every required fulfilment is either Ready or has <=5 minutes remaining.
- One delivery partner handles only one customer order at a time.
- Supported transport: Walking, Bicycle, Motorbike, Scooter, Auto, Car.
- Transport/order-load rules determine delivery mission eligibility.
- One merchant fulfilment may contain multiple physical packages, but all declared packages transfer together.
- Merchant -> Rider pickup requires in-app verification code.
- Rider -> Customer delivery requires in-app verification code.
- Verification codes are one-time, handoff-scoped, never sent by SMS.
- No paid SMS OTP anywhere.
- Customer onboarding is immediate: phone number -> proceed. No OTP, call verification, manual verification or Admin approval.
- Merchant/rider verification may use Dastak manual verification/approval where Dastak requires it, but not SMS OTP.
- Rider must capture required in-app package photo before customer handoff.
- Post-payment exact-SKU failure: recover exact SKU first; if recovery fails, refund affected line and continue the rest.
- Physical returns exist for genuine fulfilment/product issues under strict investigation.
- Prepared food is not physically returned.
- Reverse return custody uses in-app verification codes.
- Approved refunds go to original payment method by default.
- Merchant/rider earnings become settlement-eligible after successful delivery or approved equivalent completion.
- Historical payment, refund, custody and settlement truth is never rewritten.

---

# 2. CUSTOMER / ORDER MODEL

## 2.1 Basket
One parent customer order may contain:
- one Restaurant/Cafe fulfilment, and
- retail catalogue items.

Maximum one Restaurant/Cafe per order.
Retail may split across up to 3 retail merchants in Wave 2.

The same parent Order ID persists through:
- matching,
- payment,
- preparation,
- recovery,
- delivery,
- refund,
- return.

## 2.2 Ordering mode
ASAP/on-demand only. No scheduled orders.

## 2.3 Cancellation
Before payment: allowed.
After payment confirmation: customer self-service cancellation is forbidden.

Post-payment issues use recovery/support/refund/return flows, not cancellation.

---

# 3. RETAIL CATALOGUE AND MERCHANT INVENTORY MODEL

## 3.1 Canonical catalogue ownership
Only Dastak Admin may add/edit/delete canonical:
- Categories,
- Sub-categories,
- Brands where used,
- SKUs,
- canonical product metadata.

Canonical SKU includes at least:
- name,
- brand,
- variant,
- pack size,
- image,
- barcode where available,
- MRP / Dastak-standardized retail price fields,
- logistics attributes,
- lifecycle state.

Retail merchant cannot change canonical name, image, brand, pack size, barcode, category or Dastak-standardized customer price.

## 3.2 Retail merchant onboarding
Merchant identifies as `Supermarket / Convenience Store`.

Flow:
1. Select categories and sub-categories normally carried.
2. Dastak auto-loads applicable canonical SKUs as read-only product truth.
3. Merchant checks only exact SKUs they normally carry.
4. Save.

Merchant SKU selection means **normally carried**, not live inventory quantity.

Retail merchants do not maintain authoritative continuous stock quantities for matching.

## 3.3 Restaurant/Cafe
Restaurant/Cafe onboarding is separate.
Restaurants/Cafes manage their own:
- menu categories,
- menu items,
- variants/add-ons,
- food pricing,
- menu availability.

The restaurant/cafe is visible and explicitly chosen by customer.

## 3.4 Retail merchant privacy
Retail customers never browse/discover/see retail merchants or storefronts in ordinary shopping/fulfilment UI/API.

Do not expose:
- retail merchant names,
- store ratings,
- store pages,
- "fulfilled by" retail merchant identity,
- Wave 1/Wave 2 merchant identities.

Food remains merchant-visible.

## 3.5 Retail pricing
Retail merchants do not set customer-specific SKU prices.
Dastak controls standardized retail SKU pricing in the canonical catalogue, subject to applicable MRP/pricing law.

---

# 4. DASTAK CONVENIENCE STORE

Dastak Convenience Store is a normal retail fulfilment node and may participate in:
- Wave 1,
- Wave 2,
- post-payment recovery,
- normal retail fulfilment.

It is not guaranteed inventory.
It must physically confirm exact availability like every other retail merchant.
Dastak ownership does not automatically give it selection priority.

---

# 5. WAVE 1 RETAIL MATCHING

## 5.1 Eligibility
A retail branch may be considered only if applicable hard checks pass:
- approved/active,
- retail type,
- not suspended,
- open,
- accepting orders,
- service-area eligible,
- reachable under current operational policy,
- below hard capacity,
- has selected relevant canonical SKUs.

SKU selection is catalogue coverage, not live stock.

## 5.2 Candidate generation
Wave 1 candidates are only branches whose selected SKUs cover **every retail order line**.

## 5.3 Opportunity
All eligible full-basket candidates receive the same full-basket opportunity simultaneously.

Merchant sees:
- exact SKU,
- exact requested quantity,
- 3-minute countdown,
- Accept / Unavailable,
- promised prep time selector.

Merchant must physically check the exact shelf stock and full requested quantity before accepting.

## 5.4 Authoritative timer
Wave 1 = 3 minutes.
Backend `started_at`/`expires_at` is authoritative.
Client timer is display only.

Late acceptance after expiry is rejected even if merchant tapped before local timer appeared to finish.

## 5.5 First valid winner
First valid backend transaction that commits wins.
Client timestamps never decide the winner.

Winner atomically:
- becomes selected,
- creates retail fulfilment,
- physically reserves exact confirmed quantities,
- consumes one hard retail prep-capacity slot,
- invalidates competing Wave 1 opportunities.

Losing merchants receive no reservation and no capacity consumption.

## 5.6 Failure
If no winner by expiry:
- Wave 1 is permanently closed for this order attempt,
- customer does not see Retry,
- Wave 2 starts automatically.

---

# 6. WAVE 2 RETAIL MATCHING

## 6.1 Purpose
Wave 2 may split **different retail order lines** across merchants.
A single retail order line is never quantity-split.

Example customer requests `Coke x6`:
Valid: Merchant A supplies all 6.
Invalid: A supplies 4 and B supplies 2.

## 6.2 Partial opportunities
Wave 2 sends merchants only the exact subset Dastak wants them to physically confirm.

Merchant does not see other retail lines or other merchant identities.

## 6.3 Provisional confirmation
When merchant confirms Wave 2 subset:
- exact requested quantities are physically held;
- hold is provisional;
- merchant is not yet a final fulfilment;
- final preparation-capacity slot is not yet consumed.

## 6.4 Valid final plan
A plan is valid only if:
- 100% retail order-line coverage,
- each line assigned exactly once,
- full requested line quantity assigned to one merchant,
- <=3 retail merchants,
- selected provisional holds still active,
- each selected retail branch still eligible,
- hard capacity still available,
- delivery transport feasible,
- pickup route operationally feasible.

## 6.5 Plan priority
Selection order:
1. 100% exact coverage.
2. Fewest retail merchants.
3. Transport/order-size feasibility.
4. Route efficiency.
5. Operational reliability as tie-break.

Advertising/sponsorship/merchant visibility must never affect fulfilment selection.

## 6.6 Maximum merchants
Dastak v1 maximum retail merchants = 3.
If 100% basket needs 4+, order is unavailable.
Architecture may keep max configurable for future versions, but v1 baseline is 3.

## 6.7 Atomic final lock
Lock/revalidate order, selected branches and holds.
Within one transaction:
- validate whole-line coverage,
- validate <=3 merchants,
- validate holds,
- validate capacity,
- validate transport/route,
- consume selected retail capacity slots,
- convert selected holds to final reservations,
- create/finalize fulfilments,
- invalidate/release all other candidate opportunities and holds,
- mark plan locked.

All-or-none.
If one selected branch loses capacity concurrently, no partial final plan may commit.

## 6.8 Wave 2 failure
At Wave 2 expiry with no locked valid plan:
- release all provisional holds,
- release applicable pre-payment commitments,
- order attempt -> Unavailable,
- no payment.

Wave 2 timeout value remains configurable.

---

# 7. PRE-PAYMENT ALL-OR-NOTHING

The complete submitted basket must be 100% secured before payment.

If any required line cannot be secured:
- whole order attempt becomes unavailable,
- no payment,
- no automatic line removal,
- no partial checkout,
- no `Continue with available items`,
- customer returns to cart and may edit/submit a fresh order.

For mixed orders, restaurant confirmation alone is insufficient. If retail fails, restaurant commitment releases.

---

# 8. MERCHANT RESERVATIONS AND CAPACITY

## 8.1 Retail physical reservation
Wave 1 winner/final Wave 2 merchant immediately keeps exact confirmed units aside for Dastak while customer completes payment.
They must not sell reserved units to another customer until released/expired.

## 8.2 Restaurant pre-payment commitment
Restaurant confirmation reserves:
- confirmed menu availability,
- operational capacity commitment.

No preparation before payment.
If payment expires/releases, commitment releases.

## 8.3 Retail hard capacity
Default hard retail capacity = 5 concurrent committed/preparing fulfilments per physical branch.

Capacity slot:
- consumed when Wave 1 wins or merchant is selected into final Wave 2 plan,
- remains occupied while awaiting payment and during preparation,
- released when fulfilment reaches Ready,
- released if pre-payment reservation expires/releases.

At 5/5:
- branch is excluded from new retail matching.

Capacity remains configurable per branch.

## 8.4 Restaurant soft threshold
Default Restaurant/Cafe busy threshold = 5 active orders, **soft only**.

Restaurant may receive/accept 6th, 7th, etc. if it can handle them.
Restaurant may decline or Pause New Orders.
Dastak never silently routes the customer to another restaurant because selected restaurant is busy.

---

# 9. PAYMENT

## 9.1 Prepaid only
No COD / Pay on Delivery in v1.

## 9.2 Payment reservation window
Once complete order is fully secured, start configurable payment-reservation window.

During window:
- retail reservations stay locked,
- restaurant commitment stays locked,
- capacity stays committed,
- customer may retry failed payment attempts without rematching.

## 9.3 Payment success
Authoritative provider confirmation within active window:
- payment -> Succeeded exactly once,
- order -> Paid,
- all required fulfilments -> Preparing,
- prep clocks start from server time,
- expected merchant earnings recorded Pending.

## 9.4 Payment expiry
If window expires unpaid:
- order -> PAYMENT_EXPIRED,
- release retail reservations,
- release restaurant/menu commitments,
- release merchant capacity slots,
- old order attempt cannot reactivate.

## 9.5 Late provider success
A delayed success after PAYMENT_EXPIRED must never resurrect the order.
Create payment reconciliation/refund/reversal as appropriate.

## 9.6 Duplicate callbacks
Payment provider event processing must be idempotent.
Only one successful payment per order.

---

# 10. PREPARATION CLOCK AND READY

## 10.1 Merchant promised time
Merchant chooses promised prep time when accepting/confirming.

Persist:
- promised_prep_minutes,
- prep_started_at,
- estimated_ready_at,
- actual_ready_at.

Do not persist remaining seconds as source of truth.

## 10.2 Clock start
Countdown starts only after payment confirmation.

## 10.3 Early Ready
Merchant may finish and mark Ready while timer still has time remaining.

## 10.4 No extension
After payment starts the prep clock, merchant cannot extend promised prep time.
No `+5 minutes`, no new ETA button.

## 10.5 Late
Timer reaching 00:00 does not make Ready.
If actual_ready_at is null, display Running Late and late duration.

## 10.6 Ready requirements
Before Ready:
- preparation complete,
- package count declared,
- required in-app merchant evidence photo(s) captured.

Ready is explicit and irreversible.
Forbidden: `READY -> PREPARING`.

Any issue after Ready uses Report Problem/exception flow and preserves original Ready history/evidence.

---

# 11. EARLY RIDER MATCHING

Order becomes rider-match eligible when **every required fulfilment** is either:
- Ready, or
- <=5 minutes remaining on prep clock.

A fulfilment marked Ready early immediately satisfies this condition.

Actual package pickup still requires that specific fulfilment to be Ready.

If a merchant later becomes late after rider assignment:
- rider remains assigned,
- Dastak should prioritize already-Ready pickups where feasible,
- rider may wait if necessary,
- record rider arrival, actual Ready and waiting time,
- no automatic rider cancellation/reassignment merely because merchant is late.

---

# 12. RIDER MATCHING AND TRANSPORT

## 12.1 Supported transport
- Walking
- Bicycle
- Motorbike
- Scooter
- Auto
- Car

Each transport type has configured order-load limits (weight/volume/size/package constraints as implemented).

Only riders with capable transport receive/accept a mission.
If no supported transport can carry the full order, do not take payment.

## 12.2 Rider matching
When rider-match eligible:
- determine required transport capability,
- offer simultaneously to a small nearby eligible rider pool,
- first valid backend acceptance wins atomically,
- if none accepts in configured offer window, expand pool and repeat within limits.

## 12.3 One order per rider
Rider may handle only one customer order at a time.
No customer-order batching.

## 12.4 Rider offer/stall/unresponsive
Configurable:
- rider offer timeout,
- stall threshold,
- unresponsive threshold.

Ignoring/declining unaccepted offer simply expands search.

After rider accepts:
- monitor progress.
- if unresponsive before any package pickup, may release/reassign after configured escalation.
- if rider has any package, automatic reassignment is forbidden; Delivery Recovery.

Normal rider Cancel allowed only before any pickup.
After first pickup, rider uses Report Delivery Problem.

---

# 13. PACKAGES AND CUSTODY

## 13.1 Multiple packages
One merchant fulfilment may contain one or more physical packages.
Merchant declares package count before Ready.

At pickup:
- all declared packages must be accounted for,
- partial package pickup is forbidden,
- one pickup code verifies the complete merchant fulfilment handoff.

For multi-merchant orders:
- each fulfilment verifies separately,
- final delivery cannot start until all required packages across all fulfilments are collected.

## 13.2 Explicit custody
Each package should have explicit current custody:
- MERCHANT,
- RIDER,
- CUSTOMER,
- RETURN_RIDER,
- ORIGINAL_MERCHANT.

Custody changes only through verified/authorized handoff commands.

---

# 14. NO SMS OTP / CUSTOMER SIGNUP

No paid SMS OTP anywhere.

Customer onboarding:
- enter phone number,
- continue immediately,
- no SMS OTP,
- no verification call,
- no manual review,
- no Admin approval.

Merchant/rider verification may use Dastak manual call/approval where applicable, but not SMS OTP.

Use implementation-level device/session/account security without reintroducing SMS OTP.

---

# 15. IN-APP HANDOFF VERIFICATION

Normal physical handoffs require Dastak-generated in-app verification codes:
1. Merchant -> Rider pickup.
2. Rider -> Customer delivery.
3. Customer -> Return Rider return pickup.
4. Return Rider -> Original Merchant return receipt.

No SMS.

## 15.1 Lifecycle
Codes are:
- one-time,
- handoff-scoped,
- active only at appropriate stage,
- permanently consumed after success,
- securely random,
- stored hashed where practical.

Repeated invalid attempts are recorded and after configurable threshold transition to Blocked and require controlled Operations flow.

## 15.2 Merchant pickup code
Each merchant fulfilment has its own pickup code.
Valid only when fulfilment Ready and assigned rider is performing pickup.

## 15.3 Final delivery code
Scoped to parent customer order.
Becomes active only after all required packages are collected/final-delivery stage begins.

## 15.4 Buyer vs recipient
Ordering customer owns delivery code.
If another person receives:
- buyer shares code directly,
- recipient needs no Dastak account,
- no SMS OTP.

## 15.5 Exceptional handoff override
Merchant/rider/customer cannot bypass normal code themselves.

Authorized Dastak Operations/Admin may approve rare exceptional handoff after evidence review.

Override must preserve truth:
- normal code verification did not happen,
- verification state = OVERRIDDEN,
- record authorizer, reason, timestamp, context and evidence.

Never mark override as normal code success.

---

# 16. EVIDENCE PHOTOS

Mandatory:
- Merchant: in-app photo(s) of prepared items/package before Ready.
- Rider: in-app package photo before handing to customer.
- Return Rider: in-app returned-item/package photo at customer return pickup.

Evidence is immutable audit evidence tied to order/fulfilment/package/return/actor/timestamp.
Admin does not need to inspect every normal order; evidence is surfaced for issues/investigations.

---

# 17. POST-PAYMENT EXACT-SKU EXCEPTION

Merchant physical confirmation/reservation should make this rare.

Possible examples:
- damaged/leaking item discovered during packing,
- expired product,
- wrong variant accidentally checked,
- count mistake,
- reserved unit accidentally unavailable.

Merchant:
- reports exact affected line,
- no substitution,
- continues valid remaining items.

Dastak:
1. attempt exact-SKU recovery from another eligible merchant/Dastak Convenience Store;
2. same exact SKU and full order-line quantity only;
3. if recovered: replacement fulfilment, same parent order, no extra customer payment;
4. if recovery fails: automatically refund affected line and continue remaining paid order;
5. no customer cancellation prompt;
6. if nothing remains deliverable: close as Dastak fulfilment failure with applicable full refund.

---

# 18. DELIVERY RECOVERY / FAILED FINAL DELIVERY

Once rider has collected any package, rider retains custody until Dastak completes customer handoff or explicitly directs recovery/return.

Rider must never independently:
- abandon,
- reroute to a materially different destination,
- refund,
- dispose,
- hand goods elsewhere.

Examples:
- customer unreachable,
- customer refuses,
- wrong/materially changed address,
- delivery code problem,
- rider vehicle breakdown,
- safety issue,
- package issue.

Customer-caused failed delivery:
- not cancellation,
- no automatic refund,
- eligible retail may return to original merchant,
- prepared food non-restockable,
- correctly fulfilling restaurant remains entitled to legitimate earnings.

Dastak/rider-caused failure:
- Dastak owns recovery,
- if ultimately cannot deliver, applicable customer refund,
- protect correctly fulfilling merchant earnings.

Minor address correction may be operationally handled.
Materially different destination requires delivery-address exception.

---

# 19. RETURNS

## 19.1 Eligible issues
- wrong SKU,
- wrong quantity,
- damaged,
- defective,
- expired,
- tampered/broken seal,
- incorrect package,
- suspected merchant mis-fulfilment,
- other Dastak-approved exception.

## 19.2 Normally non-returnable
- change of mind,
- ordered by mistake,
- dislike,
- found cheaper elsewhere,
- no longer needed,
- correctly delivered product with no genuine issue.

## 19.3 Food
Prepared food is not physically returned.
Food problems use investigation/refund resolution.

## 19.4 Physical-return decision
Dastak decides whether approved retail issue requires:
- physical return, or
- refund/other resolution without physical return.

Reporting windows remain configurable by category/SKU/issue/value/policy.

## 19.5 Reverse custody
Customer -> Return Rider:
- return pickup code,
- required return photo,
- verified custody transfer.

Return Rider -> Original Merchant:
- return receipt code,
- verified custody transfer.

Preserve full reverse chain of custody.

---

# 20. REFUNDS AND SETTLEMENT

## 20.1 Refund destination
Approved monetary refunds go to original payment method by default.
Dastak credits/store credit must not be forced as sole refund method.

Original successful payment remains immutable historical truth.
Refund is a separate record.

## 20.2 Merchant earnings
Payment confirmation records expected merchant earning as Pending.
After successful delivery or approved equivalent completion, correctly fulfilling merchant earning -> Settlement Eligible.

If Dastak/rider later causes delivery failure after correct merchant fulfilment, merchant should not lose legitimate earning.

## 20.3 Rider earnings
Mission offer/active mission may show Estimated earning.
Successful mission completion -> Confirmed/Settlement Eligible.

## 20.4 Payout cadence
Actual bank payout cadence remains configurable/business decision.

## 20.5 Later merchant-caused refund after settlement
Do not rewrite historical payout.
Create new auditable settlement adjustment/debit/credit applied to future settlement according to policy.

---

# 21. CORE DOMAIN MODEL

Use names appropriate to current stack, but preserve these domain boundaries.

## 21.1 Customers / sessions
- customers
- customer_sessions

## 21.2 Merchants
- merchant_organizations
- merchant_branches
- merchant_users

merchant_type:
- RETAIL
- RESTAURANT_CAFE
- DASTAK_CONVENIENCE_STORE

Physical branch is matching/capacity unit.

## 21.3 Canonical retail catalogue
- categories
- subcategories
- brands
- skus
- merchant_sku_selections

## 21.4 Restaurant menu
- restaurant_menu_categories
- restaurant_menu_items
- variants/add-ons as required

## 21.5 Orders
`orders` fields conceptually:
- id
- display_order_number
- customer_id
- order_type: RETAIL_ONLY | FOOD_ONLY | MIXED
- status
- delivery_address_snapshot
- recipient_snapshot
- subtotal/fees/discount/tax/total snapshots
- created_at
- submitted_at
- fully_secured_at
- payment_expires_at
- paid_at
- delivered_at
- version

## 21.6 Order lines
- order_id
- line_type: RETAIL_SKU | FOOD_MENU_ITEM
- sku/menu reference
- name/variant/pack-size snapshots
- quantity
- unit price snapshot
- line total
- status

## 21.7 Matching
- matching_attempts
- merchant_opportunities
- inventory_holds
- fulfilment_plans
- plan line/merchant mappings

## 21.8 Fulfilments
- fulfilments
- fulfilment_lines

Fulfilment fields:
- order_id
- merchant_branch_id
- type: FOOD | RETAIL | RECOVERY
- status
- committed_at
- promised_prep_minutes
- payment_confirmed_at
- prep_started_at
- estimated_ready_at
- actual_ready_at
- package_count
- expected merchant earning
- capacity slot state
- version

## 21.9 Packages/evidence
- packages
- evidence

Package current custody explicit.

Evidence types include:
- MERCHANT_READY_PHOTO
- RIDER_PRE_DELIVERY_PHOTO
- CUSTOMER_ISSUE_PHOTO
- RETURN_PICKUP_PHOTO

## 21.10 Payments
- payments
- payment_attempts
- payment_provider_events
- payment_reconciliation_cases

## 21.11 Delivery
- delivery_missions
- delivery_offers
- delivery_stops

## 21.12 Verification
- verification_handoffs

handoff_type:
- MERCHANT_TO_RIDER
- RIDER_TO_CUSTOMER
- CUSTOMER_TO_RETURN_RIDER
- RETURN_RIDER_TO_MERCHANT

status:
- INACTIVE
- ACTIVE
- CONSUMED
- BLOCKED
- OVERRIDDEN

## 21.13 Recovery / Issues / Return / Refund
- recovery_cases
- customer_issues
- returns
- return_lines
- return_packages
- refunds

## 21.14 Settlement
- settlement_entries

entry types:
- EARNING
- BONUS
- DEBIT_ADJUSTMENT
- CREDIT_ADJUSTMENT
- REFUND_ADJUSTMENT

status:
- PENDING
- ELIGIBLE
- SETTLED

## 21.15 Infrastructure
- domain_events_outbox
- audit_events
- setting_definitions
- platform_settings
- idempotency_records

---

# 22. STATE MACHINES

## 22.1 Parent order
Primary:
`CREATED -> MATCHING -> FULLY_SECURED -> AWAITING_PAYMENT -> PAID -> PREPARING -> PICKUP_IN_PROGRESS -> OUT_FOR_DELIVERY -> DELIVERED`

Pre-payment terminal:
- MATCHING -> UNAVAILABLE
- AWAITING_PAYMENT -> PAYMENT_EXPIRED
- unpaid customer cancellation -> CANCELLED_PREPAYMENT

Rare post-payment terminal:
- DASTAK_FULFILMENT_FAILURE when nothing remains deliverable.

Recovery never rewinds Paid order to Matching.

## 22.2 Opportunity
Wave 1:
- OFFERED -> SELECTED | DECLINED | EXPIRED | LOST | INVALIDATED

Wave 2:
- OFFERED -> PROVISIONALLY_ACCEPTED
- PROVISIONALLY_ACCEPTED -> SELECTED | RELEASED | EXPIRED | INVALIDATED

## 22.3 Fulfilment
`RESERVED_PREPAYMENT -> PREPARING -> READY -> PICKED_UP -> COMPLETED`

Pre-payment release:
`RESERVED_PREPAYMENT -> RELEASED`

No READY -> PREPARING.

## 22.4 Delivery mission
`SEARCHING_RIDER -> ASSIGNED -> EN_ROUTE_TO_PICKUPS -> PICKUP_IN_PROGRESS -> ALL_PACKAGES_PICKED_UP -> OUT_FOR_DELIVERY -> ARRIVED -> DELIVERED`

Before custody: REASSIGNING allowed under rules.
After custody: problems -> DELIVERY_RECOVERY.

## 22.5 Package
`DECLARED -> READY -> PICKED_UP -> IN_TRANSIT -> DELIVERED`

## 22.6 Order line
`ORDERED -> RESERVED -> FULFILLING -> FULFILLED`

Exception:
`FULFILLING -> RECOVERY -> FULFILLED | REFUNDED`

## 22.7 Verification
`INACTIVE -> ACTIVE -> CONSUMED`
Repeated invalid attempts -> BLOCKED.
Authorized exception -> OVERRIDDEN.

## 22.8 Recovery
`OPEN -> SEARCHING_EXACT_SKU -> RECOVERED | RECOVERY_FAILED`

## 22.9 Return
`REQUESTED -> UNDER_REVIEW -> REJECTED | APPROVED`

Approved no physical return:
`APPROVED -> RESOLUTION_WITHOUT_PHYSICAL_RETURN -> COMPLETED`

Approved physical return:
`APPROVED -> RETURN_REQUIRED -> RIDER_SEARCH -> CUSTOMER_PICKUP -> IN_RIDER_CUSTODY -> RETURNED_TO_ORIGINAL_MERCHANT -> COMPLETED`

## 22.10 Refund
`CREATED -> APPROVED -> PROCESSING -> COMPLETED | FAILED`

## 22.11 Settlement
Merchant: `PENDING -> ELIGIBLE -> SETTLED`
Rider: `ESTIMATED -> CONFIRMED/PENDING -> ELIGIBLE -> SETTLED`

---

# 23. BACKEND COMMAND CONTRACT

Apps request business commands; never directly set domain statuses.

Critical commands should support:
- authenticated actor,
- authorization,
- resource ownership/context,
- idempotency key,
- expected version where useful,
- transaction,
- audit,
- event outbox.

## 23.1 Customer
- submitOrder
- cancelPrepaymentOrder
- createPaymentAttempt
- reportPostDeliveryIssue

## 23.2 Retail merchant
- acceptWave1Opportunity
- declineOpportunity
- acceptWave2Opportunity
- reportFulfilmentProblem
- markReady

No prep extension command.
No substitution command.
No paid-order cancellation command.

## 23.3 Restaurant
- confirmRestaurantOrder
- declineRestaurantOrder
- markReady
- reportFulfilmentProblem

5 active threshold must not hard-reject additional customer-selected order.

## 23.4 Internal matching
- startWave1
- expireWave1
- startWave2
- lockWave2Plan
- evaluateOrderSecured

## 23.5 Payment
- confirmPayment
- expirePaymentReservation
- reconcileLatePayment

## 23.6 Rider
- acceptDeliveryOffer
- declineDeliveryOffer
- cancelDeliveryBeforePickup
- arriveAtPickup
- verifyPickup
- capturePreDeliveryEvidence
- verifyDelivery
- reportDeliveryProblem

## 23.7 Operations
- authorizeExceptionalHandoff
- start/inspect recovery
- controlled delivery-recovery actions
- approveReturn where permitted
- approveRefund according to permissions/thresholds

## 23.8 Returns
- verifyReturnPickup
- verifyReturnReceipt

## 23.9 Catalogue
Only Catalogue/Admin:
- create/edit/activate/deactivate canonical categories/subcategories/brands/SKUs.

Retail merchant only:
- update own merchant_sku_selections.

---

# 24. DATABASE / CONCURRENCY / IDEMPOTENCY

## 24.1 Versioning
Mutable business objects should carry `version` for stale-screen/optimistic concurrency protection.

## 24.2 Wave 1 first winner
Use transactional row lock or equivalent compare-and-swap.
Exactly one valid winner.
Never use client timestamp.

## 24.3 Guarded opportunity transition
Conditional update only from allowed state and before server expiry.
Stale/late requests affect zero rows and are rejected.

## 24.4 Wave 2 atomicity
Lock order + selected branches + holds in deterministic order.
Revalidate everything.
Commit final plan all-or-none.

## 24.5 Retail capacity
Use atomic guarded increment (`active < limit`).
Never read 4 then later independently write 5.
Capacity release exactly once with slot state HELD/RELEASED.

## 24.6 Payment exactly once
Provider reference unique.
Provider event id unique.
At most one successful payment per order.
Webhook retries safe.

## 24.7 Paid vs Expired race
Both commands lock same authoritative order/payment-reservation row.
Exactly one final state: Paid or Payment Expired.

## 24.8 Prep start once
prep_started_at null -> timestamp once.
Duplicate provider event cannot restart prep.

## 24.9 Ready one-way
Only PREPARING -> READY.
No reverse transition.

## 24.10 One active rider mission per order
DB uniqueness/constraint over active statuses.

## 24.11 One active customer mission per rider
DB uniqueness/constraint over active statuses.

## 24.12 Custody
Package has exactly one current custody owner.
Custody transfer occurs only inside verified handoff transaction.

## 24.13 Pickup atomicity
For N declared packages:
- all N verified,
- code consumed,
- all N custody -> Rider,
- fulfilment -> Picked Up,
- all or none.

## 24.14 Final delivery completeness
Before Out for Delivery, every non-refunded required package must be in assigned rider custody.

## 24.15 Code consumption
Secure random code.
Store hash where practical.
Conditional ACTIVE -> CONSUMED update exactly once.
Atomic invalid-attempt increment.

## 24.16 Transactional outbox
Business state + event outbox row commit together.
Push/analytics/settlement side effects happen after commit.

## 24.17 Idempotency
Required for critical writes:
- submit order,
- accept opportunity,
- payment attempt,
- mark Ready,
- accept rider mission,
- verify pickup,
- verify delivery,
- approve refund,
- approve return.

Same key/same request -> original result.
Same key/different request -> reject.

## 24.18 Immutable history
Do not hard-delete transactional records.
Do not overwrite evidence.
Do not rewrite old payments/refunds/settlements/custody.

## 24.19 Snapshotting
Order submission snapshots commercial and recipient/address values.
Future catalogue/config changes do not rewrite old order.

---

# 25. RBAC / PRIVACY

## 25.1 Principle
Authorization requires:
- explicit permission,
- resource ownership/context,
- current state.

Hiding UI buttons is not authorization.

## 25.2 Roles
Suggested:
- Customer
- Retail Merchant
- Restaurant/Cafe
- Delivery Partner
- Customer Support
- Merchant Support
- Delivery Operations
- Live Order Operations
- Finance
- Catalogue Admin
- Verification/KYC
- Operations Admin
- Super Admin

Roles should be permission bundles.

## 25.3 Customer
Can:
- own order/cart/payment/refund/return/support.
Cannot:
- see/select retail merchants,
- cancel after payment,
- bypass code,
- access another customer.

## 25.4 Retail merchant
Can:
- own branch availability,
- own SKU selection,
- own opportunities/fulfilments,
- prep/Ready/problem/pickup code,
- own earnings.

Cannot:
- edit canonical SKU/MRP,
- see other retail merchants,
- substitute,
- extend prep,
- reverse Ready,
- mark pickup/delivery,
- issue arbitrary refund.

## 25.5 Restaurant
Own food menu/order flow.
Cannot alter retail catalogue or reroute customer to another restaurant.

## 25.6 Rider
Only assigned mission operational data.
Cannot:
- hold two customer missions,
- alter fulfilment/merchant/address,
- bypass verification,
- partial pickup,
- cancel after custody,
- refund/dispose/abandon goods.

## 25.7 Support / Operations / Finance / Catalogue
Separate permissions. Do not use a broad `is_admin` model.

## 25.8 Retail privacy
Ordinary customer retail API should not even return internal merchant identity fields unless legally required in a specific document/context.
Merchant A cannot query Merchant B fulfilment.

## 25.9 Sensitive data
- mask bank details outside authorized roles,
- never expose raw payment credentials,
- limit rider access to customer contact/location after mission completion,
- evidence access scoped to relevant case/role.

## 25.10 Audit
Sensitive writes and high-sensitivity reads must be auditable.
Admin is never exempt from audit.

---

# 26. EVENTS AND NOTIFICATIONS

Backend committed events are truth.
Push is alert only.
Push failure never rolls back business state.
Apps fetch current server state on open/reconnect.

Suggested events:
- ORDER_SUBMITTED
- WAVE_1_STARTED
- MERCHANT_SELECTED
- WAVE_1_EXPIRED
- WAVE_2_STARTED
- WAVE_2_PROVISIONAL_ACCEPTED
- WAVE_2_HOLD_RELEASED
- WAVE_2_PLAN_LOCKED
- ORDER_FULLY_SECURED
- PAYMENT_WINDOW_STARTED
- PAYMENT_ATTEMPT_FAILED
- PAYMENT_CONFIRMED
- PAYMENT_RESERVATION_EXPIRED
- PREPARATION_STARTED
- FULFILMENT_RIDER_THRESHOLD_REACHED
- ORDER_RIDER_MATCH_ELIGIBLE
- RIDER_MATCHING_STARTED
- RIDER_ASSIGNED
- FULFILMENT_READY
- RIDER_ARRIVED_PICKUP
- PICKUP_VERIFIED
- FULFILMENT_PICKED_UP
- ALL_PACKAGES_PICKED_UP
- ORDER_OUT_FOR_DELIVERY
- RIDER_ARRIVED_CUSTOMER
- DELIVERY_VERIFIED
- ORDER_DELIVERED
- FULFILMENT_EXCEPTION_REPORTED
- RECOVERY_STARTED
- RECOVERY_SUCCEEDED
- RECOVERY_FAILED
- REFUND_CREATED
- REFUND_COMPLETED
- CUSTOMER_ISSUE_REPORTED
- RETURN_APPROVED
- RETURN_RIDER_ASSIGNED
- RETURN_PICKUP_VERIFIED
- RETURN_RECEIPT_VERIFIED
- DELIVERY_RECOVERY_STARTED

Customer-visible progress remains simple:
- Confirming / Finding items
- Payment
- Preparing
- Picking up
- On the way
- Delivered

Do not expose Wave terminology or retail merchant identities.

Use notification dedupe keyed by event + recipient + notification type.

---

# 27. CUSTOMER APP UX CONTRACT

## 27.1 Signup
Phone number -> Continue -> immediate use.

## 27.2 Retail browsing
Canonical Dastak SKU catalogue only.

## 27.3 Food browsing
Customer-visible restaurants/cafes.

## 27.4 Cart
One Restaurant/Cafe max + retail items.

## 27.5 Place Order
Starts matching/confirmation. Does not charge.

Matching UI:
- Finding your items...
- optional Checking more nearby availability...
- Cancel available while unpaid.

## 27.6 Fully secured
Show authoritative total and Pay action.
Optionally show payment reservation countdown.

## 27.7 Unavailable
Back to Cart.
No Continue with available items.
No same-attempt Retry.

## 27.8 Payment failed
Show order still reserved and Retry while window valid.

## 27.9 Paid
Cancel action disappears.

## 27.10 Preparing
Retail merchant identities hidden.
Selected food restaurant may be named.

## 27.11 Rider assigned/pickup
Customer sees Picking up your order, not internal retail stops.

## 27.12 Final delivery
On the way + final in-app delivery code.

## 27.13 Delivered
Get Help.

## 27.14 Returns/refunds
Issue -> investigation -> return/refund status.
Physical return shows return rider + return pickup code when active.

---

# 28. MERCHANT APP UX CONTRACT

## 28.1 Merchant type onboarding
Choose:
- Restaurant/Cafe
- Supermarket/Convenience Store

## 28.2 Retail onboarding
Category/subcategory selection -> Dastak canonical SKUs -> merchant checkboxes -> Save.

## 28.3 Retail Home
Show:
- accepting orders,
- capacity x/5,
- incoming requests,
- Preparing,
- Ready.

At 5/5, automatically no new retail opportunities.

## 28.4 Restaurant Home
Show active count and soft busy threshold warning.
May accept >5.
May Pause New Orders.

## 28.5 Wave 1 request
Exact full basket, exact quantities, 3-minute timer, promised prep selector, Accept/Unavailable.

## 28.6 Wave 2 request
Only requested subset.
After provisional confirmation say held while Dastak completes order, not final win.

## 28.7 Waiting payment
Do not prepare.

## 28.8 Paid / Preparing
Countdown + Report Problem + Mark Ready.
No Extend.
No Substitute.
No Cancel Paid Order.

## 28.9 Mark Ready
1. package count,
2. in-app evidence photo(s),
3. irreversible Ready confirmation.

## 28.10 Ready
Show rider state and active pickup code when appropriate.

## 28.11 Picked Up
Show fulfilment transferred.

## 28.12 Earnings
Expected/Pending -> Eligible -> Settled according to settlement system.

---

# 29. DELIVERY APP UX CONTRACT

## 29.1 Transport onboarding
Walking / Bicycle / Motorbike / Scooter / Auto / Car.

## 29.2 Home
Online/offline.
At most one customer mission.

## 29.3 Mission offer
Show pickup count, order-size class, distance/route estimate, estimated earning, timeout, Accept/Decline.

## 29.4 Assigned
Route to pickup stops.
A stop may be Ready or approximately <=5 min due early matching.

## 29.5 At merchant
- I've Arrived,
- expected package count/checklist,
- pickup code only when Ready and all packages accounted.

## 29.6 Cancellation
Before any package: secondary Cancel may exist.
After first pickup: no normal Cancel; Report Delivery Problem only.

## 29.7 All pickups complete
Final delivery stage begins.

## 29.8 At customer
1. I've Arrived.
2. Take mandatory package photo.
3. Enter delivery code.
4. Delivered.

## 29.9 Delivery problems
Customer unreachable/refusal, address issue, code issue, vehicle/safety/package problem -> controlled recovery.

## 29.10 Return mission
Customer pickup + return photo + return pickup code -> original merchant + return receipt code.

---

# 30. ADMIN / OPERATIONS CONSOLE CONTRACT

Admin is control tower, not database editor.
All actions must use named business commands.

Main modules:
- Live / Network
- Orders
- Matching
- Recovery
- Merchants
- Restaurants/Cafes
- Delivery / Riders
- Returns & Refunds
- Finance
- Catalogue
- Zones
- Verification
- System Health
- Audit
- Configuration
- Roles/Permissions

## 30.1 Live Order Attention
Separate from normal support tickets.
Prioritize:
1. safety/custody emergency,
2. paid-order recovery,
3. delivery recovery,
4. rider waiting / food deterioration,
5. verification problems.

## 30.2 Order forensic view
Show complete internal truth:
- customer/payment,
- all fulfilments,
- internal retail merchants,
- lines,
- matching timeline,
- plan selection,
- prep,
- evidence,
- packages/custody,
- rider,
- verification,
- recovery,
- returns/refunds,
- settlement,
- event timeline.

## 30.3 Merchant capacity
Retail hard capacity and exclusion reason.
Restaurant soft threshold only.

## 30.4 Rider control
If rider holds packages, ordinary Reassign disabled; open Delivery Recovery.

## 30.5 Verification Center
No generic Mark Verified.
Use explicit Authorize Exceptional Handoff with reason/evidence/audit.

## 30.6 Recovery
Exact-SKU only.
No Admin substitute picker.

## 30.7 Finance
Payment reconciliation, refunds, settlement, append-only adjustments.

## 30.8 Catalogue
Canonical product management, validation/audit, bulk import review.

## 30.9 Emergency controls
Scoped pause of new retail/food/mixed/merchant/rider assignment.
Existing paid commitments remain active.

## 30.10 Audit
Admins fully audited.

---

# 31. CONFIGURATION REGISTRY

Configuration tunes operations but must not redefine locked product behavior.

Support scopes:
- Global
- Zone
- Merchant branch / rider class
- Category/SKU where applicable

## 31.1 Protected v1 baseline
- Wave 1 duration: 3 minutes.
- Max retail fulfilment merchants: 3.
- Default hard retail branch capacity: 5.
- Default restaurant busy threshold: 5, soft only.
- Early rider matching threshold: 5 minutes.

## 31.2 Intentionally configurable
- Wave 2 timeout
- Payment reservation timeout
- Retail matching radius
- Recovery radius
- Route feasibility thresholds
- Rider initial pool size
- Rider offer timeout
- Rider expansion behavior
- Rider stall/unresponsive thresholds
- Merchant reachability thresholds
- Transport load limits
- Return/refund reporting windows
- Verification invalid-attempt threshold
- Customer-unreachable wait/contact policy
- Alert thresholds
- Refund approval limits
- Merchant commission
- Rider payout formula
- Customer delivery/platform fees
- Payout cadence
- ETA model/buffers

Codex must not invent production business values. Use clearly marked development defaults/config placeholders if not supplied.

## 31.3 Product-version locked, not ordinary toggles
- substitutions = off
- COD = off
- scheduled orders = off
- post-payment customer cancellation = off
- retail merchant customer visibility = off
- retail line quantity splitting = off
- rider batching = off
- SMS OTP = off
- merchant Ready photo required = true
- rider pre-delivery photo required = true
- in-app custody verification required = true

Changing these requires a new explicit product lock.

## 31.4 Config audit
Every change: key, scope, old/new, actor, reason, time, effective date where applicable.

---

# 32. ACCEPTANCE TESTS / RELEASE GATES

The build is not complete because screens work. It must preserve invariants under races/failures/retries.

## 32.1 Matching tests
1. Full-basket Wave 1 success -> one winner, reservation, capacity, no payment yet.
2. Simultaneous Wave 1 accepts -> exactly one winner.
3. Late Wave 1 accept -> rejected.
4. One line quantity never split across merchants.
5. Wave 1 expiry -> Wave 2 auto-start.
6. Wave 2 merchant sees only subset.
7. Provisional Wave 2 hold does not consume final capacity.
8. Valid 2-merchant plan beats valid 3-merchant plan.
9. Same merchant count -> route/operations decides, ads never matter.
10. Final Wave 2 lock atomic under concurrent capacity loss.
11. 4 merchants required -> unavailable.
12. Wave 2 failure releases all provisional holds.

## 32.2 Mixed/pre-payment tests
13. Restaurant confirms, retail fails -> whole attempt unavailable, food commitment releases.
14. 4/5 lines secured -> no partial checkout.

## 32.3 Payment tests
15. Payment success starts prep exactly once.
16. Failed payment retry does not rematch.
17. Payment expiry releases everything.
18. Late payment success after expiry does not resurrect.
19. Duplicate webhook -> one logical payment/prep/earning/notification.

## 32.4 Preparation tests
20. Merchant cannot extend prep.
21. Merchant may Ready early.
22. 00:00 does not Ready automatically.
23. Ready irreversible.

## 32.5 Rider tests
24. 05:00 threshold eligible; 05:01 not yet for single fulfilment.
25. Multi-fulfilment all must be Ready or <=5.
26. Early Ready satisfies its condition.
27. Simultaneous rider accepts -> one winner.
28. Wrong transport backend-rejected.
29. Rider with active customer mission cannot accept another.
30. Rider unresponsive before pickup may be released/reassigned.
31. Rider unresponsive after pickup -> Delivery Recovery, no auto-reassign.

## 32.6 Lateness/package tests
32. Merchant late after rider assignment -> rider remains assigned.
33. Rider waiting duration recorded correctly.
34. Ready rejected without evidence/package count.
35. Declared 3 / present 2 -> pickup cannot complete.
36. One pickup code atomically transfers all declared packages.
37. Pickup-code replay -> no second transfer.
38. Wrong rider with valid code -> rejected.

## 32.7 Final delivery tests
39. Missing required pickup blocks Out for Delivery.
40. Final code activates only after all required packages collected.
41. Correct code without rider photo cannot complete.
42. Normal delivery -> custody customer, Delivered, earnings eligible.
43. Different recipient without Dastak account can receive buyer-shared code.
44. Invalid code threshold -> Blocked/Operations.

## 32.8 Override tests
45. Rider cannot self-bypass.
46. Authorized override -> OVERRIDDEN, normal verification false, audit complete.
47. Unauthorized override rejected.

## 32.9 Recovery tests
48. Exact recovery succeeds -> replacement fulfilment, same line, no extra customer payment.
49. Recovery fails -> affected line refund, remainder continues.
50. Only line fails -> Dastak fulfilment failure/full applicable refund.

## 32.10 Cancellation tests
51. Pre-payment cancel succeeds and releases all.
52. Post-payment cancel rejected.

## 32.11 Failed delivery tests
53. Customer unreachable -> rider keeps custody, Delivery Recovery, no automatic refund.
54. Customer refuses -> not Cancelled, custody controlled.
55. Material address change -> rider cannot self-reroute.
56. Eligible retail return-to-origin controlled to original merchant.
57. Correct restaurant/customer-caused failure -> restaurant earning protected.

## 32.12 Returns tests
58. Wrong SKU issue surfaces full evidence chain.
59. Change-of-mind normally ineligible.
60. Approved refund without physical return creates no return mission.
61. Physical return uses both in-app reverse codes + return pickup photo.
62. Return-code replay creates no second custody transfer.

## 32.13 Settlement tests
63. Merchant expected earning Pending after payment.
64. Delivered -> merchant/rider Eligible.
65. Later merchant-caused refund after payout -> new adjustment, old settlement unchanged.
66. Dastak/rider failure after correct merchant fulfilment protects merchant legitimate earning.

## 32.14 Security/privacy tests
67. Retail merchant cannot access another merchant fulfilment.
68. Customer cannot access another customer order.
69. Rider cannot alter merchant/fulfilment assignment.
70. Catalogue Admin cannot refund without permission.
71. Merchant cannot edit canonical SKU/MRP.
72. Customer retail API does not expose retail merchant identity.
73. Mixed order may expose selected restaurant but not internal retail merchants.

## 32.15 Capacity/system truth tests
74. Retail 5/5 excluded from matching.
75. Ready releases retail capacity exactly once.
76. Duplicate Ready retry does not double-release.
77. Restaurant >5 active may still receive/accept selected-restaurant order.
78. Matching infrastructure failure is not product unavailability.
79. Merchant push failure is observable as system failure, not stock truth.
80. Push failure after Payment Confirmed does not roll back business state.
81. Duplicate domain event does not duplicate earnings/notifications.
82. Evidence cannot be silently overwritten/deleted.
83. Historical order price remains snapshot after catalogue price change.

## 32.16 Impossible-state monitors
These queries must normally return zero:
- orders with >1 active delivery mission,
- riders with >1 active customer mission,
- retail line with >1 active final merchant,
- retail hard capacity exceeded,
- Picked Up fulfilment missing declared packages,
- Delivered without Consumed/Overridden final verification,
- Paid without successful payment,
- Payment Expired with prep started,
- contradictory package custody.

Any non-zero result = critical system incident.

---

# 33. IMPLEMENTATION PHASES

## Phase 0 — Audit
Inspect current backend/schema/apps/auth/payment/push/admin/deployments.
Produce REUSABLE / MUST CHANGE / MISSING / CONFLICTS WITH V1.

## Phase 1 — Additive schema/migrations
Create domain tables, constraints, indexes, immutable history.

## Phase 2 — State machines/business commands
No generic state edits.

## Phase 3 — Auth/session/RBAC
Customer immediate phone entry; server authorization; merchant/rider verification path as applicable.

## Phase 4 — Canonical retail catalogue
Admin catalogue + retail merchant SKU selection. Restaurant menu remains merchant-managed.

## Phase 5 — Parent order/mixed basket
Retail-only, food-only, mixed. Immutable snapshots. No payment on submit.

## Phase 6 — Wave 1
3 minutes, full-basket, simultaneous, atomic winner, reservation, capacity.

## Phase 7 — Wave 2
Partial opportunities, provisional holds, <=3, fewest merchants, route/transport, atomic final lock.

## Phase 8 — Restaurant coordinator
Customer-selected restaurant, soft threshold, pre-payment commitment.

## Phase 9 — Payment reservation/payment
Retry, exactly once, expiry/release, reconciliation.

## Phase 10 — Preparation
No extension, early Ready, package/evidence, irreversible Ready.

## Phase 11 — Early rider matching
<=5 minute/Ready condition, transport eligibility, pool expansion.

## Phase 12 — Package custody/outbound verification
All-packages pickup, pickup code, rider photo, final delivery code.

## Phase 13 — Delivery Recovery
Rider/customer/address/custody exceptions.

## Phase 14 — Exact-SKU recovery
Same exact SKU only; line refund on failure.

## Phase 15 — Returns/refunds
Issue investigation, reverse custody, original-method refund.

## Phase 16 — Settlement ledger
Pending -> Eligible -> Settled, append-only adjustments.

## Phase 17 — Transactional outbox/events/notifications
Push is side effect only.

## Phase 18 — Customer app integration
Authoritative state/commands only.

## Phase 19 — Merchant app integration
Retail vs Restaurant flows.

## Phase 20 — Delivery app integration
Transport, offers, custody, recovery, return missions.

## Phase 21 — Admin/Operations
Safe named commands only.

## Phase 22 — Configuration registry
No scattered magic operational constants.

## Phase 23 — Observability
Order forensic trace + invariant alarms.

## Phase 24 — Full acceptance suite
Concurrency, failure, security, finance, recovery.

### Definition of Done per phase
Not done because a screen exists.
Done requires, as applicable:
- schema/migration,
- backend command,
- authorization,
- legal state transition,
- DB invariant,
- domain event,
- error handling,
- UI integration,
- audit/observability,
- acceptance tests,
- concurrency tests for critical paths.

---

# 34. EXPLICIT DO-NOT LIST FOR CODEX

Do not:
- add substitutions;
- add COD;
- add scheduled orders;
- expose retail merchants/storefronts to customers;
- allow customer post-payment cancellation;
- split one retail line quantity across stores;
- exceed 3 retail merchants in v1;
- assume Dastak Convenience Store inventory;
- give Dastak Store guaranteed winning priority;
- let retail merchant edit canonical SKU/MRP/name/image/pack size/category;
- let merchant extend prep after payment;
- auto-mark Ready at timer zero;
- allow Ready -> Preparing;
- allow partial package pickup;
- let rider batch multiple customer orders;
- assign order to incapable transport;
- automatically reassign after rider has any package;
- start final delivery before all required packages collected;
- let rider mark Delivered without valid code or authorized override;
- use paid SMS OTP anywhere;
- add customer OTP/call/Admin approval signup;
- require recipient Dastak account;
- allow normal users to bypass handoff codes;
- record override as normal code success;
- resurrect expired order from delayed payment;
- mutate historical payment/refund/settlement/custody truth;
- use merchant advertising in fulfilment selection;
- represent technical matching failure as real product unavailability;
- give Admin generic state-edit controls;
- trust client-supplied ownership/role/merchant/rider/price/payment/transport state;
- rely on frontend timer as matching/payment authority;
- rely on push delivery as business state;
- hard-delete transactional history.

If an implementation shortcut conflicts with this list, the shortcut is wrong.

---

# 35. CURRENT DEVELOPMENT CONTEXT — NON-AUTHORITATIVE / OFF-RECORD

The following was discussed after the v1 lock and is **not** a locked product rule unless explicitly locked later:
- Web customer experience currently exists as a temporary fallback while native Android is not complete.
- iOS is being built natively.
- Android is intended as a separate native frontend.
- Current intent is that once Android is complete/live, Web may become primarily a marketing/landing page with App Store / Google Play install buttons.

Do not let this note override any locked v1 marketplace behavior.

---

# 36. FINAL CODEX INSTRUCTION

Do not begin implementation by editing screens.

First:
1. Read this handoff.
2. Audit existing repositories and schema.
3. Produce the gap analysis.
4. Map existing code to the implementation phases.
5. Identify migrations and conflicts.
6. Implement backend invariants/state/commands before UI convenience.
7. Run acceptance tests and concurrency tests.

The implementation must adapt to Dastak v1. Dastak v1 must not be silently simplified to fit the existing implementation.
