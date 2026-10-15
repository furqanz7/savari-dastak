# Basket product photos — Build 42

The user's Grocery basket screenshot showed a basket glyph instead of the Aavin Delite Milk photo.

## Cause and correction

Both item-row branches in `DastakCartView` called the symbol-only artwork initializer, which deliberately supplied no image key. The Grocery row now passes `entry.product.imageKey`; the Food row passes `entry.item.imageKey`. Both use the existing cached catalogue photo loader, aspect-fit rendering, thumbnail/original fallback and 68-point row width. Basket/cutlery symbols remain fallbacks only when the item has no usable photo. No order, payment, product data or basket contents are changed.

## Verification

- Full DastakUI host suite: 491 tests passed, zero failures.
- New regression test verifies Grocery and Food image keys survive quantity increments and basket JSON persistence/restoration, with both quantities retained.
- Simulator Debug and signed device Debug builds succeeded.
- Strict deep signature verification passed; signed artifact CFBundleVersion is 42.
- `git diff --check` passed.
- After the user reconnected the iPhone, installation succeeded. The installed-app inventory confirms Dastak 1.0.0, bundle version 42, and launch succeeded with the navigation-only basket URL. Device Hub's physical screen visibly shows the purple Aavin Delite Milk 500 ml product photo in the Grocery basket, with quantity 1 and ₹24.00 unchanged. No order was placed. Food's image-key wiring and persistence are tested; a populated Food basket was not available for physical visual verification.

Logs: `/tmp/dastak-basket-photos42-tests.log`, `/tmp/dastak-basket-photos42-simulator.log`, `/tmp/dastak-basket-photos42-device.log`.
