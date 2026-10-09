# Dastak location and saved-address pass — 2026-10-09

Scope: Customer phone location picker, Profile Saved places, area refresh and existing availability gates. No SKU work, background changes, database migration or live account/order mutations. Solo implementation.

## Corrected defects

- Editing location-search text retained the previous confirmed coordinates and allowed saving the wrong delivery pin. The editor now clears that selection and requires a newly confirmed result before Save.
- Address submit did not guard its busy state; address fields remained editable during Save. Fields are now disabled and submit is guarded. The shared search input has an associated label.
- A routine token refresh reset a locally selected non-default address. Fresh data remains session-bound, but local selection is now bound to account and backend, not the rotating token.
- Account management marked both the local selection and saved default as Default. It now marks only the saved default; checkout selection is labelled Selected.
- Editing a non-default address promoted it to default. Both Customer management paths now preserve that address's default status. New addresses retain the existing default behaviour; explicit default selection remains available.
- Location management incorrectly promised Save and review order. Its editor now uses the account Save address context.
- Profile address saves/default changes/deletions did not refresh the Reimagined root's shared address resource. A success callback now triggers a reread; Grocery availability and Food discovery then receive the fresh address identity/version.
- Old Profile address responses could update UI or sign out after credentials changed/unmount. Their lifetime is guarded; submit events deduplicated; ambiguous Save retries reuse a key only for the same draft.

## Verification

- Red tests reproduced wrong-pin save, busy submit, token-refresh selection loss and duplicate Default badges before their respective fixes.
- Full web suite: **986 tests across 144 files passed**.
- TypeScript build, changed-file ESLint and diff whitespace checks passed.
- Integration tests cover Profile mutation refresh, both services receiving a new address version, stale area/session replies, missing merchant/restaurant messaging, visible disabled closed restaurant, out-of-stock packs and cart-without-delivery/order-blocking behaviour.
- Browser: synthetic local phone preview at 390 × 844 and 390 × 520. Editor/footer stayed inside viewport with no horizontal overflow. Changing search text removed Pin confirmed and disabled Save. Escape dismissed without Save and restored opener focus; closing Location left no modal or body scroll lock.
- Short viewport is keyboard-height emulation, not a physical-device keyboard test.
- Browser synthetic data only; no live address save/delete/default change, GPS permission or order submission. Actual address writes exercised using mocked services in interaction tests.

Evidence: [short phone editor](verification/dastak-location-controls-2026-10-09/phone-short-editor.png).

## Release

Production release and live read-only verification to be appended after deployment.
