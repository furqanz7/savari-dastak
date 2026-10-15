# Customer final address fixes — Build 43

Owner requested exactly two final Customer fixes before wrapping the current scope: the Save address footer/keyboard overlap, and checkout address selection incorrectly replacing the account default.

## Changes

- The address editor hides its bottom Save footer while a form field is focused. A top navigation Done action dismisses the keyboard; the footer returns once editing ends. Removed the floating keyboard Done toolbar and broad navigation-level tap recognizer. Added an inline navigation title so the close control has a defined header. Save rejects a second concurrent submission.
- `defaultDeliveryAddress` tracks the server's actual default independently of the current `deliveryAddress` used for checkout/availability/quotes. Account presentation and Default badges use the actual default.
- Checkout address selection revalidates through the authenticated snapshot read and never calls `setDefault`. New/edited addresses saved from checkout explicitly send `makeDefault: false`, and the saved server address/version becomes the checkout target. Existing API semantics may make the very first address the default when the account has none.
- Account address selection/save retains deliberate default-changing behaviour. The address book labels the checkout target Selected without falsely labelling it Default.
- Refresh preserves a valid current checkout target; a new model restores the unchanged server default. Deleting another address preserves the checkout target; deleting the target falls back to the actual default. Failed/missing-address reads cannot activate the draft or write a new default.
- Submitted reservations retain their existing immutable address snapshots; checkout/availability invalidation remains driven by the selected delivery target.

## Verification

- Final full DastakUI host suite: **498 tests passed, zero failures**. Seven new tests cover read-only checkout selection, refresh/relaunch, non-default checkout save/edit, explicit account default selection, failed/stale reads, and selected/unselected address deletion. Existing address/version/quote/race/checkout-retention tests also pass.
- Final simulator Debug and signed iPhone Debug builds succeeded; strict deep signature verification passed; signed artifact version 43.
- `git diff --check` passed. Branch/HEAD remained `codex/dastak-v1-launch` / `94f531d679e6dcca1bd588ab63c5000b1eb2c620`; accumulated unrelated edits preserved.
- Isolated DEBUG sample address editor installed in the dedicated simulator. CUA screenshot verified keyboard-open form with top Done, no floating keyboard toolbar and no Save footer obscuring fields. Synthetic Block A entry and Next navigation worked. Final Done → enabled Save → local save check was interrupted by the Mac locking; no live address was saved.
- Physical Build 43 installation and normal launch succeeded; installed-app inventory confirms version 1.0.0, bundle version 43. Final two owner checks remain pending. After Mac unlock, CUA again confirmed the top Done action, but Device Hub omits the active navigation controls from its accessibility tree and coordinate taps fail `noWindowsAvailable`, so Done → Save → local save is not claimed passed. No production address/default/order/payment or schema changes were made during development. The Supabase skill guided use of existing authenticated snapshot/save/setDefault contracts rather than backend changes.

Logs: `/tmp/dastak-address43-tests.log`, `/tmp/dastak-address43-simulator.log`, `/tmp/dastak-address43-device.log`.

## Prior Customer commerce acceptance

The owner reported all requested checks passed across seventeen guided rounds, covering Grocery/Food successful journeys, actual collection/handover/completion, before-confirmation cancellations, reservation expiry, matching-time offline recovery, rejection/unavailability, duplicate taps, force-close recovery and cross-role terminal reconciliation. These are owner-reported live acceptance results, not independent backend trace certification. Those passes are retained; only the two new address issues are reopened here. Post-confirmation cancellation policy, Delivery exception/return workflows and distribution/release gates were not silently passed.

## Final owner check

After installing Build 43:

1. In a new/edited address, type the required doorstep details, tap the top Done, and check the Save button is unobscured, enables for a complete form and saves normally.
2. From checkout select a different saved address (and optionally add one there); verify checkout uses it while the original Default badge and Account default remain unchanged, including after relaunch. Do not submit an order.

## Owner acceptance — 15 October 2026

The owner replied **“Both passed”** to the two physical-iPhone checks above on installed Build 43. Save-button/keyboard usability and checkout-address/default separation are therefore owner-confirmed passed. This supersedes the pending owner-check notes above, while retaining the distinction between direct inspection and owner acceptance.

**Dastak Customer's current agreed product scope is wrapped at Build 43.** Preserve its accepted design and features; reopen only for a reproducible defect or an explicit new requirement. The seventeen owner-confirmed commerce rounds remain accepted. Next implementation focus is Delivery Partner in the same app; native Merchant/Admin expansion remains parked. Separate Delivery exception/return, post-confirmation cancellation-policy and distribution/release gates are not marked passed by this Customer scope closure.
