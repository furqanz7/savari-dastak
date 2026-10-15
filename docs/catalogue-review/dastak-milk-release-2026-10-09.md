# Approved Milk Product Type release — 9 October 2026

## Scope and outcome

Owner approved exactly eight reviewed Milk Product Types plus the Everyday 15 g description correction. Applied atomically to linked project `zmtsolkfxlrxepshnjdf` through `dastak_v1_api.update_catalogue_sku`, attributed to the currently signed-in owner's account with its existing catalogue permission. Session claims were transaction-local maintenance context, not a new login, role grant or browser-session change.

| Product | Packs | Recorded Product Type |
|---|---|---|
| Nestle Everyday Dairy Whitener | 15 g, 200 g, 400 g, 1 kg | Dairy Whitener |
| Amul Taaza Toned Milk | 200 ml, 1 L | Toned |
| Arokya Toned Milk | 500 ml | Toned |
| Arokya Full Cream Milk | 1 L | Full Cream |

Only the 15 g description changed to `Dairy whitener for tea and coffee.` Its generated search document followed the corrected description. IDs, legacy slugs, packs, prices, statuses, other attributes, structured quantities, merchant selections and stock/reservations were preserved. Non-target SKU digest remained identical during the transaction. Eight versions advanced by exactly one; eight audit records, eight outbox events and eight idempotency receipts were verified. Active SKU count remains 572; eight have Product Types, 564 do not.

## Safety and verification

- Guarded branch/HEAD: `codex/dastak-v1-launch` / `9c754a787fad0ec7a4612865657d168d0d02362f`; existing review edits and both unrelated staff assets preserved.
- All target IDs/names/packs/versions and the original 15 g description freshly checked; live command definition matched the reviewed hash. Global catalogue lock preceded row locks; deterministic ID order, five-second lock timeout, 30-second statement timeout. Original attributes merged, not overwritten.
- Initial rehearsals rolled back: one caught an SQL alias ambiguity; another exposed the legitimate generated-search-document change. Inspected the live generated expression, retained strict invariants and verified that derived field against its expected expression. Final rollback rehearsal and commit both passed all checks. No failed rehearsal left durable SKU/audit/outbox changes.
- Focused local tests: `catalogueProductType.test.ts` and `reimaginedCatalogue.test.ts`, 14 tests passed. No source-feature changes requiring app deployment.
- Live signed-in Customer: Milk has All, Toned, Full Cream and Dairy Whitener. Toned contains grouped two-pack Amul plus Arokya Toned; Full Cream contains Arokya Full Cream; Dairy Whitener contains one four-pack Nestle card. All retains three unclassified Aavin products, seven grouped products total. Selecting 15 g shows ₹10, Product Type and corrected description, with out-of-stock Add disabled. No cart, order, payment or wishlist mutation for verification.
- Live guarded Admin `admin_catalogue_page` and Merchant `merchant_canonical_catalogue_snapshot` responses, using the owner's existing authorized branch, match all eight IDs/packs/types. Admin's legacy snapshot is not the current paginated SKU detail source. This is database-projection verification, not signed-in Admin/Merchant UI verification.
- A transient Customer availability-check error was visible during screenshot capture, then resolved to the no-delivery-partners notice without signing out or a source change. Its cause was not established or repaired; do not treat this classification release as availability reliability certification.

Machine-readable durable receipt: `dastak-milk-release-receipt-2026-10-09.json`. Operational scripts: `Backends/Dastak/ops/approved-milk-product-types-2026-10-09.sql` (defaults to rollback), `verify-approved-milk-product-types-2026-10-09.sql`, `verify-approved-milk-projections-2026-10-09.sql`. Temporary command outputs: `/tmp/dastak-approved-milk-{rehearsal,commit,postcheck,projections}.json`; live screenshot `/tmp/dastak-approved-milk-15g-live.jpg`.

## Still outstanding

This completes only the approved eight-SKU batch, not all F6 or the full parity audit. Ten held content/evidence conflicts remain, including three Aavin entries. Another 554 products still need classification research. The 15 g structured-quantity warning and legacy slug remain deliberately untouched. F7–F10 and real operational/payment workflows remain open. No blanket migration push, deployment, Git commit/push, new SKU, security change or background/staff edit in this batch.
