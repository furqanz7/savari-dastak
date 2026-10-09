# Checkout fee fix — local implementation, 9 October 2026

Guard: `codex/dastak-v1-launch`, HEAD `34ee886d9e01cbdf857e7493f1d8e418548d5a56`.
Worktree: `/Users/Furqan/Documents/Savari/.worktrees/wave1-runtime-ci`.
Existing unrelated edits preserved. Solo execution; no paid model/image calls.

## Approved rules

Customer platform surcharge: 2% of item subtotal plus delivery, half-up to paise.
Grocery and Food delivery: ₹15 through 1 km, ₹20 through 2 km, then ₹5 per
additional started kilometre. Existing tax-inclusive unit prices remain intact.

## Complete feature path

Delivery/billing review → one debounced batched `customerCheckoutQuote` call →
authenticated owned-address/version RPC → current exact SKU/menu-option prices
and eligible merchant inventory → pickup-route estimate → separate numeric
delivery/platform/total lines. Quote failure is NOT represented as ₹0.

Quotes are read-only: no order, stock reservation, idempotency record, commitment,
payment, audit or outbox write. Customer coordinates/prices/actor overrides are
not forwarded by the handler. Private route helpers are not customer-executable.

The Grocery estimate prefers one full-cart merchant, then bounded greedy coverage
of remaining SKUs, with at most four stops including Food. It is not a matching
promise; inability to find a complete estimated cover returns unavailable.
The route remains the existing geodesic shortest pickup permutation, not roads.

SUBMITTED prices are estimates. FULLY_SECURED prices use actual reserved
fulfilment branches, so the bill can change before explicit confirmation.
PAID snapshots copy the committed price without rerunning current pricing.
Old orders retain immutable pricing version 0; new orders default to version 1.
No historical snapshot updates or accounting/royalty changes are included.

Changing cart, exact Food options, restaurant, address/version or session cancels
obsolete requests. Offline/expired/failed quotes fail closed, with retry. A quote
expires after at most 45 seconds; inactive Grocery item view does not fetch it.
After reservation the upper estimate yields to the server-confirmed bill below,
keeping the frozen recipient/address and exact payable amount visible.

## Verified locally

- Complete frontend suite: **147 files, 1,032 tests passed**.
- New quote client/lifecycle tests: **29 passed**, including fee boundaries,
  half-paise rounding, exact context/options, stale replies, expiry and errors.
- Catalogue/API handler suite: **32 passed**; Edge entrypoint type-check passed.
- TypeScript, scoped ESLint and `git diff --check` passed.
- Production Vite build passed; existing large-chunk warning remains.
- Isolated PostgreSQL 14 SQL execution: `CHECKOUT_FEE_CONTRACT_OK`.
  Covers Grocery multi-stop fees, Food options, zero-stock rejection, RPC grants,
  address ownership/version, no quote writes, actual secured repricing and
  preservation of PAID/historical amounts and immutable policy version.

## Explicit verification limits and release boundary

The SQL harness uses a minimal schema and simulated planar-metre spatial helpers.
It is NOT full Supabase/PostGIS, complete RLS/matching/collection integration or
production verification. The Docker daemon is unavailable; no full stack started.
No real customer order/reservation/collection or live cart mutation was performed.

Migration `20261009111558_checkout_fee_quotes.sql` is prepared but NOT applied.
The catalogue Edge function and Customer app are NOT deployed for this fix.
Obtain scoped release authorization, check the pending migration list, apply ONLY
this fee migration, refresh the exposed RPC schema as needed, deploy the API and
Customer build, then verify quotes read-only. Do not deploy unrelated dirty edits,
create real test orders, collect payment, or claim the fee fix is live beforehand.
