# Checkout appearance — Build 31, 15 October 2026

These changes are also included in Build 32, which corrects the preparation/assignment stage sequence. Build 32 passes simulator/device builds and signature verification; installation and visual comparison still await Mac unlock/iPhone reconnection.

## Changes

- Fixed dark text on the fixed brown reservation and selected-payment cards in Light Mode. These cards now explicitly use the light primary-action foreground and the dark-surface secondary text palette. Applied the same correction to the payment-collection card and return pickup-code card, which used the same fixed brown background.
- The modal Order status content now draws the adaptive matte page canvas inside NavigationStack, and modal checkout screens opt out of the immersive scene environment. This prevents the default white navigation canvas from showing through. Payment option uses the same opaque navigation-bar palette.
- Shortened the pre-confirmation button to “Review & confirm”. The final confirmation action remains on the payment screen. Changed “Authoritative total” to “Order total”; the displayed amount still comes from the secured order snapshot.
- Added a DEBUG-only checkout appearance preview that renders the actual order-status/payment-option views with a synthetic unsaved reservation. Its client fails closed for submission/confirmation and polling is skipped for this explicit preview flag.

## Verification

- Simulator and signed iPhone builds succeed; deep/strict signature verification and diff whitespace checks pass. Device artifact reports bundle version 31.
- Existing palette/contrast suite: 8 tests pass.
- Local Light Mode order-status preview installed and launched in the dedicated simulator. Visual comparison is pending because the Mac is locked. Physical install is pending because the iPhone is unavailable; user asked to unlock/reconnect via the ongoing questions.
- No production orders, confirmations, payment changes or backend migrations.

Logs: `/tmp/dastak-checkout31-{simulator,device,palette-tests}.log`.
