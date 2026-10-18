# Merchant polish — local sample evidence

18 October 2026. See the [implementation checkpoint](../../dastak-merchant-polish-implementation-2026-10-18.md) for exact scope and limits.

- [Phone Orders, dark](phone-orders-dark.png): real SwiftUI heading, tiles, queues and incoming-card components with static local data. Not a signed-in order desk.
- [Phone Store, light](phone-store-light.png): local banner/form component gallery; Add photo is intentionally disabled so this check cannot upload.
- [Phone Orders, accessibility size and light appearance](phone-orders-accessibility-light.png): initial heading/summary scaling, not a full accessibility audit.
- [Local detail activation feedback](phone-local-detail-feedback.png): read-only sample callback, not the authenticated detail endpoint.
- [Incomplete iPad startup](ipad-startup-incomplete.png): startup/Home capture from the stalled attempt. **Not** an iPad Merchant pass.

The sample substitutes a two-option Orders/Store chooser for the real four-tab workspace. Preparation expansion, package 2 → 1 → 2 and detail-control activation were observed through the accessibility tree. Native scroll automation was unavailable; software-keyboard, full root/journal/location and live acceptance remain unverified.

No real order, account, photo, notification registration, payment or payout was changed. The simulator-only sample entry requires DEBUG and an explicit launch argument; normal app launch still uses authentication and Merchant access checks.
