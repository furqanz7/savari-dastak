# Finished Grocery order blocking new checkout

## Evidence and cause

Customer screenshot showed an old order receipt with `Status: delivered`, a
disabled Confirm Grocery order button, and no way back to a fresh reservation.
The saved journal survived completion. Recovery only reads the old order; it
does not submit a new request. The reset path previously accepted only expired
and unpaid-cancelled reservations. Delivered recovery could also acknowledge an
old purchase against a newly refilled Bucket, removing matching new items.

## Fix

- Rename recovery to Check saved Grocery order and clarify that it sends no new
  merchant request.
- Recognize DELIVERED/CANCELLED as finished and show Return to Bucket for a new
  order instead of a disabled confirmation button.
- Re-read the authoritative old order under the existing checkout lock before
  clearing only its journal pointer. Do not alter any server order or current cart.
- Never acknowledge a finished old purchase against current Bucket quantities.
- A new reservation still requires a separate explicit Reserve Grocery order
  click, with a new request key and the current exact cart/recipient/location.
- Live committed-order lost-response reconciliation remains unchanged. Active,
  mismatched, failed or ambiguous recovery is never discarded to create a new order.
- No backend, fee, inventory, rider gate, merchant application or matching change.

## Verification

- Counter regressions: delivered/cancelled recovery; no commit/submission/cart
  acknowledgement on status check or reset; new explicit reservation/key afterward.
- Recheck failures preserve the old journal. Active reservations cannot be reset.
- Full Customer-root test loads an old delivered journal plus a refilled Bucket
  and Food cart, preserves both, resets safely and submits exactly the current
  quantities only on the next explicit reservation click.
- Tests use mock clients. No real order submitted, cancelled, confirmed or paid.
- Only Customer needs deployment. Unrelated dirty documents/assets remain untouched.

## Release

- Customer production READY at https://dastak-customer.vercel.app/.
- Built source `f4e3766862f21a00732308d93ce2f99d2e7936e7`;
  deployment `dpl_SX9L8a7uB3ahaeVa4fQEQu648gqb`.
- Production HTML confirmed SHA, Customer variant, production environment and
  deployment identity. Error-level deployment log scan returned no entries.
- All 148 test files / 1,045 tests passed. TypeScript, changed-file ESLint and
  production build passed. Existing 3D chunk-size warnings remain.
- Stabilized test-only asynchronous fixtures: wait for request fingerprinting,
  provide repeatable autocomplete results and target the actual directions link
  rather than the first map anchor. No additional application code was changed.
- No real new order was placed to prove merchant receipt. The full Customer-root
  regression proves a fresh authenticated submission intent after explicit reset
  and Reserve clicks; actual merchant delivery still uses existing server eligibility.
- No database changes, merchant/delivery redeployment or Git push.
