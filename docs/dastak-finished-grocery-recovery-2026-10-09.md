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

Final test totals and production identity are recorded after release.
