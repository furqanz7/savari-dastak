// Local, read-only review preparation. No database, HTTP or update operations.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const [skuFile, browseFile, outputDirectory] = process.argv.slice(2);
assert(skuFile && browseFile && outputDirectory, 'Supply SKU JSON, browse JSON and output directory');
const skus = JSON.parse(readFileSync(skuFile, 'utf8')).rows;
const browse = JSON.parse(readFileSync(browseFile, 'utf8')).rows;
assert.equal(skus.length, 572, 'Review snapshot must contain the expected 572 active SKUs');
assert.equal(new Set(skus.map(s => s.sku_id)).size, skus.length);
const paths = new Map(browse.map(r => [r.sku_id, r.browse_nodes]));
assert.equal(paths.size, skus.length);

const nestle = 'https://www.nestle.in/brands/nestleeverydaydairywhitener';
const nestle15 = 'https://www.nestle.in/media/pressreleases/allpressreleases/nestl%C3%A9-everyday-tata-tea-kanan-devan-partner-perfect-cup-tea';
const everyday15Id = '2642d986-1130-4d4a-88bf-d0da178469d7';
const staleEverydayDescription = 'Curated infant milk formula for Dastak grocery delivery.';
const taaza = 'https://old.amul.com/products/amul-uhttaaza-info.php';
const fullCream = 'https://www.hap.in/arokya/full-cream-milk.html';
const toned = 'https://www.hap.in/arokya/toned-milk.html';
// Exact IDs, never substring-based automatic classification of the catalogue.
const candidates = new Map([
  [everyday15Id, ['Dairy Whitener', nestle15, 'Nestle Everyday Dairy Whitener', '15 g']],
  ['21de9800-be42-4da4-ba6f-13bf17980145', ['Dairy Whitener', nestle, 'Nestle Everyday Dairy Whitener', '200 g']],
  ['6c425649-c011-4f9e-80dc-3b228a95b5ff', ['Dairy Whitener', nestle, 'Nestle Everyday Dairy Whitener', '1 kg']],
  ['d5e0f1fc-f851-4469-b307-b858d4fed175', ['Dairy Whitener', nestle, 'Nestle Everyday Dairy Whitener', '400 g']],
  ['5d9344b3-4d48-4cc2-a041-289fba4155bb', ['Toned', taaza, 'Amul Taaza Toned Milk', '1 L']],
  ['a51d8c7d-bd8c-4f1e-8728-27b2b3df7397', ['Toned', taaza, 'Amul Taaza Toned Milk', '200 ml']],
  ['5908c4c1-9dce-4104-9342-13a9ab7926aa', ['Full Cream', fullCream, 'Arokya Full Cream Milk', '1 L']],
  ['3ca69e40-a71f-4c10-977b-738aa67b9b3f', ['Toned', toned, 'Arokya Toned Milk', '500 ml']],
]);
const holds = new Map([
  ['ad8ffcb7-6615-4ad0-a36d-c79bf944a1ab', 'Aavin Delite name does not establish Full Cream. Its current canonical subcategory alone is not sufficient evidence.'],
  ['278b1418-3ff6-4398-ba51-132b559fc035', 'Aavin Full Cream name suggests Full Cream, but no manufacturer or verified pack evidence was obtained in this pass.'],
  ['b5bb8877-b01e-40fe-a306-7f61a2e6d131', 'Aavin Nice Toned name suggests Toned, but no manufacturer or verified pack evidence was obtained in this pass.'],
  ['f6f936e6-ff4c-4920-b5bf-6181edaa90c2', 'Same Amul Pasteurised Butter name is split between salted and unsalted canonical subcategories across pack sizes. Check actual packs, not their paths.'],
  ['2f5eee78-0a5c-492b-a578-71ed1f259255', 'Same Amul Pasteurised Butter name is split between salted and unsalted canonical subcategories across pack sizes. Check actual packs, not their paths.'],
  ['afdd4039-1717-4db8-8f32-9a05ba57fb6d', 'Same Amul Pasteurised Butter name is split between salted and unsalted canonical subcategories across pack sizes. Check actual packs, not their paths.'],
  ['02e45397-40ef-4226-9365-df1e58f7a0ce', 'Processed Cheese Cubes name is under Cheese Blocks; the 200 g pack is under Cheese Slices. Resolve form/path conflict.'],
  ['7a55f61a-d128-492b-a4b3-ee84c833d821', 'Processed Cheese Cubes name is under Cheese Slices; the 500 g pack is under Cheese Blocks. Resolve form/path conflict.'],
  ['a8bcb2e9-cd42-43ee-8105-91ef2ce3e1aa', 'Peanut Butter Bar multipack is under Peanut Butters, while a similarly named single bar is under Protein Bars. Confirm product identity and appropriate rail.'],
  ['41ca4536-c609-433f-9bdc-310c4d3aad0c', 'Name describes Hakka Noodles Masala but its canonical subcategory is Hakka Noodles. Confirm seasoning versus noodles and appropriate rail.'],
]);
const rows = skus.map(s => {
  const nodes = paths.get(s.sku_id);
  assert.equal(nodes.filter(n => n.kind === 'DESTINATION').length, 1, s.sku_id);
  assert.equal(nodes.filter(n => n.kind === 'RAIL').length, 1, s.sku_id);
  const destination = nodes.find(n => n.kind === 'DESTINATION');
  const rail = nodes.find(n => n.kind === 'RAIL');
  assert.equal(rail.parent, destination.key);
  const candidate = candidates.get(s.sku_id);
  if (candidate) {
    assert.equal(s.canonical_name, candidate[2], `Name drift: ${s.sku_id}`);
    assert.equal(s.pack_size, candidate[3], `Pack drift: ${s.sku_id}`);
    assert.equal(rail.label, 'Milk');
    assert(!holds.has(s.sku_id));
  }
  const warnings = [];
  if (s.quantity_unit === 'pack' && /\d\s*(?:g|kg|ml|l)\b/i.test(s.pack_size)) {
    warnings.push('Structured quantity is expressed as pack while the display pack uses a weight/volume; not corrected in this review.');
  }
  return {
    skuId: s.sku_id, expectedVersion: s.version, name: s.canonical_name,
    brand: s.brand, packSize: s.pack_size, variantName: s.variant_name,
    destination: { key: destination.key, label: destination.label },
    rail: { key: rail.key, label: rail.label },
    canonicalSubcategory: { slug: s.subcategory_slug, label: s.subcategory_name },
    currentProductType: s.attribute_data?.productType ?? null,
    proposedProductType: candidate?.[0] ?? null,
    status: candidate ? 'SUPPORTED_PROPOSAL_AWAITING_REVIEW' : holds.has(s.sku_id) ? 'HOLD_EVIDENCE_OR_CONTENT_CONFLICT' : 'NOT_YET_CLASSIFIED',
    approved: false,
    reason: candidate ? 'Manufacturer product-line information agrees with the existing SKU name. Pack identity remains anchored to the Dastak snapshot, not newly certified by the manufacturer page.' : holds.get(s.sku_id) ?? 'No product-specific classification has been verified in this pass. Blank does not mean this product needs no Product Type.',
    evidence: candidate ? [{ kind: 'manufacturer_product_line', url: candidate[1], checkedOn: '2026-10-09' }] : [],
    contentWarnings: warnings,
    proposedContentRepairs: s.sku_id === everyday15Id ? [{ field: 'description', expectedValue: staleEverydayDescription, proposedValue: 'Dairy whitener for tea and coffee.', approved: false, reason: 'Manufacturer confirms an Everyday 15 g pack for tea; the live row and recorded updates identify Everyday but retain legacy infant-formula content. Keep the existing SKU ID and slug.' }] : [],
  };
});
assert.equal(rows.filter(r => r.proposedProductType !== null).length, 8);
assert.equal(rows.filter(r => r.status.startsWith('HOLD')).length, 10);
assert.equal(skus.find(s => s.sku_id === everyday15Id).description, staleEverydayDescription, 'Everyday description drift: re-review the proposed repair');
assert(rows.every(r => r.currentProductType === null && !r.approved));
for (const id of [...candidates.keys(), ...holds.keys()]) assert(rows.some(r => r.skuId === id), `Missing exact target: ${id}`);
// Conservative name-family gate. The UI includes Product Type in its grouping
// key; a partial assignment would split the four existing Everyday pack sizes.
// This gate is not certification of every UI-normalized product family.
for (const r of rows) {
  r.releaseBlockers = [];
  if (!r.proposedProductType) continue;
  const family = rows.filter(x => x.brand === r.brand && x.name === r.name && x.canonicalSubcategory.slug === r.canonicalSubcategory.slug);
  if (family.some(x => x.proposedProductType !== r.proposedProductType)) {
    r.releaseBlockers.push('Partial classification would split an existing same-name pack family. Resolve all family members first.');
  }
  if (family.some(x => x.proposedContentRepairs.length)) {
    r.releaseBlockers.push('Resolve the 15 g legacy infant-formula description through an approved content correction, then classify all four Everyday packs together.');
  }
}
assert.equal(rows.filter(r => r.proposedProductType && r.releaseBlockers.length).length, 4);
const digest = createHash('sha256').update(JSON.stringify([...rows].sort((a,b) => a.skuId.localeCompare(b.skuId)))).digest('hex');
const review = {
  preparedOn: '2026-10-09', scope: 'All active existing SKUs; product-type proposals only; no production updates',
  reference: { directory: '/Users/Furqan/Downloads/Catalogue Map Dastak', screenshots: 90, visuallyCheckedMilkRail: 'IMG_3329.PNG', briefSection: '32: Product Type Filter' },
  limitations: ['The reference and brief do not provide an exhaustive Product Type dictionary.', 'Inventory coverage is complete; product-specific classification research is not complete.', 'Eight explicit milk-pack suggestions have manufacturer support; the Nestle 15 g announcement explicitly names that pack size.', 'Existing SKU names and canonical subcategories are not treated as universally reliable classification evidence.', 'No SKU IDs, pack content, stock, prices, map paths or attributes were changed.'],
  counts: { activeSkus: rows.length, supportedProposals: 8, proposalsBlockedByPackFamily: 4, explicitHolds: 10, notYetClassified: rows.length - 18, proposedDescriptionRepairs: 1, productionClassificationsChanged: 0 },
  reviewSha256: digest, rows,
};
mkdirSync(outputDirectory, { recursive: true });
writeFileSync(resolve(outputDirectory, 'dastak-product-type-review-2026-10-09.json'), JSON.stringify(review, null, 2) + '\n');
const esc = value => String(value ?? '—').replaceAll('|', '\\|').replaceAll('\n', ' ');
const supported = rows.filter(r => r.proposedProductType);
const held = rows.filter(r => r.status.startsWith('HOLD'));
let md = `# Dastak Product Type review — 9 October 2026\n\nLocal proposal only. **Nothing in this document is approved or applied to production.**\n\n## Coverage and limits\n\n- 572 active existing SKUs inventoried; all 572 have exactly one active browse destination and one rail.\n- 8 supported suggestions, 10 explicit holds, 554 entries not yet classified.\n- Inventory coverage is complete; classification research is **not** complete.\n- Reference: 90 screenshots in Catalogue Map Dastak. IMG_3329.PNG was visually checked for the Milk rail. Brief section 32 supplies example filter values, not a complete classification dictionary.\n- Product Type is separate from flavour, pack size and variant. No new reference-only products or Skimmed Milk SKUs are proposed.\n- Manufacturer sources support product lines; they do not certify every exact Dastak pack or its structured quantity. Nestle's 2023 announcement explicitly confirms Everyday 15 g, but is not evidence of current pack artwork or formula.\n- There are no SQL updates or migration instructions in this review. Before any later update: obtain approval, re-export current versions and metadata, reject drift, preserve other attributes, use the existing version-protected Admin update path, and verify Customer/Merchant/Admin results.\n\n## Supported first batch: Milk\n\n| Exact existing SKU | Pack | Proposed Product Type | Evidence |\n|---|---|---|---|\n`;
for (const r of supported) md += `| ${esc(r.name)} | ${esc(r.packSize)} | ${r.proposedProductType} | [Manufacturer product line](${r.evidence[0].url}) |\n`;
md += `\nAll eight remain awaiting review. The four Nestle suggestions are **blocked for release** until the 15 g description correction is approved and applied. Classify all four packs together, never only three. Only the four Amul/Arokya suggestions have no identified same-name family blocker in this pass; they still require approval and a fresh preflight. This narrow gate does not certify every normalized product family.\n\n### Everyday 15 g content correction proposal\n\n- Exact existing SKU: \`${everyday15Id}\`, version 9 in the refreshed read-only check.\n- Current description: “${staleEverydayDescription}”\n- Proposed description: “Dairy whitener for tea and coffee.”\n- Keep SKU ID, slug, pack sizes, prices, stock and merchant links unchanged. The legacy slug remains stable deliberately; it is not a reason to rename or replace the SKU.\n- Evidence: [Nestle's announcement explicitly names Everyday 15 g](${nestle15}). The linked row has the Everyday name and 15 g pack; recorded update outbox versions 3–5 also have the Everyday name while retaining the legacy infant-formula slug. That corroborates stale content but does not reveal the complete original creation history.\n- This is a proposed correction, not an applied fix. Structured quantity still requires separate review.\n\nDairy Whitener is a proposed useful filter value for existing products, not a new product or a change of rail. Other products stay available under All when they have no Product Type.\n\n## Explicit holds\n\n| SKU / pack | Exact SKU ID | Why blank |\n|---|---|---|\n`;
for (const r of held) md += `| ${esc(r.name)} / ${esc(r.packSize)} | ${r.skuId} | ${esc(r.reason)} |\n`;
md += '\nThese are evidence conflicts, not approved content fixes. The generic structured-quantity warnings in the JSON also need separate content review; this pass does not resolve them.\n\n## Full SKU-by-SKU register\n\nEvery active SKU is included below and in the companion JSON with its exact ID, expected version, paths, evidence and warnings. Blank entries are outstanding work, not verified assignments.\n\n';
const groups = new Map();
for (const r of rows) { const key = `${r.destination.label} / ${r.rail.label}`; if (!groups.has(key)) groups.set(key, []); groups.get(key).push(r); }
for (const [group, products] of groups) {
  md += `### ${esc(group)}\n\n| SKU ID (version) | Existing product | Pack | Proposed type | Review status |\n|---|---|---|---|---|\n`;
  for (const r of products) md += `| ${r.skuId} (v${r.expectedVersion}) | ${esc(r.name)} | ${esc(r.packSize)} | ${esc(r.proposedProductType)} | ${r.status === 'NOT_YET_CLASSIFIED' ? 'Not yet classified' : r.status.startsWith('HOLD') ? 'Hold' : 'Supported; awaiting review'} |\n`;
  md += '\n';
}
md += `Review SHA-256: \`${digest}\`\n`;
writeFileSync(resolve(outputDirectory, 'dastak-product-type-review-2026-10-09.md'), md);
console.log(JSON.stringify({ ...review.counts, uniqueSkuIds: new Set(rows.map(r => r.skuId)).size, allAwaitingApproval: rows.every(r => !r.approved), reviewSha256: digest }));
