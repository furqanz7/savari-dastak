# Checkout fee diagnosis — 9 October 2026

Scope: delivery/platform fees only. Solo read-only source and linked-database
inspection at commit `34ee886d9e01cbdf857e7493f1d8e418548d5a56`.
No production writes, order reservations, payments or pricing changes.

## Confirmed faults

1. Grocery Price review in `ReimaginedGroceryBilling.tsx` is hard-coded to
   combine delivery/fees/taxes as `Awaiting checkout`; it never receives the
   reserved order's price. Both checkout counters do render the returned fee
   fields, including zero, after an explicit reservation/status read.
2. The linked `dastak_v1.apply_authoritative_delivery_fee()` trigger returns
   without pricing when `orders.restaurant_branch_id` is null. It therefore
   excludes Grocery. All existing RETAIL_ONLY snapshots have zero delivery
   and platform fields: SUBMITTED 36/36, FULLY_SECURED 23/23, PAID 12/12.
   Aggregate snapshot counts are not counts of unique orders.
3. The V1 submission SQL seeds zero fees; FULLY_SECURED copies that snapshot.
   Food has a separate trigger based on its restaurant route. In linked data,
   Food includes both zero-fee historical snapshots and charged snapshots.
4. There is no V1 pre-order quote RPC or client integration. Legacy merchant
   and Parcel quote APIs are different workflows and cannot safely be
   substituted for V1 multi-merchant checkout.

## Resolved policy conflict

- `DASTAK_V1_LOCKED_ADDENDA.md` and its accounting regression tests explicitly
  state that the 2% platform revenue does not change checkout pricing.
- The newer Food delivery trigger instead adds `calculate_platform_fee`
  on subtotal + delivery to the customer's payable total. These are distinct
  concepts: customer surcharge vs internal platform revenue. Do not silently
  equate them or alter existing accounting authority.
- Existing newer Food distance bands are 1500 paise through 1000m, 2000
  through 2000m, then 500 per additional started kilometre. The legacy
  launch spec uses 3500 through 3000m then 800 per started kilometre.

User approved: “Charge 2%, and use the Food delivery rule for both”. New orders
therefore add a 2% customer surcharge on items plus delivery and use the newer
Food distance bands in both services. Internal ledger revenue remains untouched.
Local implementation is prepared; no production pricing change has been applied.

## Required fix after clarification

- Add server-authoritative pre-reservation pricing for exact cart/selection
  and saved delivery location; label estimates where merchant pickup is not
  committed. Quote reads must not reserve/create orders or write audit/outbox.
- Price secured Grocery using its actual committed pickup branches/route,
  not a guessed/flat client charge. Keep matching, version/idempotency and
  commitment/payment amount consistency intact.
- Preserve already-paid/committed immutable history. Do not backfill old
  price snapshots or recompute PAID amounts against a new rule.
- Display separate delivery/platform lines and current total in the primary
  checkout review; invalidate quotes on cart/address/session changes.
- Add tests for tariff boundaries, rounding, Food options, Grocery multi-stop
  routes, unavailable quotes, stale requests and reservation/paid consistency.
- Production migration and release need explicit scoped authorization after
  the fee policy is resolved; no real order/payment needed for verification.
