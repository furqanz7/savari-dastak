# Active-order basket visibility — Build 41

The user reported an empty bottom basket/cart bar stacked above the active order tracker on iPhone.

## Change

The shared native basket dock now appears only when a basket has been picked up (or has contents) and there are no active orders. Both Grocery and Food use the same rule, including product/detail sheets, search and saved-item presentation. The legacy floating cart uses the same condition. Tracking remains unchanged. Hidden docks no longer reserve their modifier's bottom inset or prompt offset. Basket contents are preserved; terminal orders allow the dock to return.

The condition checks both loaded order history and the authoritative focused V1 order, because submission or a focused-order refresh can precede the history refresh. Existing active/terminal status definitions are reused, including legacy orders and parcels through `hasActiveOrders`.

## Verification

- 13 basket tests passed, including new coverage for all eight active V1 statuses hiding both service docks before history loads, all six terminal statuses restoring them, and preserving both populated baskets.
- Full DastakUI host suite: 490 tests passed, zero failures.
- Simulator Debug build and signed iPhone Debug build succeeded.
- Strict deep code-signature verification passed; device artifact CFBundleVersion is 41.
- `git diff --check` passed.
- After the user reconnected the iPhone, installation succeeded and `devicectl` launched `com.dastak.app`. The installed-app inventory confirms version 1.0.0, bundle version 41. Device Hub subsequently showed the phone's screenshot-sharing screen rather than the live Dastak Home screen, so physical active-order/cart visibility remains a user check. No real order, payment or production data was changed.

Logs: `/tmp/dastak-active-order41-tests.log`, `/tmp/dastak-active-order41-all-tests.log`, `/tmp/dastak-active-order41-simulator.log`, `/tmp/dastak-active-order41-device.log`.
