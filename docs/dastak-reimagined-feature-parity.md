# Customer feature parity — 2026-10-07

2026-10-08 location-aware follow-up: local stock, delivery admission and closed-store visibility are implemented; the owner authorized production release. The specific database migration and catalogue API are released, with Customer deployment next at this checkpoint. See `dastak-customer-area-availability.md` for rules and verification. Earlier deployment notes below do not apply to this new policy.

Comparison: previous `DastakCustomerView`, `DastakV1CustomerExperience` and `CatalogueView` versus the authenticated Reimagined root. Uses existing authenticated APIs and canonical SKU/menu IDs. No new inventory, payments engine or account system.

| Previous Customer capability | Reimagined implementation |
| --- | --- |
| Save Grocery products and Food dishes | Native shelf/detail Save controls; existing `customer-wishlist` snapshot/set API |
| Wishlist browsing and removal | Native Wishlist from the header or Account; exact SKU/dish details; unavailable saved identities retained |
| Product images and detail content | Photo gallery, brand/variant/pack/manufacturer/origin/diet/shelf-life/barcode when supplied, unit price, description and sharing |
| Pack-size choices | Detail choices were retained in the 2026-10-07 pass, but shelf cards were still per SKU. The 2026-10-08 local correction groups genuine branded packs into one shelf card; selection retains exact SKU identity, price and quantity. See `dastak-reimagined-shelf-parity.md`. |
| Saved-address add/edit/delete/default | Existing address sheets embedded in Location and Grocery/Food checkout; existing authenticated address API; explicit actions and retry keys |
| Profile editing used by checkout | Shared account editor; successful server profile response updates root recipient immediately |
| Order again | Native exact-SKU/option reconstruction, review-before-order, approval before replacing that service's cart; other cart retained |
| Food cart quantity controls | Increase/decrease/remove with ownership, menu availability, option validity, offline and quantity-limit guards |
| Detailed checkout bill | Grocery and Food show server item/delivery/platform/tax/discount amounts; reserved recipient/address snapshot is shown separately from later edits |
| Reservation recovery/order management | Checkout links open native Orders/details rather than navigating away |
| Notification onboarding/settings | One shared existing push controller, root prompt plus existing account controls |
| Orders, receipts, payment history, delivery PIN/tracking, cancellation, support/issues/returns | Existing operational components retained inside Reimagined; not replaced with placeholder pages |
| Account profile, linked identities, sessions, privacy/legal/support, sign-out/delete account | Existing account components retained; no live destructive/security changes performed during verification |

## Preserved exclusions and honest limits

- Parcel and Print remain Soon under the canonical Reimagined brief. This general feature-restoration request did not explicitly reverse those service restrictions.
- No fabricated city-trending ranking. The previous catalogue does not provide a verified city-ranking endpoint; the unavailable state remains.
- Older mixed-service orders cannot silently become a new mixed cart. They show an explanation to rebuild separate service carts; unavailable exact products/options are not substituted or partially restored.
- Save/address writes are verified with mocked authenticated adapters, not production account mutations. No actual order, payment, address deletion or notification permission was executed.
- Background/staff are frozen and unchanged. Existing large 3D bundle warnings remain separate from feature parity.

## Evidence

- Full web test suite: 788 passed before the final scroll-reset/Food-breakdown refinements. Final focused checks/build are recorded in the handoff.
- TypeScript, ESLint and production build passed. Regression tests cover exact galleries/variants, existing Wishlist IDs, offline and late-account responses, retry keys, address management, native reordering, replacement approval, other-cart preservation and updated recipients.
- Browser synthetic fixture at `reimagined-feature-check.html`: saved Grocery and Food, opened an exact saved SKU, checked product facts/share affordance, selected required Food options and changed Food review quantity. 390×844 and 320×568 had no horizontal page/panel overflow. One preview hot-reload duplicate-root warning was fixed; no new captured errors after reload.
- Fixture is DEV-only and uses no live account/catalogue writes; it is not proof of a real purchase or backend fulfilment.
- This pass is local implementation/verification. It is not a production deployment record.

## Production release preparation — owner approved 2026-10-07

- Owner's follow-up “go ahead” authorizes pushing and deploying this feature-restoration pass to Customer production. The local-only notes above describe the implementation checkpoint before that approval.
- Release gate reruns the full suite, lint and TypeScript. The prior production build passed. Deployment uses the guarded Customer project/archive workflow and excludes both untracked RPM avatar files; no database migration or other app deployment is included.
- Actual release SHA, deployment status, live normal-address checks and limitations are reported in the deployment handoff. Production checks are read-only; no order, Wishlist change, address write/deletion or permission prompt is submitted.
