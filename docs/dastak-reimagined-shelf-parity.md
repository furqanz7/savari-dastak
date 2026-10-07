# Reimagined Grocery shelf correction — 2026-10-08

Local implementation, not a production deployment record. Guard: branch `codex/dastak-v1-launch`, starting HEAD `0aacf52c9a60ec9e2368649a01e258d120f3ee69`. Both existing untracked RPM avatar assets are untouched. No database, inventory, account, payment or production cart writes.

## Confirmed omissions corrected

- Previous `ProductGrid` used `groupProductFamilies`; Reimagined shelves rendered every SKU separately. Shelves and suggestions now group genuine branded products, retaining each exact pack SKU in a selector. Search by a size still starts from the matching size. Brand, variant, normalized presentation name and canonical category/subcategory boundaries are respected; unrelated flavours, brands, rails and uncertain unbranded products are not guessed together.
- Each selected size drives its own image, selling price, MRP, real discount badge, availability, stock cap, quantity and Wishlist identity. Switching sizes neither replaces nor merges existing cart lines. Product-detail fallback grouping uses the same boundaries as the shelf.
- Brand labels and percentage discounts were missing from the shelf presentation and are restored. Shelf counts describe product cards, not pack SKUs.
- Tall image intrinsic dimensions could escape their image slot into the name. Explicit bounded image slots and contain scaling now prevent that. Long names have a two-line shelf label; full names remain on the detail button/title and detail screen.
- Add/quantity and Save have a dedicated action area. On phones Save occupies the image corner, leaving the full quantity row available for two 44-pixel buttons. Short desktop windows use compact spacing; narrow phone panels scroll rather than shrinking controls.

## Further parity review

Inspected the old `DastakV1CustomerExperience` product grid/detail overlay against `ReimaginedGrocery`, the current root and the existing feature-parity record. This is a Customer shopping comparison, not a fresh whole-platform certification.

- **Missing at the shelf checkpoint; now restored locally in the approved follow-up:** product-detail previous/next paging, horizontal product swipe and an orbit-style picker. See `dastak-reimagined-product-browser.md` for the behavior and separate verification record. Pack sizes stay inside one product page.
- Already connected in current source: product detail photos, supplied facts, unit price, sharing, Wishlist, address management, recipient editing, Food choices, service-specific reorder and server checkout breakdown. Account and order workflows reuse operational components rather than placeholders. Source wiring is not proof of live fulfilment.
- No genuine city-trending ranking is available in the reviewed adapter. Do not fabricate rankings. Parcel and Print stay Soon per the canonical brief.
- Image containment does not improve the resolution of the underlying product photographs. Blurry/incorrect source assets require a separate exact-SKU asset review; no replacement products or generated inventory were added.

## Verification

- Final gates: **808 tests passed across 124 files**, full ESLint passed, TypeScript passed and production build succeeded (24.77 seconds). `git diff --check` passed. Existing large 3D chunk warning is unrelated; background/staff are frozen.
- DEV/loopback-only `reimagined-shelf-check.html` uses actual shell/shelf components with deliberately tall and square synthetic packs, a long name and an unavailable item. It does not authenticate or persist a live cart.
- Browser check at 1280×720, 390×844 and 320×568: bounded images stay above names; no horizontal page overflow at the phone widths; size selector and purchase touch targets are at least 44 pixels. Small screens legitimately scroll vertically. Synthetic cart retained separate 1 L and 200 ml identities and quantities. Unavailable item stays visible with Add disabled. Selected size opens exact details and remains selected after closing.

## Owner check after deployment

Open Dairy, Bread & Eggs → Milk. Confirm one card per genuine Amul/Nestle product, choose a different size, and check image/price/MRP/quantity follow that exact size. Add two sizes of one family, then inspect separate size lines in the Bucket. Check a tall carton, a long name, an unavailable pack and the same actions on a phone. No order or payment is needed for this check.
