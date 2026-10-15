# Dastak Product Type review — 9 October 2026

Historical pre-approval proposal. **The eight Milk suggestions and one Everyday 15 g description correction were subsequently approved and applied; see [release receipt](dastak-milk-release-2026-10-09.md).** The statuses and versions below record the original review snapshot; all other proposals/holds remain unapproved.

## Coverage and limits

- 572 active existing SKUs inventoried; all 572 have exactly one active browse destination and one rail.
- 8 supported suggestions, 10 explicit holds, 554 entries not yet classified.
- Inventory coverage is complete; classification research is **not** complete.
- Reference: 90 screenshots in Catalogue Map Dastak. IMG_3329.PNG was visually checked for the Milk rail. Brief section 32 supplies example filter values, not a complete classification dictionary.
- Product Type is separate from flavour, pack size and variant. No new reference-only products or Skimmed Milk SKUs are proposed.
- Manufacturer sources support product lines; they do not certify every exact Dastak pack or its structured quantity. Nestle's 2023 announcement explicitly confirms Everyday 15 g, but is not evidence of current pack artwork or formula.
- There are no SQL updates or migration instructions in this review. Before any later update: obtain approval, re-export current versions and metadata, reject drift, preserve other attributes, use the existing version-protected Admin update path, and verify Customer/Merchant/Admin results.

## Supported first batch: Milk

| Exact existing SKU | Pack | Proposed Product Type | Evidence |
|---|---|---|---|
| Nestle Everyday Dairy Whitener | 200 g | Dairy Whitener | [Manufacturer product line](https://www.nestle.in/brands/nestleeverydaydairywhitener) |
| Nestle Everyday Dairy Whitener | 15 g | Dairy Whitener | [Manufacturer product line](https://www.nestle.in/media/pressreleases/allpressreleases/nestl%C3%A9-everyday-tata-tea-kanan-devan-partner-perfect-cup-tea) |
| Nestle Everyday Dairy Whitener | 1 kg | Dairy Whitener | [Manufacturer product line](https://www.nestle.in/brands/nestleeverydaydairywhitener) |
| Nestle Everyday Dairy Whitener | 400 g | Dairy Whitener | [Manufacturer product line](https://www.nestle.in/brands/nestleeverydaydairywhitener) |
| Arokya Full Cream Milk | 1 L | Full Cream | [Manufacturer product line](https://www.hap.in/arokya/full-cream-milk.html) |
| Amul Taaza Toned Milk | 1 L | Toned | [Manufacturer product line](https://old.amul.com/products/amul-uhttaaza-info.php) |
| Amul Taaza Toned Milk | 200 ml | Toned | [Manufacturer product line](https://old.amul.com/products/amul-uhttaaza-info.php) |
| Arokya Toned Milk | 500 ml | Toned | [Manufacturer product line](https://www.hap.in/arokya/toned-milk.html) |

All eight remain awaiting review. The four Nestle suggestions are **blocked for release** until the 15 g description correction is approved and applied. Classify all four packs together, never only three. Only the four Amul/Arokya suggestions have no identified same-name family blocker in this pass; they still require approval and a fresh preflight. This narrow gate does not certify every normalized product family.

### Everyday 15 g content correction proposal

- Exact existing SKU: `2642d986-1130-4d4a-88bf-d0da178469d7`, version 9 in the refreshed read-only check.
- Current description: “Curated infant milk formula for Dastak grocery delivery.”
- Proposed description: “Dairy whitener for tea and coffee.”
- Keep SKU ID, slug, pack sizes, prices, stock and merchant links unchanged. The legacy slug remains stable deliberately; it is not a reason to rename or replace the SKU.
- Evidence: [Nestle's announcement explicitly names Everyday 15 g](https://www.nestle.in/media/pressreleases/allpressreleases/nestl%C3%A9-everyday-tata-tea-kanan-devan-partner-perfect-cup-tea). The linked row has the Everyday name and 15 g pack; recorded update outbox versions 3–5 also have the Everyday name while retaining the legacy infant-formula slug. That corroborates stale content but does not reveal the complete original creation history.
- This is a proposed correction, not an applied fix. Structured quantity still requires separate review.

Dairy Whitener is a proposed useful filter value for existing products, not a new product or a change of rail. Other products stay available under All when they have no Product Type.

## Explicit holds

| SKU / pack | Exact SKU ID | Why blank |
|---|---|---|
| RiteBite Peanut Butter Bar (Pack of 12) / 1 unit × 12 | a8bcb2e9-cd42-43ee-8105-91ef2ce3e1aa | Peanut Butter Bar multipack is under Peanut Butters, while a similarly named single bar is under Protein Bars. Confirm product identity and appropriate rail. |
| Amul Pasteurised Butter / 100 g | f6f936e6-ff4c-4920-b5bf-6181edaa90c2 | Same Amul Pasteurised Butter name is split between salted and unsalted canonical subcategories across pack sizes. Check actual packs, not their paths. |
| Amul Pasteurised Butter / 500 g | 2f5eee78-0a5c-492b-a578-71ed1f259255 | Same Amul Pasteurised Butter name is split between salted and unsalted canonical subcategories across pack sizes. Check actual packs, not their paths. |
| Amul Pasteurised Butter / 200 g | afdd4039-1717-4db8-8f32-9a05ba57fb6d | Same Amul Pasteurised Butter name is split between salted and unsalted canonical subcategories across pack sizes. Check actual packs, not their paths. |
| Amul Processed Cheese Cubes / 500 g | 02e45397-40ef-4226-9365-df1e58f7a0ce | Processed Cheese Cubes name is under Cheese Blocks; the 200 g pack is under Cheese Slices. Resolve form/path conflict. |
| Amul Processed Cheese Cubes / 200 g | 7a55f61a-d128-492b-a4b3-ee84c833d821 | Processed Cheese Cubes name is under Cheese Slices; the 500 g pack is under Cheese Blocks. Resolve form/path conflict. |
| Aavin Delite Milk / 500 ml | ad8ffcb7-6615-4ad0-a36d-c79bf944a1ab | Aavin Delite name does not establish Full Cream. Its current canonical subcategory alone is not sufficient evidence. |
| Aavin Full Cream Milk / 500 ml | 278b1418-3ff6-4398-ba51-132b559fc035 | Aavin Full Cream name suggests Full Cream, but no manufacturer or verified pack evidence was obtained in this pass. |
| Aavin Nice Toned Milk / 500 ml | b5bb8877-b01e-40fe-a306-7f61a2e6d131 | Aavin Nice Toned name suggests Toned, but no manufacturer or verified pack evidence was obtained in this pass. |
| Ching's Secret Chowmein Hakka Noodles Masala \| No need to add salt, spices, or condiments \| Authentic Desi Chinese \| Easy to Cook \| 100% Veg \| 7g 7 g / 7 g | 41ca4536-c609-433f-9bdc-310c4d3aad0c | Name describes Hakka Noodles Masala but its canonical subcategory is Hakka Noodles. Confirm seasoning versus noodles and appropriate rail. |

These are evidence conflicts, not approved content fixes. The generic structured-quantity warnings in the JSON also need separate content review; this pass does not resolve them.

## Full SKU-by-SKU register

Every active SKU is included below and in the companion JSON with its exact ID, expected version, paths, evidence and warnings. Blank entries are outstanding work, not verified assignments.

### Cold Drinks and Juices / Caffeinated Beverages

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 189045cf-a7c9-4742-991f-0421a197935c (v9) | Red Bull | 250 mL | — | Not yet classified |
| 63ab4c0e-946a-4d43-a421-f786297bdded (v9) | Red Bull Sugar Free | 250 mL | — | Not yet classified |
| 65a0bda2-d83b-4b7a-a288-16acb22b3fc0 (v9) | Red Bull The Yellow Edition | 250 mL | — | Not yet classified |

### Biscuits and Cakes / Cookies

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 3f090bfc-4f09-4893-8da5-a1a67c0ff14c (v4) | Max Protein Choco Chips Bliss  Cookies | 1 unit | — | Not yet classified |
| 4032ee36-1a67-47e5-8d31-3cd13e3bca28 (v4) | Max Protein Choco Chips Cookie (Pack of 1) | 1 unit | — | Not yet classified |
| 65727386-eabe-47cf-bee6-d4651a0321ba (v4) | Max Protein Choco Chips Cookie (Pack of 6) | 1 unit × 6 | — | Not yet classified |
| 3b80eb06-e0da-40dd-bd60-b84d133e7505 (v4) | RiteBite Max Protein Berry Bliss Crunchy Cookies 1 unit | 1 unit | — | Not yet classified |
| 81e9d68a-db1f-46e2-857c-48971feb12c4 (v4) | RiteBite Max Protein Choco Coconut Cookie (Pack of 12) 1 unit × 12 | 1 unit | — | Not yet classified |
| 001ff35a-1783-4b6b-a59e-198d6dba7ac3 (v4) | RiteBite Max Protein Choco Coconut Cookie (Pack of 6) 1 unit × 6 | 1 unit | — | Not yet classified |
| d508d505-d59f-4fca-82b0-efbbdd3e524b (v4) | RiteBite Max Protein Coconut Delite Cookie (Pack of 12) 1 unit × 12 | 1 unit | — | Not yet classified |
| 80ede452-1f1d-4ea6-b3c9-4fe7288134be (v4) | RiteBite Max Protein Coconut Delite Cookie (Pack of 6) 1 unit × 6 | 1 unit | — | Not yet classified |
| 5fe2c54b-f235-4061-b8fa-f58011604fd2 (v4) | RiteBite Max Protein Cookies Choco Almond (Pack of 12) 720g \| Zero Added Sugar 720 g × 12 | 720 g | — | Not yet classified |
| 880c519a-a8ca-48b7-9b9f-307dfad6b36a (v4) | RiteBite Max Protein Cookies Choco Almond 60 g | 60 g | — | Not yet classified |
| 8ad2c010-7dbb-4787-865a-5c0673ec1de3 (v4) | RiteBite Max Protein Nuts & Seeds Cookie (Pack of 6) 1 unit × 6 | 1 unit | — | Not yet classified |
| cb3a771f-096e-4e0f-89cd-2a924e4100f4 (v4) | RiteBite Max Protein Nuts & Seeds Cookie 1 unit | 1 unit | — | Not yet classified |
| 93d2fb4f-a84d-48b8-bbe9-825f6711df00 (v4) | RiteBite Max Protein Nuts & Seeds Cookie 1 unit × 12 | 1 unit | — | Not yet classified |
| bf3614aa-fdd9-4326-8b5c-f3b578d4d9b8 (v4) | RiteBite Max Protein Oats & Raisins Cookie 1 unit | 1 unit | — | Not yet classified |
| 5927417c-3dcf-4452-81d3-4d67ea176224 (v4) | RiteBite Max Protein Oats & Raisins Cookie 1 unit × 12 | 1 unit | — | Not yet classified |
| 15a610ce-df12-461c-9ca0-06ebbbb14c24 (v4) | RiteBite Max Protein Trail Mix Cookie 1 unit | 1 unit | — | Not yet classified |

### Biscuits and Cakes / Wafers, Rusk & Crackers

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| d03ee52c-2698-48b1-aa8b-7de94845ced8 (v5) | Amul T-Special Rusk - Super Family Pack | 700 g | — | Not yet classified |

### Cereals and Breakfast / Kids Cereals

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| edee8afe-298b-4d92-9ef6-1a075b94d068 (v8) | Tata Soulfull Ragi Bites - Choco Fills 250 g | 250 g | — | Not yet classified |
| df6d8409-39f8-4cd9-bf31-93b70df86ed1 (v8) | Tata Soulfull Ragi Bites - Choco Fills 500 g | 500 g | — | Not yet classified |

### Sauces and Spreads / Honey and Cider Vinegar

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| cdd3ba06-0fc3-454b-af4c-272b053d35b6 (v5) | Amul Honey | 250 g × 3 | — | Not yet classified |

### Cereals and Breakfast / Ready Mixes

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 24139972-685b-4dff-bf50-efd0a3826f88 (v7) | MTR Dhokla Mix 200 g | 200 g | — | Not yet classified |
| 3191a0e0-d38a-4f81-946a-f55fb94d90ec (v7) | MTR Dosa Mix with 10g Protein 250 g | 250 g | — | Not yet classified |
| fcd49304-4bee-4df1-9329-dcf825fda7ff (v7) | MTR Multigrain Dosa Mix 500 g | 500 g | — | Not yet classified |
| 63717878-50fa-4840-b386-88089a4321c8 (v7) | MTR Ragi Dosa Mix 500 g | 500 g | — | Not yet classified |
| a15b7dd6-930e-4f52-afe6-9b56baa3211a (v7) | MTR Rava Dosa Mix 500 g | 500 g | — | Not yet classified |
| 6b442dad-1db2-42ad-a54b-d97dab46e381 (v7) | MTR Rice Dosa Mix 1 kg | 1 kg | — | Not yet classified |
| ec2b0941-07ee-4dc2-bfb4-8a4975ede01c (v7) | MTR Rice Dosa Mix 200 g | 200 g | — | Not yet classified |
| dfc2b54a-2445-40cf-abbf-a609c2231939 (v7) | MTR Rice Dosa Mix 500 g | 500 g | — | Not yet classified |
| 0816620a-0ee4-4df1-90df-6596ec85aaa0 (v7) | Aachi Rava Idly Mix 500 g | 500 g | — | Not yet classified |
| a59d8aae-01a0-46b3-8394-af6539857a27 (v7) | MTR Masala Rava Idli Mix 500 g | 500 g | — | Not yet classified |
| 4a5407ec-90bc-4b76-8008-ac3ec3541561 (v7) | MTR Oats Idli Mix 500 g | 500 g | — | Not yet classified |
| 3d8db91c-7307-46bf-8f63-b5b5640cde7a (v7) | MTR Rava Idli Mix 1 kg | 1 kg | — | Not yet classified |
| 63d54c9a-3181-4dac-8f2b-9d2ba4fb24b8 (v7) | MTR Rava Idli Mix 200 g | 200 g | — | Not yet classified |
| e4098633-86d0-46b9-954d-e3b044be0fbd (v7) | MTR Rava Idli Mix 500 g | 500 g | — | Not yet classified |
| ad753afa-eb4d-4d8b-a204-cc84fbf9b2bb (v7) | MTR Rava Idli Mix with 10g Protein 250 g | 250 g | — | Not yet classified |
| 3a164966-0663-4bbe-a5ab-41f13eaff21c (v7) | MTR Rice Idli Mix 1 kg | 1 kg | — | Not yet classified |
| fe2a8922-015b-46b4-b23f-891a0b6e1dad (v7) | MTR Rice Idli Mix 200 g | 200 g | — | Not yet classified |
| 71478b64-aafd-4494-a0e6-45ab1f9b8886 (v7) | MTR Rice Idli Mix 500 g | 500 g | — | Not yet classified |
| 30b7b56a-6090-4507-8bd4-e033b078052f (v7) | MTR 3 Minute Khatta Meetha Poha Cup 80 g | 80 g | — | Not yet classified |
| 7a777155-23db-44df-b58f-a4a0ad2261dc (v7) | MTR 3 Minute Khatta Meetha Poha with 10g Protein 80 g | 80 g | — | Not yet classified |
| 5bb7126c-32b1-412d-9c37-de4098751f9a (v7) | MTR 3 Minute Poha Pouch ( Pack of 5 ) 60 g ×5 | 60 g | — | Not yet classified |
| c000b8b1-b904-42b9-a7b6-1b10d86444fc (v7) | MTR 3 Minute Poha with 10g Protein 80 g | 80 g | — | Not yet classified |
| 80a809d2-8b56-49ee-95c6-e69565751f2a (v7) | MTR 3 Minute Magic Masala Upma Cup 80 g | 80 g | — | Not yet classified |
| 089379f5-b700-4179-880e-f9dcdf7c1c86 (v7) | MTR 3 Minute Veggie Upma (Pack of 5) 60 g ×5 | 60 g | — | Not yet classified |
| 71e2b6cb-f2da-4d4c-96d6-569f1448cf9c (v7) | MTR 3 Minute Veggie Upma with 10g Protein 80 g | 80 g | — | Not yet classified |
| 6c88de6a-c177-4486-b1f1-ee6d397a136a (v7) | MTR Upma Mix 160 g | 160 g | — | Not yet classified |
| a75a6b25-d78b-4206-82f3-3577d17b03b2 (v7) | MTR Upma Mix 500 g | 500 g | — | Not yet classified |
| 640a70cf-260c-48f9-8218-a99db4a29713 (v7) | MTR Upma Mix with 10g Protein 250 g | 250 g | — | Not yet classified |
| 72f8b2b3-21fa-4f43-b080-df18d6b5d116 (v7) | MTR Uttappam Mix 500 g | 500 g | — | Not yet classified |
| c0a7169a-29dc-4b8f-85d0-2af1bfb76545 (v7) | MTR Vada Mix 200 g | 200 g | — | Not yet classified |
| dd977f2f-0944-4a56-96ec-c7a764dcf9b3 (v7) | MTR Vada Mix 500 g | 500 g | — | Not yet classified |

### Cereals and Breakfast / Muesli & Granola

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 694ef596-0420-4b98-839f-f031ef1cd711 (v8) | Tata Soulfull Millet Muesli - 0% Added Sugar \| High in fibre  \| High in Protein \| Made with 97% whole grains, fruit, nuts and seeds \| 500g / 700g 500 g | 500 g | — | Not yet classified |
| 17ef4b27-b4b5-4951-8fc8-0a7145cd9371 (v8) | Tata Soulfull Millet Muesli - 0% Added Sugar \| High in fibre  \| High in Protein \| Made with 97% whole grains, fruit, nuts and seeds \| 500g / 700g 700 g | 700 g | — | Not yet classified |
| 1dcb03a6-d082-422a-b653-42ca8b79375a (v10) | Tata Soulfull Millet Muesli - Crunchy \| Source of Protien \| High in dietry fibre \| 80% Whole Grains, Nuts & Fruits \| 500g / 700g / 1.2Kg 1.2 kg | 1.2 kg | — | Not yet classified |
| 1bdf95b1-a5b0-413f-b95c-0b5e8379aaa1 (v10) | Tata Soulfull Millet Muesli - Crunchy \| Source of Protien \| High in dietry fibre \| 80% Whole Grains, Nuts & Fruits \| 500g / 700g / 1.2Kg 500 g | 500 g | — | Not yet classified |
| e0bee7b9-5495-4c05-a62e-0e870a617f67 (v10) | Tata Soulfull Millet Muesli - Crunchy \| Source of Protien \| High in dietry fibre \| 80% Whole Grains, Nuts & Fruits \| 500g / 700g / 1.2Kg 700 g | 700 g | — | Not yet classified |
| d6306489-b1ee-40b5-ad5d-02ae1940e933 (v8) | Tata Soulfull Millet Muesli - Fruit, Nuts & Seeds \| 30% Fruits, Nut & Seeds \| High Protein \| 500g 500 g | 500 g | — | Not yet classified |
| fb5b9faa-c089-4fa4-8139-bc89f4022634 (v8) | Tata Soulfull Millet Muesli - Fruits, Nuts & Seeds \| 90% Whole Grains, Fruits and Nuts \| High in Fibre \| Source Of Protein \| 500g / 700g / 1.2Kg 1.2 kg | 1.2 kg | — | Not yet classified |
| 8c9c131d-dfb5-4c59-98c3-3fc0b4f92834 (v8) | Tata Soulfull Millet Muesli - Fruits, Nuts & Seeds \| 90% Whole Grains, Fruits and Nuts \| High in Fibre \| Source Of Protein \| 500g / 700g / 1.2Kg 500 g | 500 g | — | Not yet classified |
| 4d826001-93e2-490e-a3e2-b7c8826028ed (v8) | Tata Soulfull Millet Muesli - Fruits, Nuts & Seeds \| 90% Whole Grains, Fruits and Nuts \| High in Fibre \| Source Of Protein \| 500g / 700g / 1.2Kg 700 g | 700 g | — | Not yet classified |

### Cereals and Breakfast / High protein oats & muesli

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 7e8b439a-137d-4d94-9141-99527951d4a1 (v4) | Max Protein Granola - Choco Crunchy - 500g | 500 g | — | Not yet classified |
| ee5a7eae-f727-4faf-a080-20789e05a520 (v4) | Max Protein Granola - Fruits & Nuts - 500g | 500 g | — | Not yet classified |
| 6def3049-2cc2-427f-bd66-ec6578126e97 (v4) | Max Protein Granola - No Added Sugar - 500g | 500 g | — | Not yet classified |
| 1e22c5ce-997d-4da2-b841-df0a73150728 (v8) | Tata Soulfull Tata Soulfull Protein Berry Chia 35 g | 35 g | — | Not yet classified |
| 1fbef2ea-701f-4b1d-8178-97b44fb99f0e (v8) | Tata Soulfull Tata Soulfull Protein Berry Chia 375 g | 375 g | — | Not yet classified |
| a60be443-86c8-4e90-9b94-88f9e74449f9 (v8) | Tata Soulfull Tata Soulfull Protein Dark Cocoa 35 g | 35 g | — | Not yet classified |
| 80afffa1-b8a5-4640-b782-8644aa7e45ca (v8) | Tata Soulfull Tata Soulfull Protein Dark Cocoa 375 g | 375 g | — | Not yet classified |
| f53de505-d5c2-4a76-a41a-2c2a916c1480 (v8) | Tata Soulfull Tata Soulfull Protein Masala 35 g | 35 g | — | Not yet classified |
| bdcdfce9-00fa-4f6e-a599-1adf93c00be4 (v8) | Tata Soulfull Tata Soulfull Protein Masala 375 g | 375 g | — | Not yet classified |

### Cereals and Breakfast / Masala Oats

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 20a19761-6c84-4c77-9e1b-60f46655d9fc (v8) | Tata Soulfull Masala Oats - Dal Shakti \| Ready in 4 Minutes \| High in Fibre & Source of Protein \| 500g 500 g | 500 g | — | Not yet classified |
| a3b698c5-3563-415e-a23f-9b4e471377a8 (v7) | Tata Soulfull Masala Oats - Desi Veggie \| 25% Millets, Real Veggies \| Healthy Evening Snack \| Non Sticky \| 500g 500 g | 500 g | — | Not yet classified |
| e2aa4305-5dc1-4ddd-8063-37455984fb2c (v8) | Tata Soulfull Masala Oats - Tomato \| 25% Millets, Real Veggies \| Healthy Evening Snack \| Non Sticky \| 500g 500 g | 500 g | — | Not yet classified |

### Sweet Corner / Dessert Mixes

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 6d434d35-608f-4ebb-95aa-70004fb959ee (v7) | Aachi Palada Payasam Mix 175 g | 175 g | — | Not yet classified |
| 4f035b5e-eaf8-4c46-9224-a191e2b969ec (v7) | Aachi Rava Kesari Mix 180 g | 180 g | — | Not yet classified |
| a1cea4be-b934-4da8-a7bd-31af85c233cf (v7) | Aachi Royal Badam Payasam Mix 175 g | 175 g | — | Not yet classified |
| 4655ea75-ad54-4863-bd3f-9ff2a80a1d8d (v7) | Aachi Royal Gulab Jamun Mix 175 g | 175 g | — | Not yet classified |
| 8657535a-37d0-42a3-8053-dc75370bbaea (v7) | Aachi Royal Semiya Payasam Mix 100 g | 100 g | — | Not yet classified |
| 690e93c1-0907-4f20-ba0a-230fc6a1a20f (v7) | Aachi Royal Semiya Payasam Mix 175 g | 175 g | — | Not yet classified |
| 0124c5a5-fa06-42b0-904f-6277d7ee621a (v7) | MTR Gulab Jamun Mix 1 kg | 1 kg | — | Not yet classified |
| 4843cf20-cd30-4961-95ca-664f28f1daa8 (v7) | MTR Gulab Jamun Mix 175 g | 175 g | — | Not yet classified |
| 7c6844d1-88a7-4690-bc8a-3b48b74611bc (v7) | MTR Gulab Jamun Mix 500 g | 500 g | — | Not yet classified |
| 13cf1e85-0991-4365-a6dd-7c8788c9e3dc (v7) | MTR Gulab Jamun Tin Can 1 kg | 1 kg | — | Not yet classified |
| 5bd034b0-ed0c-4062-becb-6ae9a908fb20 (v7) | MTR Gulab Jamun Tin Can 500 g | 500 g | — | Not yet classified |
| f3244ace-9b31-4823-9783-30586901464c (v7) | MTR Kesar Badam Gulab Jamun 1 kg | 1 kg | — | Not yet classified |
| bf3550a8-975f-4a81-9330-d4cf000259ab (v7) | MTR Kesar Badam Gulab Jamun 500 g | 500 g | — | Not yet classified |
| fd178aaf-b205-45b5-85b1-7b0c22bc0c53 (v7) | MTR Vermicelli Payasam - Seviyan Kheer Mix 100 g | 100 g | — | Not yet classified |
| 80272481-6512-47c0-8bd6-8a34312ff465 (v7) | MTR Vermicelli Payasam - Seviyan Kheer Mix 180 g | 180 g | — | Not yet classified |

### Sauces and Spreads / Mayo & Spreads

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| f8927913-bfb9-4e97-99db-6f85d84abfe1 (v5) | Snackible Salted Caramel Spread 250 g | 250 g | — | Not yet classified |
| 903bd376-113e-4b32-9b18-ed19bdc6f8e7 (v7) | Snackible Hazelnut Spread 250 g | 250 g | — | Not yet classified |
| 564932a3-af66-4ea3-ac01-a721eb5275fc (v7) | Snackible Pistachio Spread 250 g | 250 g | — | Not yet classified |
| f7c01498-6105-4460-863e-6ae5efad642a (v5) | Snackible Vanilla Creme Spread 250 g | 250 g | — | Not yet classified |

### Sauces and Spreads / Chocolate Spreads

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| abd112b1-6a7b-4ba6-a627-0531e2bb9299 (v5) | Snackible Chocolatey Spread  \| No Refined Sugar 250 g | 250 g | — | Not yet classified |

### Sauces and Spreads / Jams

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 1b3c5ced-ca69-44b1-956f-3c8ad9797281 (v7) | Aachi Mixed Fruit Jam 200 g | 200 g | — | Not yet classified |

### Sauces and Spreads / Peanut Butters

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| e0be6956-cff0-4893-a465-f577151d9db1 (v4) | Max Protein Jaggery Crunchy Spread | 1 unit | — | Not yet classified |
| c1a363d9-0594-4523-b9e9-711a55e7a982 (v4) | Max Protein Peanut Butter Dark Choco Crunchy | 1 unit | — | Not yet classified |
| 26429436-a23d-46cd-a420-2c60667e7ed7 (v6) | Max Protein Peanut Butter Unsweetened Creamy - 1kg | 1 kg | — | Not yet classified |
| a3ffb33b-dda2-43d6-ad0f-15bed124efaa (v6) | Max Protein Peanut Butter Unsweetened Crunchy - 1kg | 1 kg | — | Not yet classified |
| 79bc9f5a-9337-4e26-b2cf-9441b0059ad6 (v4) | RiteBite Max Protein Peanut Butter Choco Creamy 340 g | 340 g | — | Not yet classified |
| 24418841-654a-4342-ac02-b00c9598e805 (v4) | RiteBite Max Protein Peanut Butter Classic Creamy 340 g | 340 g | — | Not yet classified |
| daa2490d-d1bf-4f1c-b7be-cfdaf28b7a98 (v4) | RiteBite Max Protein Peanut Butter Classic Crunchy 340 g | 340 g | — | Not yet classified |
| a8bcb2e9-cd42-43ee-8105-91ef2ce3e1aa (v4) | RiteBite Peanut Butter Bar (Pack of 12) | 1 unit × 12 | — | Hold |

### Dairy, Bread & Eggs / Batters and Chutneys

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| df63fb0a-fa61-45a5-8317-0766e366a1be (v9) | Ching's Secret Jain Schezwan Chutney 250 g | 250 g | — | Not yet classified |
| 5d529e56-ef66-4f8f-b5d1-0a237aa65a62 (v9) | Ching's Secret Schezwan Chutney \| Fiery Flavour Fusion \| Easy to Cook, Dip and Spread \|Rich flavours \| 100% Veg \| 30g / 250g / 590g 250 g | 250 g | — | Not yet classified |
| e10ed93e-941b-4dad-bc6f-a98eadea406e (v9) | Ching's Secret Schezwan Chutney \| Fiery Flavour Fusion \| Easy to Cook, Dip and Spread \|Rich flavours \| 100% Veg \| 30g / 250g / 590g 30 g | 30 g | — | Not yet classified |
| 475fe40b-95be-420e-b761-f8d1ea30a55f (v9) | Ching's Secret Schezwan Chutney \| Fiery Flavour Fusion \| Easy to Cook, Dip and Spread \|Rich flavours \| 100% Veg \| 30g / 250g / 590g 590 g | 590 g | — | Not yet classified |
| 02aa64b5-90d6-44e5-98f3-db3db928bc5e (v8) | MTR Coconut Chutney 80 g | 80 g | — | Not yet classified |
| ba9635ef-9c9e-4db1-b555-6bbbe548546e (v8) | MTR Idli Dosa Chilly Chutney Powder 100 g | 100 g | — | Not yet classified |
| 7cf12775-808d-4883-b289-9a991af60700 (v8) | MTR Idli Dosa Chilly Chutney Powder 200 g | 200 g | — | Not yet classified |

### Dairy, Bread & Eggs / Bread and Buns

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| f27b00f8-766d-47ee-a42d-08427f365683 (v7) | Plain Buns | 1 pack | — | Not yet classified |

### Dairy, Bread & Eggs / Butter

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 1c65bab5-cca0-453f-bbda-7267ae07234f (v6) | Amul Garlic & Herbs Buttery Spread 100 g | 100 g | — | Not yet classified |
| f6f936e6-ff4c-4920-b5bf-6181edaa90c2 (v8) | Amul Pasteurised Butter | 100 g | — | Hold |
| cfc5d8e4-c19a-4960-8d07-2fb9a747adca (v4) | Milky Mist Butter Chiplet | 100 g | — | Not yet classified |
| 2ad98484-b4cf-4ee4-906a-c420cb123ce1 (v4) | Milky Mist Table Butter | 100 g | — | Not yet classified |
| 86a3c496-5a42-4601-a905-578b0be678f8 (v4) | Milky Mist Table Butter | 200 g | — | Not yet classified |
| a04e8308-69df-4004-9bfb-6816c8b1830d (v4) | Milky Mist Table Butter | 500 g | — | Not yet classified |
| fe66bde6-b9a8-4ac7-ab75-fca59eb876a8 (v9) | Amul Butter Chiplets | 100 g | — | Not yet classified |
| 2f5eee78-0a5c-492b-a578-71ed1f259255 (v9) | Amul Pasteurised Butter | 500 g | — | Hold |
| afdd4039-1717-4db8-8f32-9a05ba57fb6d (v9) | Amul Pasteurised Butter | 200 g | — | Hold |
| 4db65298-eff7-4231-a7f1-741ed3c59642 (v4) | Milky Mist Cooking Butter | 500 g | — | Not yet classified |
| 59938a44-3025-4885-a18d-06b1c1ca7412 (v3) | Milky Mist Cooking Butter | 200 g | — | Not yet classified |
| ccca2377-1c49-4970-a85e-9de2345e8b9c (v4) | Milky Mist Cooking Butter | 100 g | — | Not yet classified |

### Dairy, Bread & Eggs / Cheese

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| f9e336ee-3c1a-4b01-87ec-e4ba3d72c928 (v9) | Amul Processed Cheese Block | 200 g | — | Not yet classified |
| fd249407-13e0-4a3c-b583-73385139fd5e (v8) | Amul Processed Cheese Block | 500 g | — | Not yet classified |
| 02e45397-40ef-4226-9365-df1e58f7a0ce (v9) | Amul Processed Cheese Cubes | 500 g | — | Hold |
| 0e2b47f3-f4d1-42c9-8b65-c16a28bc479f (v5) | Milky Mist Processed Cheese Block | 200 g | — | Not yet classified |
| a3abcd98-4630-4c2a-b969-d19e5af8e15b (v5) | Milky Mist Processed Cheese Block | 500 g | — | Not yet classified |
| b639c35f-9972-466e-936a-8d4550c5c390 (v6) | Milky Mist Processed Cheese Cubes | 200 g | — | Not yet classified |
| 7a55f61a-d128-492b-a4b3-ee84c833d821 (v9) | Amul Processed Cheese Cubes | 200 g | — | Hold |
| 8e69990f-1d13-4d95-91cd-894683dfeda4 (v8) | Amul Processed Cheese Slices | 400 g | — | Not yet classified |
| a8deb40e-ad80-44f1-a148-f26be1944f94 (v8) | Amul Processed Cheese Slices | 100 g | — | Not yet classified |
| cfa51c3a-adf4-4882-8332-9d5ad992bf93 (v8) | Amul Processed Cheese Slices | 200 g | — | Not yet classified |
| 0984d332-7c82-4c5d-94ee-670db8697aef (v5) | Milky Mist Cheese Slices | 440 g | — | Not yet classified |
| 2698227f-146e-40ad-a2e9-e43548f9ded7 (v4) | Milky Mist Cheese Slices | 100 g | — | Not yet classified |
| 59dd6795-626b-4f60-b929-24dc15128866 (v4) | Milky Mist Cheese Slices | 200 g | — | Not yet classified |
| e0dc24c9-2cd8-4da5-b17c-e1f26248a7aa (v9) | Amul Cheese Spread | 200 g | — | Not yet classified |
| 1e2e28a7-682f-4bb9-b3b5-220f837a4d60 (v4) | Milky Mist Cream Cheese | 1 kg | — | Not yet classified |
| 4458048c-56e5-4882-b9cf-f2b50a19ab81 (v4) | Milky Mist Cream Cheese | 200 g | — | Not yet classified |
| 6f105ddc-8e49-4e84-a72e-69e2dd65375d (v7) | Amul Diced Cheese | 1 pack | — | Not yet classified |

### Dairy, Bread & Eggs / Cream and Condensed Milk

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| a04cfd78-15e6-4683-b77b-d53b3ea51a5e (v9) | Amul Fresh Cream | 250 mL × 3 | — | Not yet classified |
| bfb913ab-52c2-4a0c-a7a3-57a071cf74b1 (v5) | Amul Fresh Cream | 250 ml | — | Not yet classified |

### Dairy, Bread & Eggs / Curd and Yogurts

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| ec2c3960-700e-4612-9200-514dd7b01d6e (v3) | Aavin Curd Pouch | 500 g | — | Not yet classified |
| 610bf590-6990-44d2-bf72-d67e8fcb2117 (v3) | Arokya Fresh Curd | 500 g | — | Not yet classified |
| 8db521f5-1320-4bec-93db-b734ba7c416c (v3) | Hatsun Curd | 400 g | — | Not yet classified |
| e31ab6b1-d7a1-483c-9e20-ffc4539b82b2 (v3) | Aavin Thick Curd | 1 kg | — | Not yet classified |
| 4525fd88-50aa-450d-8834-9116e2bd8c21 (v3) | Arokya Fresh Curd Family Pack | 1 kg | — | Not yet classified |
| 6d228080-53ea-4da3-8507-8bac5749b193 (v3) | Hatsun Curd Family Pack | 1 kg | — | Not yet classified |

### Dairy, Bread & Eggs / Eggs

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 088f401c-1b7d-4b89-9ca1-63c632526df8 (v8) | Country Eggs selection | ₹12 each / 5 pcs | — | Not yet classified |
| a1884336-5ba4-488a-acfb-8a03775cd032 (v6) | White Eggs selection | ₹6 each / 5 pcs | — | Not yet classified |

### Dairy, Bread & Eggs / Indian Breads

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 13a58cd1-deb2-408e-94a7-92ef077a1302 (v8) | Milk Bread | 1 pack | — | Not yet classified |

### Dairy, Bread & Eggs / Milk

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 21de9800-be42-4da4-ba6f-13bf17980145 (v5) | Nestle Everyday Dairy Whitener | 200 g | Dairy Whitener | Supported; awaiting review |
| 2642d986-1130-4d4a-88bf-d0da178469d7 (v9) | Nestle Everyday Dairy Whitener | 15 g | Dairy Whitener | Supported; awaiting review |
| 6c425649-c011-4f9e-80dc-3b228a95b5ff (v5) | Nestle Everyday Dairy Whitener | 1 kg | Dairy Whitener | Supported; awaiting review |
| d5e0f1fc-f851-4469-b307-b858d4fed175 (v5) | Nestle Everyday Dairy Whitener | 400 g | Dairy Whitener | Supported; awaiting review |
| ad8ffcb7-6615-4ad0-a36d-c79bf944a1ab (v7) | Aavin Delite Milk | 500 ml | — | Hold |
| 278b1418-3ff6-4398-ba51-132b559fc035 (v5) | Aavin Full Cream Milk | 500 ml | — | Hold |
| 5908c4c1-9dce-4104-9342-13a9ab7926aa (v5) | Arokya Full Cream Milk | 1 L | Full Cream | Supported; awaiting review |
| b5bb8877-b01e-40fe-a306-7f61a2e6d131 (v5) | Aavin Nice Toned Milk | 500 ml | — | Hold |
| 5d9344b3-4d48-4cc2-a041-289fba4155bb (v6) | Amul Taaza Toned Milk | 1 L | Toned | Supported; awaiting review |
| a51d8c7d-bd8c-4f1e-8728-27b2b3df7397 (v7) | Amul Taaza Toned Milk | 200 ml | Toned | Supported; awaiting review |
| 3ca69e40-a71f-4c10-977b-738aa67b9b3f (v5) | Arokya Toned Milk | 500 ml | Toned | Supported; awaiting review |

### Dairy, Bread & Eggs / Paneer and Tofu

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 8e20ab1f-eb9b-430b-9520-54a1b9fdeeea (v4) | Amul Fresh Malai Paneer | 200 g | — | Not yet classified |
| e17e9e7c-cba6-49cc-8e95-a7da9ba23786 (v4) | Amul Fresh Malai Paneer | 500 g | — | Not yet classified |
| 018985df-6146-4b3b-a443-20553546f73d (v7) | Milky Mist Paneer | 200 g | — | Not yet classified |
| 320168a2-accf-4c0e-bccb-6309f1cbd04c (v5) | Milky Mist Paneer | 500 g | — | Not yet classified |

### Noodles Pasta Vermicelli / Hakka Noodles

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 8c7fed1a-07fc-445d-b708-24d6062f8d82 (v8) | Ching's Secret Ching’s Veg Hakka Noodles \| Not Fried \| Air Dried \| Cooks in 5–7 Minutes \| 560 g 140 g | 140 g | — | Not yet classified |
| 0f00303c-29af-4d9d-a799-3fd7316acb75 (v8) | Ching's Secret Ching’s Veg Hakka Noodles \| Not Fried \| Air Dried \| Cooks in 5–7 Minutes \| 560 g 560 g | 560 g | — | Not yet classified |
| 41ca4536-c609-433f-9bdc-310c4d3aad0c (v7) | Ching's Secret Chowmein Hakka Noodles Masala \| No need to add salt, spices, or condiments \| Authentic Desi Chinese \| Easy to Cook \| 100% Veg \| 7g 7 g | 7 g | — | Hold |

### Noodles Pasta Vermicelli / Instant Noodles

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| f12f7dc4-2691-4aa7-b528-47d7f8b7cbf7 (v8) | Ching's Secret Ching’s Korean Kimchi Instant Noodles \| 80g \| Veg \| It’s Hot, It’s Spicy, It’s Ching’s 80 g | 80 g | — | Not yet classified |
| b682f5e2-ff24-4f1c-9ca6-2a287ba2ccef (v7) | Ching's Secret Ching’s Korean Spicy Veg Instant Noodles \| 80g \| Veg \| It’s Hot, It’s Spicy, It’s Ching’s 80 g | 80 g | — | Not yet classified |
| b6791ff3-d5ef-40ca-a5c7-ff244fdce4f0 (v8) | Ching's Secret Chings Korean Ramen Kimchi & Spicy Noodles \| 112g makes 500g Soupy Ramen meal 112 g | 112 g | — | Not yet classified |
| de18c193-095c-4418-90b5-ca93a1dc7ec5 (v8) | Ching's Secret Manchurian Instant Noodles Quick and Tasty  \| 100% Veg \| Desi-Chinese Ka Mazaa Minton Mein \| 240g 256 g | 256 g | — | Not yet classified |
| 869a42bd-04a6-4584-a0e9-4e32d52a5829 (v8) | Ching's Secret Manchurian Instant Noodles Quick and Tasty  \| 100% Veg \| Desi-Chinese Ka Mazaa Minton Mein \| 240g 60 g | 60 g | — | Not yet classified |
| c026dd3a-5740-4f0b-8586-179d9de9bf64 (v8) | Ching's Secret Ching's Secret Shirataki Noodles \| 270g 270 g | 270 g | — | Not yet classified |

### Noodles Pasta Vermicelli / Cooking Pasta

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 3daf3cef-26ef-4f83-be1c-97105342f2e2 (v7) | MTR Macaroni Pasta 400 g | 400 g | — | Not yet classified |
| e541ebce-118e-412b-b8d0-d5496efb043b (v7) | MTR Macaroni Pasta 850 g | 850 g | — | Not yet classified |

### Atta, Flour & Dal / Ready to Cook Flour Mix

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 32107cfb-2fd0-4e3e-9624-98f3d829c1a3 (v7) | Aachi Adhirasam Maavu 500 g | 500 g | — | Not yet classified |
| 058f032f-81f0-498a-a1a4-2054d517365d (v7) | Aachi Bajji Bonda Powder 200 g | 200 g | — | Not yet classified |
| e2f5272e-d3cf-405e-96bd-14bade3d6e66 (v7) | Aachi Bajji Bonda Powder 500 g | 500 g | — | Not yet classified |
| 8a1046f4-1682-4e89-9a5e-dd0f11ffb1e3 (v7) | MTR Bhajji Bonda Mix 200 g | 200 g | — | Not yet classified |
| 15358afd-acb3-43f4-836a-26bdd761be3b (v7) | Aachi Murukku Maavu 500 g | 500 g | — | Not yet classified |

### Atta, Flour & Dal / Rice

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| ab343bef-4409-4cbf-9c9c-c485d4641c2c (v7) | Aachi Chettinadu Basmati Biryani Kit 365 g | 365 g | — | Not yet classified |
| 929998e1-b346-448a-bd2c-00d280155fa0 (v7) | Aachi Dindigul Seeraga Samba Rice Biryani Kit 365 g | 365 g | — | Not yet classified |
| dac0ae5a-e949-4394-adb9-4f801dedc265 (v7) | Aachi Hyderabadi Basmati Biryani Kit 375 g | 375 g | — | Not yet classified |

### Noodles Pasta Vermicelli / Ready to eat

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| f14c6112-f5f1-406e-92af-124e20369a27 (v7) | Aachi Instant Vegetable Biryani 250 g | 250 g | — | Not yet classified |
| 8df329e6-2092-4b49-860a-5ba147b56876 (v7) | Aachi Instant Chana Masala 300 g | 300 g | — | Not yet classified |
| 2081ee2f-0c8f-4a14-aee5-749d44d0c101 (v7) | Aachi Instant Dal Makhani 300 g | 300 g | — | Not yet classified |
| da35287d-b962-4d99-a93b-3554610fca15 (v8) | MTR Ready to Eat Chana Masala 300 g | 300 g | — | Not yet classified |
| 7051cca1-bbe3-4bbf-865e-57f07a98316c (v7) | MTR Ready to Eat Dal Fry 300 g | 300 g | — | Not yet classified |
| fd8f3e1c-561c-4b7c-b605-b5a711e48616 (v7) | MTR Ready to Eat Dal Makhani 300 g | 300 g | — | Not yet classified |
| 52c2b6af-2dcb-4d6c-b487-bf9a23a9cd70 (v7) | MTR Ready to Eat Mixed Vegetable Curry 300 g | 300 g | — | Not yet classified |
| 76f61edb-ffe3-4396-8f67-aa18d8c20b7f (v7) | MTR Ready to Eat Mutter Paneer 300 g | 300 g | — | Not yet classified |
| cd3acb40-66bb-45bf-9129-c91abefeabf8 (v7) | MTR Ready to Eat Palak Paneer 300 g | 300 g | — | Not yet classified |
| 48be29a1-e5f9-4f8f-b36f-e0645cb3f011 (v7) | MTR Ready to Eat Paneer Butter Masala (Pack of 2) 300 g ×2 | 300 g | — | Not yet classified |
| 4e64d6a7-307f-4eda-90d5-2b930cfb4e53 (v7) | MTR Ready to Eat Paneer Butter Masala 300 g | 300 g | — | Not yet classified |
| ee12e37d-3b43-4a41-90a5-b0b51e63a663 (v7) | MTR Ready to Eat Paneer Makhani 300 g | 300 g | — | Not yet classified |
| 6be1feee-7502-442b-a65f-7b21c0364ee6 (v8) | MTR Ready to Eat Pav Bhaji 300 g | 300 g | — | Not yet classified |
| 126be22d-5767-45f5-b604-89a72cdcb6bf (v7) | MTR Ready to Eat Rajma Masala (Pack of 2) 300 g ×2 | 300 g | — | Not yet classified |
| 63a869b8-9fd4-4d14-b9c3-c47e3283bb78 (v7) | MTR Ready to Eat Rajma Masala 300 g | 300 g | — | Not yet classified |
| 346bd286-02e6-4f7d-8597-ae42118a46bf (v7) | MTR Ready to Eat SHAHI PANEER 300G 300 g | 300 g | — | Not yet classified |
| 9fb7826e-a2b5-4283-b093-8d74b3b5d1c9 (v7) | Aachi Instant Bisibele Bhath 300 g | 300 g | — | Not yet classified |
| 551430c9-0a83-4d41-a9eb-876e66af939b (v7) | Aachi Instant Lemon Rice 250 g | 250 g | — | Not yet classified |
| 30f23b9c-1a02-4866-ae3e-f9d82556bbc8 (v7) | Aachi Instant Pongal 300 g | 300 g | — | Not yet classified |
| f78f2350-07da-4c69-8e70-70b3a770dbbf (v7) | Aachi Instant Sambar Rice 300 g | 300 g | — | Not yet classified |
| b4d89312-a945-4eff-b003-6a794ea6b9fc (v7) | Aachi Instant Veg Pulao 250 g | 250 g | — | Not yet classified |
| 229b0afb-eb3c-4d48-83e0-e9bd70a48bb8 (v7) | MTR Bisibele Bhath Masala (3x Value Pack) 100     g 100 g ×3 | 100 g | — | Not yet classified |
| d3d65828-965f-4001-8f0f-bb9e0cb3ddfc (v7) | MTR Ready to Eat Bisibele Bhath (Pack of 2) 300 g ×2 | 300 g | — | Not yet classified |
| 0d96a255-6efd-462d-a09f-13684c7d9962 (v7) | MTR Ready to Eat Bisibele Bhath 300 g | 300 g | — | Not yet classified |
| 0cd59a57-0592-48ad-a159-b5c9ed52dfb7 (v7) | MTR Ready to Eat Jeera Rice (Pack of 2) 250 g ×2 | 250 g | — | Not yet classified |
| 7c7dc8ae-882d-47e3-8c39-3e422409c22a (v7) | MTR Ready to Eat Jeera Rice 250 g | 250 g | — | Not yet classified |
| 4d9f3a16-089b-4529-bb86-e82062105bd8 (v7) | MTR Ready to Eat Lemon Rice (Pack of 2) 250 g ×2 | 250 g | — | Not yet classified |
| 34035c47-c4fd-4546-a708-018066a8b586 (v7) | MTR Ready to Eat Lemon Rice 250 g | 250 g | — | Not yet classified |
| 3def9d0d-f1f5-4edc-adfd-4e42789ac24d (v7) | MTR Ready to Eat Masala Rice (Pack of 2) 250 g ×2 | 250 g | — | Not yet classified |
| 707dc783-37ad-49ec-a7f6-dc56214af7d3 (v7) | MTR Ready to Eat Masala Rice 250 g | 250 g | — | Not yet classified |
| b8038164-ffbe-4e9b-9179-af14cc35fe4f (v7) | MTR Ready to Eat Pongal 300 g | 300 g | — | Not yet classified |
| 6d918c8f-8663-47f5-acf3-e7f01a8e4b06 (v7) | MTR Ready to Eat Sambar Rice (Pack of 2) 300 g ×2 | 300 g | — | Not yet classified |
| c6fc0937-1e39-4fc5-8498-ce76149fb7c2 (v7) | MTR Ready to Eat Sambar Rice 300 g | 300 g | — | Not yet classified |
| 0f54a922-bfaf-4470-bede-16a7309b01f8 (v7) | MTR Ready to Eat Tomato Rice (Pack of 2) 250 g ×2 | 250 g | — | Not yet classified |
| e7dcaf58-ea91-4a90-b738-dafdedbc0ad1 (v7) | MTR Ready to Eat Tomato Rice 250 g | 250 g | — | Not yet classified |
| 8d240d44-3d18-42d8-adcc-d92cb5af3207 (v7) | MTR Ready to Eat Vegetable Pulao 250 g | 250 g | — | Not yet classified |

### Noodles Pasta Vermicelli / Soups

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 416ca67c-b494-43c6-a2bd-d90421b03bc4 (v8) | Ching's Secret Instant Tomato with croutons Soup 15 g | 15 g | — | Not yet classified |
| 7105113c-8d05-4381-9487-637a7db2f787 (v8) | Ching's Secret Mix Veg Soup 55 g | 55 g | — | Not yet classified |
| 47712955-31a1-4037-b66d-11f4dfe975c3 (v8) | Ching's Secret Sweet Corn Veg Soup 55 g | 55 g | — | Not yet classified |

### Noodles Pasta Vermicelli / Vermicelli

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| d5c17048-c582-482a-be21-2992a820c36b (v7) | Aachi Instant Idiyappam 200 g | 200 g | — | Not yet classified |
| ea34573e-127f-4e7b-972a-372cda1e4f18 (v7) | MTR Rice Sevai 165 g | 165 g | — | Not yet classified |
| 0500b35d-47aa-4d7b-8915-3de06670f567 (v7) | MTR Rice Sevai 400 g | 400 g | — | Not yet classified |
| e2bfb32e-43e3-4e75-903e-0d30765c2bb6 (v7) | Aachi Roasted Short Vermicelli 180 g ×2 | 180 g | — | Not yet classified |
| 4f80b9dd-658b-471b-b0e2-c42c7cab84ac (v7) | MTR Roasted Vermicelli 180 g | 180 g | — | Not yet classified |
| 5ff65c05-dc2e-4fa3-902c-7cca398763d4 (v7) | MTR Roasted Vermicelli 400 g | 400 g | — | Not yet classified |
| 1614b3e1-e912-48c0-a90c-20ce61999935 (v7) | MTR Roasted Vermicelli 850 g | 850 g | — | Not yet classified |
| 79d12382-2705-4bf1-ba49-13b919d8be3e (v7) | Aachi Lemon Vermicelli 200 g | 200 g | — | Not yet classified |
| 2cbcc1f3-65cc-4839-bf27-f99f669dfd78 (v7) | Aachi Ragi Vermicelli 180 g ×2 | 180 g | — | Not yet classified |
| 92d71459-de56-4df9-9262-ed6c420c8848 (v7) | Aachi Vermicelli 400 g ×2 | 400 g | — | Not yet classified |
| f8be76a9-0ace-469d-a6ea-8f8a90880f44 (v7) | MTR Seviyan Vermicelli 400 g | 400 g | — | Not yet classified |
| b2f14bf5-8015-47cd-ab37-e36d69200163 (v7) | MTR Seviyan Vermicelli 850 g | 850 g | — | Not yet classified |

### Masalas / Ready Masala

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 67ff5e78-cfc4-4d06-b3e8-3889d44e52c5 (v7) | Aachi Biryani Masala 100 g | 100 g | — | Not yet classified |
| a67c38e7-2eac-42dd-b0b9-a2937376ba38 (v7) | Aachi Biryani Masala 200 g | 200 g | — | Not yet classified |
| 8a7df50c-9819-40a2-acec-e9468ceee2c1 (v7) | Aachi Biryani Masala 50 g | 50 g | — | Not yet classified |
| 774fd9ab-27d9-4344-ae0b-6e799e4e6da4 (v7) | Aachi Chettinad Chicken Biryani Masala 50 g ×2 | 50 g | — | Not yet classified |
| f8063ece-ecc6-4824-9e59-c35da6debff4 (v7) | Aachi Chettinadu Biryani Masala Paste 167 g | 167 g | — | Not yet classified |
| a0ec455f-db22-4a14-b6b5-abf9b15771e5 (v7) | Aachi Dindigul Biryani Masala 50 g ×2 | 50 g | — | Not yet classified |
| 6beda5ff-ce3c-4509-9fd0-f3cc6bf3e0b1 (v7) | Aachi Dindigul Biryani Masala Paste 167 g | 167 g | — | Not yet classified |
| 2f22058d-4a47-44a3-b647-002df5cef3a4 (v7) | Aachi Hyderabadi Biryani Masala Paste 177 g | 177 g | — | Not yet classified |
| d942f451-8f59-4cbe-a23d-285396ce48fa (v7) | Aachi Chaat Masala 50 g | 50 g | — | Not yet classified |
| 080e2aa1-5ff8-489f-8023-4dbc4bb32e99 (v7) | Aachi Pani Puri Masala 50 g | 50 g | — | Not yet classified |
| 1c0efee1-849c-4be8-afc5-77d3c4b5ad13 (v7) | Aachi Chana Masala 50 g | 50 g | — | Not yet classified |
| d204748b-34af-4e75-8e23-4997fe4b4631 (v7) | MTR Chana Masala Powder 100 g | 100 g | — | Not yet classified |
| 70a9c5d1-fae7-471f-9300-31d4614dfb49 (v7) | Aachi Chicken 65 Masala 100 g | 100 g | — | Not yet classified |
| d92567f8-ded9-471b-91fb-e0be6f2969a7 (v7) | Aachi Chicken 65 Masala 200 g | 200 g | — | Not yet classified |
| a6222ac7-d2c2-4392-8802-f72c206e426c (v7) | Aachi Chicken 65 Masala 500 g | 500 g | — | Not yet classified |
| 76112454-a938-4037-81c0-22103486df1d (v7) | Aachi Chicken Kabab Powder 100 g | 100 g | — | Not yet classified |
| 9ebf82f9-fede-4d45-80aa-dca19c8857e6 (v7) | Aachi Chicken Masala 100 g | 100 g | — | Not yet classified |
| 1bd3a930-a1d7-4a2e-b53b-5ab2ee0083f9 (v7) | Aachi Chicken Masala 200 g | 200 g | — | Not yet classified |
| 4e6877d9-43cd-46e1-8463-8f57c895470a (v7) | Aachi Chicken Masala 500 g | 500 g | — | Not yet classified |
| 2a1349c8-aed8-456b-ab3e-5f8ae92398db (v7) | Aachi Chilli Chicken Masala 100 g | 100 g | — | Not yet classified |
| e2c35496-61a4-42ec-ac6b-42f3b34ae12e (v7) | Aachi Crispy Fry Chicken Mix 80 g ×3 | 80 g | — | Not yet classified |
| 98257d58-782a-40cb-9c8a-a8768ff786c6 (v7) | Aachi Nattu Kozhi Masala 50 g ×2 | 50 g | — | Not yet classified |
| a80253e0-ad31-4f14-a846-8e6900e56146 (v7) | Aachi Pepper Chicken Masala 50 g ×2 | 50 g | — | Not yet classified |
| 78eefc5f-a90e-402a-b98d-086e271e36ba (v8) | Ching's Secret Chicken 65 Masala 20 g | 20 g | — | Not yet classified |
| 2e5ec02c-ecf9-4df1-832c-a09ea970b727 (v7) | Aachi Curry Masala 100 g | 100 g | — | Not yet classified |
| 52e72fff-d2d4-4fb7-99d3-1b18972531e8 (v7) | Aachi Egg Curry Masala 50 g ×2 | 50 g | — | Not yet classified |
| bef9988e-d15b-4337-ae2c-16c6c342067f (v7) | Aachi Gobi 65 Masala 50 g ×3 | 50 g | — | Not yet classified |
| a80bdc38-d12d-4c6d-b210-e0953bfe817b (v7) | Aachi Paneer Butter Masala 50 g | 50 g | — | Not yet classified |
| cfcd5edb-d525-491f-b9b7-61f0d9463de2 (v7) | Aachi Vatha Kulambu Masala 50 g ×2 | 50 g | — | Not yet classified |
| 606d80d8-e26c-41eb-b2a8-215ab9e69ceb (v7) | Aachi Fish Curry Masala 100 g | 100 g | — | Not yet classified |
| 02a61b84-1cf3-4a22-924d-1aa36108a062 (v7) | Aachi Fish Curry Masala 50 g | 50 g | — | Not yet classified |
| 15c76a50-eac3-4b1f-9180-87d7b6592998 (v7) | Aachi Fish Fry Masala 100 g | 100 g | — | Not yet classified |
| 22c68ed6-f60a-4c57-b35d-bd6a9fa22dc9 (v7) | Aachi Fish Fry Masala 50 g | 50 g | — | Not yet classified |
| d10211f6-bb9a-47db-bf3d-d01bc679ea11 (v7) | Aachi Garam Masala 100 g | 100 g | — | Not yet classified |
| 5dd90808-cd24-4082-8dce-e4ac3c3f47bc (v7) | Aachi Garam Masala 200 g | 200 g | — | Not yet classified |
| ad39f686-a4ba-4941-b02d-ebd02f19f241 (v7) | Aachi Garam Masala 500 g | 500 g | — | Not yet classified |
| 40b4f0f7-f422-4b8f-b0d9-ac439f953131 (v7) | MTR Special Garam Masala 100 g | 100 g | — | Not yet classified |
| 8f2283ca-e51d-4613-a916-e50b6393ab7e (v7) | MTR Special Garam Masala 50 g | 50 g | — | Not yet classified |
| 2705aa2d-ae36-45e7-ba78-04ca3c41df2d (v7) | Aachi Kitchen king Masala 50 g | 50 g | — | Not yet classified |
| 0fe5f7fb-ff81-4027-a86a-b0f9c81ef042 (v7) | Aachi Kulambu Chilli Masala 1 kg | 1 kg | — | Not yet classified |
| 1009a7a6-41ee-4cc2-8377-46984f93e7fa (v7) | Aachi Kulambu Chilli Masala 100 g | 100 g | — | Not yet classified |
| 26ce931d-343f-4712-8a16-1748f7fbdc29 (v7) | Aachi Kulambu Chilli Masala 200 g | 200 g | — | Not yet classified |
| a4fe684d-230c-4759-aeb0-2f4551c1e8fc (v7) | Aachi Kulambu Chilli Masala 500 g | 500 g | — | Not yet classified |
| 5ec6797d-07f3-4505-aa53-36aee4b6e0f3 (v7) | Aachi Meat Masala 50 g | 50 g | — | Not yet classified |
| cd62f7de-a5b9-4618-b92c-78eae342a634 (v7) | Aachi Mutton Masala 100 g | 100 g | — | Not yet classified |
| c4129122-d2f0-4e72-a196-1fada60b7553 (v7) | Aachi Mutton Masala 200 g | 200 g | — | Not yet classified |
| c7c6b67b-d1ff-4437-881b-a5e1500bf155 (v7) | Aachi Pav Bhaji Masala 50 g | 50 g | — | Not yet classified |
| ec0bd5fb-cb8f-49bc-818b-6a045898779e (v7) | Aachi Rasam Powder 100 g | 100 g | — | Not yet classified |
| b5e65b3c-78e4-44f2-a69e-419c271e5e52 (v7) | MTR Rasam Powder (3x Value Pack) 100g 100 g ×3 | 100 g | — | Not yet classified |
| aba79a3d-a412-4bd6-bc5f-47a620316553 (v7) | MTR Rasam Powder 100 g | 100 g | — | Not yet classified |
| f68e3ac4-671c-440b-bf90-ef4d9ec96c25 (v7) | MTR Rasam Powder 200 g | 200 g | — | Not yet classified |
| 70d8abb3-1ae2-429d-8c81-47cf8cbf3c22 (v7) | Aachi Lemon Rice Powder 50 g ×2 | 50 g | — | Not yet classified |
| 0f0011d8-7aa4-497e-b5c8-4340e5ba030c (v7) | Aachi Original Fried Rice Powder (pack of 6) 15 g ×6 | 15 g | — | Not yet classified |
| 3e7156f9-fc4c-4fa4-a0c8-9342403908e1 (v7) | Aachi Puliyogare Powder 100 g | 100 g | — | Not yet classified |
| 47df2f3a-cc1d-439c-af24-08bc98aaf7ac (v7) | Aachi Schezwan Fried Rice Powder (pack of 6) 15 g ×6 | 15 g | — | Not yet classified |
| e8d9ed20-3856-4cb6-b9a2-3fcf4769b92a (v7) | Aachi Tamarind Rice Powder 100 g | 100 g | — | Not yet classified |
| 2f8c8578-f1eb-4998-bae1-6f669e06068f (v7) | Aachi Tomato Rice Powder 50 g ×3 | 50 g | — | Not yet classified |
| bafcf45e-1c43-4249-a026-a27d050d955d (v7) | MTR Bisibele Bhath Masala 100 g | 100 g | — | Not yet classified |
| 3dc5a9fd-1d94-423a-898d-b4f28e02964d (v7) | MTR Bisibele Bhath Masala 200 g | 200 g | — | Not yet classified |
| 28433846-f8d8-4b36-8a74-284ead422ece (v7) | MTR Pulao Masala Powder 100 g | 100 g | — | Not yet classified |
| bd367942-39c2-4188-b7ab-146ee47fafe7 (v7) | MTR Puliogare Paste (3x Value Pack) 200 g ×3 | 200 g | — | Not yet classified |
| 760043be-1664-4ed1-ae72-fb40bc379bb6 (v7) | MTR Puliogare Paste 200 g | 200 g | — | Not yet classified |
| bc984dfd-9508-461b-9e2e-4a6c658029b9 (v7) | MTR Puliogare Powder 100 g | 100 g | — | Not yet classified |
| 2df338b4-5e6f-4235-8921-3c85bdabe3af (v7) | MTR Puliogare Powder 200 g | 200 g | — | Not yet classified |
| d40d6ec7-0d52-4b06-bc6e-992bc9e68868 (v7) | MTR Vangi Bhath Powder 100 g | 100 g | — | Not yet classified |
| 4c2e5cde-d15f-49f2-a2ec-85805d014482 (v7) | MTR Vangi Bhath Powder 200 g | 200 g | — | Not yet classified |
| 83cee75d-3653-4e8b-8759-4de10b58a2f9 (v7) | Aachi Sabji Masala 50 g | 50 g | — | Not yet classified |
| 249bb5f6-566c-455f-a302-ad8a1067d4fb (v7) | Aachi Hotel Sambar Powder 100 g | 100 g | — | Not yet classified |
| d9261ceb-f0b8-4cfb-84da-468e7b97916a (v7) | Aachi Idicha Sambar Powder 100 g | 100 g | — | Not yet classified |
| 573c2abf-f407-4954-868d-01af9207a098 (v7) | Aachi Idicha Sambar Powder 50 g | 50 g | — | Not yet classified |
| 207efa21-1a7a-4271-a7a2-774eb875fbbe (v7) | Aachi Madras Sambar Powder 100 g | 100 g | — | Not yet classified |
| 96ff7d5d-9c1a-44d0-9305-353da7889051 (v7) | Aachi Sambar Powder 200 g | 200 g | — | Not yet classified |
| 1c30eeb8-e004-471f-bffb-10019d41e66c (v7) | Aachi Sambar Powder 500 g | 500 g | — | Not yet classified |
| c40cc834-f039-448f-8e83-f3a45b057060 (v7) | Aachi Spicy Sambar Powder 100 g | 100 g | — | Not yet classified |
| 1f30163c-f615-4b0d-933b-5850353065b7 (v7) | MTR Sambar  powder 100 g | 100 g | — | Not yet classified |
| c32c6dc2-5afe-4848-8dce-ac0da5914701 (v7) | MTR Sambar  powder 180 g | 180 g | — | Not yet classified |
| 95c3f20a-e29e-4bd7-bc15-298d8e542636 (v7) | MTR Sambar  powder 500 g | 500 g | — | Not yet classified |
| cc7f0276-5ef6-4c0d-b22d-2e8b3c9586d0 (v7) | MTR Sambar Powder (3x Value Pack) 100 g 100 g ×3 | 100 g | — | Not yet classified |
| b085f5fa-3707-4668-9d5c-df1590cc5b29 (v7) | MTR Sambar Powder 100 g | 100 g | — | Not yet classified |
| 3eaf7246-4e94-4421-b629-7f3f3b6973ee (v7) | MTR Sambar Powder 500 g | 500 g | — | Not yet classified |
| dc65f374-1f0a-4645-b567-93e0c70a06f7 (v7) | MTR Spicy Sambar Powder 100 g | 100 g | — | Not yet classified |
| 8ff32acc-a96b-472f-b328-1360b6e0930d (v7) | MTR Spicy Sambar Powder 200 g | 200 g | — | Not yet classified |

### Masalas / Paste and Puree

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| be8f0db4-84c5-4864-ace4-7e9fbf0f3fef (v7) | Aachi Ginger Garlic Paste 100 g ×2 | 100 g | — | Not yet classified |

### Masalas / Papad & Fryums

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| e6f64b65-a03b-431f-88cc-7e9f3d6b694e (v7) | Aachi Appalam 100 g | 100 g | — | Not yet classified |
| 561ba52e-f3ed-4ecf-9d0c-27058c2f1403 (v7) | Aachi Appalam 200 g | 200 g | — | Not yet classified |

### Masalas / Pickles & Chutney

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| c143ffde-6a60-4712-8fd0-140d2c64123f (v7) | Aachi Green Chilli Pickle 200 g | 200 g | — | Not yet classified |
| b39f4e4e-01eb-4498-bbe4-55792bd57dab (v7) | Aachi Red Chilli Pickle 300 g | 300 g | — | Not yet classified |
| 96561e1b-beb4-4453-99da-ec45ce0cc033 (v7) | Aachi Idly Chilli Powder 100 g | 100 g | — | Not yet classified |
| 0ebe0714-0b5d-40db-883d-5ca0a1c0f3ef (v7) | Aachi Idly Chilli Powder 200 g | 200 g | — | Not yet classified |
| 81424a1e-1f76-4243-85c1-56c90cec970e (v7) | Aachi Idly Chilli Powder 500 g | 500 g | — | Not yet classified |
| 51289b19-a9c1-488d-b4a1-1b6888a6990d (v7) | MTR Idli Karam Podi 100 g | 100 g | — | Not yet classified |
| f4ece478-bf00-405f-be9e-f108bdd43818 (v7) | MTR Kandi Podi 100 g | 100 g | — | Not yet classified |
| d420c432-dba0-47f5-a39e-cc4641c1f6e6 (v7) | MTR Karivepaku Podi 100 g | 100 g | — | Not yet classified |
| 9ad2b4a5-57a4-4698-ad81-2f3becc4af3e (v7) | Aachi Citron Pickle 200 g | 200 g | — | Not yet classified |
| d44d0c05-132b-42c0-aebb-e5c2a6fbb4f4 (v7) | Aachi Garlic Pickle 1 kg | 1 kg | — | Not yet classified |
| c7133918-8a8f-43d4-8b1f-7e30219041cc (v7) | Aachi Garlic Pickle 200 g | 200 g | — | Not yet classified |
| b6eb35d9-427b-4701-bc82-bca16020f129 (v7) | Aachi Garlic Pickle 500 g | 500 g | — | Not yet classified |
| 2a0e6c76-1997-40db-b024-67b0bc21fb23 (v7) | Aachi Ginger Pickle 200 g | 200 g | — | Not yet classified |
| 51ecaff6-de65-4f83-9546-1ec05f2b00b0 (v7) | Aachi Gongura Pickle 200 g | 200 g | — | Not yet classified |
| 63d860e1-91c9-4e76-be09-db977856fca2 (v7) | Aachi Lime Pickle 200 g | 200 g | — | Not yet classified |
| 5c6fcba5-5f87-4f1d-a37a-e87fea3ec143 (v7) | Aachi Lime Pickle 300 g | 300 g | — | Not yet classified |
| cdabf94e-20ad-4479-9e24-9b1f5073c56e (v7) | MTR Lime Pickle 300 g | 300 g | — | Not yet classified |
| 49a305ba-e366-46ad-8da6-f178acdef98c (v7) | MTR Lime Pickle 500 g | 500 g | — | Not yet classified |
| 41a1def1-028c-4c36-aff1-dc6ce9707b0a (v7) | Aachi Cut Mango Pickle 1 kg | 1 kg | — | Not yet classified |
| adf81369-49cb-4b4c-b8d5-9bb627d39e00 (v7) | Aachi Cut Mango Pickle 200 g | 200 g | — | Not yet classified |
| cfa68159-2e5a-4ef6-a8f9-269485152681 (v7) | Aachi Mango Avakkai Pickle 200 g | 200 g | — | Not yet classified |
| 556d6964-920c-437b-a1b8-91a221f46174 (v7) | Aachi Mango Avakkai Pickle 300 g | 300 g | — | Not yet classified |
| d4181ab1-e48f-4741-8127-3480aa7972d4 (v7) | Aachi Mango Ginger Pickle 200 g | 200 g | — | Not yet classified |
| e1888643-58c6-4b00-a07d-af0a70dc38a9 (v7) | Aachi Mango Thokku Pickle 1 kg | 1 kg | — | Not yet classified |
| 337fe325-5027-40a4-b061-5678fa5dd687 (v7) | Aachi Mango Thokku Pickle 200 g | 200 g | — | Not yet classified |
| 2672b69c-e861-47db-b7e8-78ab01879966 (v7) | MTR Mango Appemidi Pickle 500g 500 g | 500 g | — | Not yet classified |
| 7172028a-93a1-42e5-aa94-fe46fafb775f (v7) | MTR Mango Avakai Pickle 300 g | 300 g | — | Not yet classified |
| f5c99a13-7607-4c17-a8c7-e93e62be47a3 (v7) | MTR Mango Avakai Pickle 500 g | 500 g | — | Not yet classified |
| 42e73079-aeef-4fea-b542-65539a9159d2 (v7) | MTR Mango Pickle (Full) 500 g | 500 g | — | Not yet classified |
| 216ad830-47b8-44dc-a237-568fc450e086 (v7) | MTR Mango Sliced Pickle 300 g | 300 g | — | Not yet classified |
| e64f90b9-280d-4a0d-96b6-5600661ee717 (v7) | MTR Mango Sliced Pickle 500 g | 500 g | — | Not yet classified |
| 2359b5cf-74c8-47ae-8c2d-fb01f321efc8 (v7) | MTR Mango Thokku Pickle 300 g | 300 g | — | Not yet classified |
| 1750795f-a03b-4f9a-903e-9fbea3bf6068 (v7) | MTR Mango Thokku Pickle 500 g | 500 g | — | Not yet classified |
| 4e7d6af1-b260-4764-8c43-1588de25a267 (v7) | Aachi Mixed Veg Pickle 200 g | 200 g | — | Not yet classified |
| a8d72489-7cc0-4ee2-b545-ee1c664cc1bb (v7) | MTR Mixed Vegetable Pickle 300 g | 300 g | — | Not yet classified |
| 73d660ee-3856-4017-878c-21a8bc6746c7 (v7) | MTR Mixed Vegetable Pickle 500 g | 500 g | — | Not yet classified |
| a6fdd91b-b2e8-4521-9f8c-449b10d3d15c (v7) | Aachi Curry Leaf Rice Paste 200 g | 200 g | — | Not yet classified |
| 3222b56a-a0a0-48b4-b7b9-420320f9f15c (v7) | Aachi Lemon Rice Paste 200 g | 200 g | — | Not yet classified |
| 5916ce3f-9674-484f-8463-c2ccf0ef8e75 (v7) | Aachi Puliyodharai Rice Paste 200 g | 200 g | — | Not yet classified |
| 8d896785-a723-4dfa-9bed-bd8b7e63aafd (v7) | Aachi Tomato Garlic Rice Paste 200 g | 200 g | — | Not yet classified |
| b78083fb-56ed-40b0-9869-2b4eda3fa9c1 (v7) | Aachi Tomato Rice Paste 200 g | 200 g | — | Not yet classified |
| 4720ff06-2beb-415a-a9f9-380ab0315f7d (v7) | Aachi Vatha Kulambu Rice Paste 200 g | 200 g | — | Not yet classified |
| 875eb8dd-d88e-4b38-a029-752202b4ce61 (v7) | Aachi Coriander Thokku 200 g | 200 g | — | Not yet classified |
| 47cd4e84-881c-480b-aeea-5d45c3ebeb7d (v7) | Aachi Pudhina Thokku 200 g | 200 g | — | Not yet classified |
| 82d35ed3-3db2-4ccf-a4a4-1f2a8943509a (v7) | Aachi Tomato Garlic Pickle 100 g | 100 g | — | Not yet classified |
| 30a0ac42-04b6-4f0e-a54b-34ec3c045051 (v7) | Aachi Tomato Pickle 200 g | 200 g | — | Not yet classified |
| 72874909-64e5-4785-98ca-0caddcedb31f (v7) | MTR Tomato Pickle 300 g | 300 g | — | Not yet classified |
| dbb5187d-0fc2-459d-acc6-4e3675f4fbfb (v7) | MTR Tomato Pickle 500 g | 500 g | — | Not yet classified |

### Masalas / Powdered Spices

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 989d8565-3450-4382-8066-90425877e2c9 (v9) | Aachi Asafoetida Powder 50 g | 50 g | — | Not yet classified |
| 46f037e8-676c-4a36-84bf-c8da9f5eb185 (v9) | MTR Hing Powder 100 g | 100 g | — | Not yet classified |
| cc0b3c62-c827-4cd5-8a20-6a909fa80138 (v9) | MTR Hing Powder 25 g | 25 g | — | Not yet classified |
| 659a491e-2c94-4175-a48d-75d72eb025fa (v9) | MTR Hing Powder 50 g | 50 g | — | Not yet classified |
| 13548c44-0f3e-496b-882d-597f90815212 (v9) | Aachi Byadagi Chilli Powder 500 g | 500 g | — | Not yet classified |
| 31ce8d14-4a13-4a97-b932-dae11d82b17b (v9) | Aachi Chilli Powder 100 g | 100 g | — | Not yet classified |
| 2055fe2b-28b0-4bd3-9622-f1adf28ff88b (v9) | Aachi Chilli Powder 200 g | 200 g | — | Not yet classified |
| 0444a46b-17d9-4be5-9dca-adfbdbca3e13 (v9) | Aachi Chilli Powder 500 g | 500 g | — | Not yet classified |
| f3d73ab9-27a6-4f11-b19f-3b11163dc6ec (v9) | MTR Chilli Powder 100 g | 100 g | — | Not yet classified |
| ec42ea04-5d35-46c6-9504-a53de04e7f64 (v9) | MTR Chilli Powder 250 g | 250 g | — | Not yet classified |
| 8ca61390-bbf2-49af-9efc-d865f71da2f5 (v9) | MTR Chilli Powder 500 g | 500 g | — | Not yet classified |
| 5498b26c-62bd-48ec-8dba-0f6822b430c3 (v9) | MTR Kashmiri Chilli Powder 100 g | 100 g | — | Not yet classified |
| 1ce178ec-1aa4-429f-a115-9cb273e977a1 (v9) | MTR Kashmiri Chilli Powder 250 g | 250 g | — | Not yet classified |
| bffe8bb9-9c7d-417d-adc1-63c4ef5cb0d3 (v9) | Aachi Coriander Powder 100 g | 100 g | — | Not yet classified |
| ec1161e4-8358-491f-a7e3-2cd3b8dd53d6 (v9) | Aachi Coriander Powder 50 g ×2 | 50 g | — | Not yet classified |
| 6ef8dfe5-8ef8-46f7-a0e8-f0546148d761 (v9) | Aachi Coriander Powder 500 g | 500 g | — | Not yet classified |
| 65e68ef3-598f-4980-96ec-45da8a29a61c (v9) | MTR Coriander Powder 100 g | 100 g | — | Not yet classified |
| 824c86cd-0976-4889-8796-cfd60c740e67 (v9) | MTR Coriander Powder 250 g | 250 g | — | Not yet classified |
| b60fc3e3-1e47-4aae-818d-30c238480a69 (v9) | MTR Coriander Powder 500 g | 500 g | — | Not yet classified |
| 685e971e-a0a4-40d1-b7f9-6dc84b8c4827 (v9) | Aachi Cumin Powder 100 g | 100 g | — | Not yet classified |
| d1f80018-b4c8-42a6-bfb3-1bfdd179214a (v9) | MTR Cumin Powder 100 g | 100 g | — | Not yet classified |
| 6862fe43-57b5-41b4-b537-0b7b7d79affa (v9) | Aachi Fennel Powder 100 g | 100 g | — | Not yet classified |
| a2fa4803-d55e-4b60-adff-bb1a609d68e2 (v9) | Aachi Kashmiri Chilli Powder 100 g | 100 g | — | Not yet classified |
| e95e1f0f-38c7-494b-9b3f-42d5adfaee2d (v9) | Aachi Kashmiri Chilli Powder 50 g | 50 g | — | Not yet classified |
| cb1cc5fd-bd0a-4ee1-9d8a-b5cfb03a85ce (v9) | Aachi Pepper Powder 100 g | 100 g | — | Not yet classified |
| 5595701a-d126-47ad-a5a8-81747c098bb3 (v9) | Aachi Pepper Powder 50 g | 50 g | — | Not yet classified |
| 50f1f0ca-5cd5-43bd-97fa-f4513e845ad7 (v9) | MTR Kali Mirch Black Pepper Powder 100 g | 100 g | — | Not yet classified |
| a7b3431c-43da-45bd-8002-5ad4df301792 (v9) | Aachi Turmeric Powder 100 g | 100 g | — | Not yet classified |
| 4ba5211f-68a7-4f0a-bfdd-ff663eea1f20 (v9) | Aachi Turmeric Powder 200 g | 200 g | — | Not yet classified |
| 60baab60-bb2c-469d-8fbd-623082840480 (v9) | MTR Turmeric Powder 100 g | 100 g | — | Not yet classified |
| 2c25ac4b-7abf-4325-9dc6-cfc9b49e8955 (v9) | MTR Turmeric Powder 250 g | 250 g | — | Not yet classified |
| bf0f0305-1ab5-465c-9994-cb309ec5d0d2 (v9) | MTR Turmeric Powder 500 g | 500 g | — | Not yet classified |

### Masalas / Salt

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 16d762d9-f275-4c49-8380-18024d854ed2 (v8) | Tata Salt 1 Kg \| Free flowing & Iodised Namak \| Vacuum Evaporated \| Salt in Fresh 1 kg | 1 kg | — | Not yet classified |

### Sauces and Spreads / Asian Sauces

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 0a783953-7798-48fc-9609-7cf26ed22942 (v8) | Ching's Secret Ching’s Manchurian Stir Fry Sauce \| 250gm 250 g | 250 g | — | Not yet classified |
| 6c966ced-3d43-413e-b17d-a8440f1b8711 (v8) | Ching's Secret Ching’s Paneer Stir Fry Sauce \| 250gm \| No Added Colour, No MSG \| Perfect for Hakka Noodles or Chowmein 250 g | 250 g | — | Not yet classified |
| be8fb437-3b50-4e8a-923f-3b0c90fe87b9 (v8) | Ching's Secret Chings Chowmein Stir Fry Sauce \| 250gm 250 g | 250 g | — | Not yet classified |
| 0d3cacdb-bef8-4404-a60f-6e4d5d704af4 (v8) | Ching's Secret Schezwan Stir Fry Sauce \| Bold, Fiery and Spicy Flavour \| Spice up your snacks \| Authentic Desi Chinese \| Glass Bottle \| 250g 250 g | 250 g | — | Not yet classified |
| 37191cbb-6477-450f-9ecf-e6c1b9fb3f69 (v8) | Ching's Secret Dark Soy Sauce 210 g | 210 g | — | Not yet classified |
| ad9b2ce0-bbf7-498d-a737-3d8c0b59e010 (v8) | Ching's Secret Dark Soy Sauce 90 g | 90 g | — | Not yet classified |

### Sauces and Spreads / Cooking Sauces

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 37564b78-f942-4a2f-bc4e-0bea8fb174f7 (v8) | Ching's Secret Ching's Chilli Sauce \| 680gm 680 g | 680 g | — | Not yet classified |
| 867e8607-5881-4729-b792-e74bcf748c70 (v8) | Ching's Secret Ching's Secret Green Chilli Sauce - 190 Gm 190 g | 190 g | — | Not yet classified |
| d3c7680e-e749-4dc2-91bc-45859c507880 (v8) | Ching's Secret Ching's Secret Red Chilli Sauce \| 200 Gm 200 g | 200 g | — | Not yet classified |
| 3bbb1adf-b862-45f6-8876-da82bf05538f (v8) | Ching's Secret Green Chilli Sauce 90 g | 90 g | — | Not yet classified |
| 8d75abdc-edc9-470a-9623-6a906b295ad1 (v8) | Ching's Secret Original Sriracha Hot Chilli Sauce (Green)  Perfect Blend Of Spicy & Tangy \| Dip, Spread, Cook, Drizzle \| 100% Veg \| 225g / 530g 225 g | 225 g | — | Not yet classified |
| df6da5b7-325e-4bf6-abe6-bc9b473c85dd (v8) | Ching's Secret Original Sriracha Hot Chilli Sauce (Green)  Perfect Blend Of Spicy & Tangy \| Dip, Spread, Cook, Drizzle \| 100% Veg \| 225g / 530g 530 g | 530 g | — | Not yet classified |
| 59dd0524-de5b-4d4d-9755-8ce0f200aa4a (v8) | Ching's Secret Original Sriracha Hot Chilli Sauce (Red)  Perfect Blend Of Spicy & Tangy \| Dip, Spread, Cook, Drizzle \| 100% Veg \| 230g 230 g | 230 g | — | Not yet classified |
| e71fe4f6-8e30-42b7-b3f4-012df1d6b2e2 (v8) | Ching's Secret Red Chilli Sauce 90 g | 90 g | — | Not yet classified |

### Oils and Ghee / Sunflower Oils

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 8d874dd0-e44b-47c3-80db-18f8b738e589 (v5) | Fortune Sunlite Refined Sunflower Oil 1 L Pouch | 1 L | — | Not yet classified |
| 9ab82ca4-b17c-4faa-a2b9-b7bc18476a01 (v5) | Fortune Sunlite Refined Sunflower Oil 2 L PET Bottle | 2 L | — | Not yet classified |
| 3a14c9dc-09f3-4389-8bc0-fc2ce0a53496 (v6) | Fortune Sunlite Refined Sunflower Oil 5 L PET Bottle | 5 L | — | Not yet classified |

### Oils and Ghee / Ghee

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 190dec68-8d29-4df5-9fe3-19d1d3d2b26e (v7) | Aachi Pure Ghee 1 l | 1 l | — | Not yet classified |
| 3fa4fdf3-0ec7-45d2-88c1-4ab4a5abe92b (v7) | Aachi Pure Ghee 200 ml | 200 ml | — | Not yet classified |
| f320b873-2e3d-4dc4-9351-cd80c8e782e4 (v7) | Aachi Pure Ghee 500 ml | 500 ml | — | Not yet classified |

### Chips and Namkeens / Chips and Crisps

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| dc03ee0c-3c73-42cf-8a32-a4c68ab7cf69 (v7) | Open Secret Open Secret Ragi Chips - Chatpata 30g 30 g | 30 g | — | Not yet classified |
| 7f355814-3317-4ed6-94a2-b42835a3f81c (v7) | Open Secret Open Secret Ragi Chips - Korean Mirchi 30g 30 g | 30 g | — | Not yet classified |
| 137cb039-b32c-40a4-ac2b-c103cf395303 (v4) | Desi Masala Chips by Max Protein | 150 g | — | Not yet classified |
| 6441fdda-7f2b-483b-bbe4-8508c70667fe (v4) | Max Protein Barbeque Korean Chips | 1 unit | — | Not yet classified |
| f7adf392-5e18-4feb-9983-06a7e6b48795 (v4) | Max Protein Cheese & Jalapeno Chips | 150 g | — | Not yet classified |
| f4531e83-54cc-4c67-a427-84fb83556259 (v4) | Max Protein Chinese Manchurian Chips | 150 g | — | Not yet classified |
| 85022748-cf72-46ed-92ad-19eeb55e98d6 (v4) | Max Protein Cream & Onion Chips | 150 g | — | Not yet classified |
| 9a979e22-30ea-4912-b8ff-a8a8f4426b03 (v4) | Max Protein Gochujang Korean Chips | 1 unit | — | Not yet classified |
| a10794cb-c4ba-4910-8f83-bb934ba43d68 (v4) | Max Protein Hot Chilli Korean Chips | 1 unit | — | Not yet classified |
| 1cd070c3-ef64-442f-9466-46c50bff5194 (v4) | Max Protein Peri Peri Chips | 150 g | — | Not yet classified |
| ffe1aac1-4a0c-4a2f-a48f-05e222e017b0 (v4) | Max Protein Spanish Tomato Chips | 150 g | — | Not yet classified |

### Cereals and Breakfast / Energy Bars

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 8876c527-de15-4ed3-a40b-2dc188a644ab (v4) | Max Protein Bar - Active Date & Almond (Single Pack) | 1 unit | — | Not yet classified |
| 1db080f2-edf0-4c32-aeff-c6ef373a54b0 (v4) | RiteBite Choco Delite Bar (Pack of 6) | 40 g × 6 | — | Not yet classified |
| 79380956-2f6e-4d16-af2f-325fd47664a8 (v4) | RiteBite Choco Delite Bar (Single Pack) | 40 g | — | Not yet classified |
| 95e2fcce-ada2-4b73-b6cf-af492396af05 (v4) | RiteBite Choco Delite Bar 40 g × 12 | 40 g × 12 | — | Not yet classified |
| b08d22e3-4e9c-4381-aa38-c515c0244000 (v4) | RiteBite Fruits & Seeds Bar (Pack of 12) | 35 g × 12 | — | Not yet classified |
| e2c788d3-9603-44f7-b6be-e27b39078ba2 (v4) | RiteBite Fruits & Seeds Bar (PACK OF 6) | 35 g × 6 | — | Not yet classified |
| bf2ed427-b53e-4df9-be21-5972a383790c (v4) | RiteBite Fruits & Seeds Bar (Single Pack) | 35 g | — | Not yet classified |
| 3b4a2f4d-09c1-4c10-a7b4-e615fec514aa (v6) | RiteBite Max Protein 5g Protein Bytes Pack of 10 | 1 unit × 10 | — | Not yet classified |
| b739804c-d440-4c91-a1bb-537e35bab8a5 (v4) | RiteBite Max Protein 5g Protein Bytes Single Choco Almond 17g 17 g | 17 g | — | Not yet classified |
| 310b9bd0-01bc-4984-b7d3-b5f8b2fb4fac (v4) | RiteBite Max Protein 5g Protein Bytes Single Choco Berry 17g 17 g | 17 g | — | Not yet classified |
| d8dfed3c-ca2f-4d13-adf3-6621a5980411 (v4) | RiteBite Max Protein 5g Protein Bytes Single Date & Almond 19g 19 g | 19 g | — | Not yet classified |
| 4df8c32c-18d5-4a65-ad52-09998752b036 (v4) | RiteBite Max Protein Active Choco Fudge 1 unit | 1 unit | — | Not yet classified |
| 9af3c3b9-f169-4e0d-ba50-1d8ab54e8e85 (v4) | RiteBite Max Protein Active Choco Fudge 1 unit × 12 | 1 unit | — | Not yet classified |
| d60a7a90-0c9a-4190-8c29-c5cbc8a2bc73 (v4) | RiteBite Max Protein Active Choco Fudge 1 unit × 6 | 1 unit | — | Not yet classified |
| 1bdd03a1-bc12-4a89-9439-8469d8688e0a (v4) | RiteBite Max Protein Active Choco Slim 1 unit | 1 unit | — | Not yet classified |
| aa6af58a-e7f7-4ad4-bb45-f5b95d467f17 (v4) | RiteBite Max Protein Active Choco Slim 1 unit × 12 | 1 unit | — | Not yet classified |
| 702325ac-bbbf-468d-8b6a-6c4a2fa3ae7c (v4) | RiteBite Max Protein Active Choco Slim 1 unit × 6 | 1 unit | — | Not yet classified |
| 398d195d-1099-4339-8141-2fdcfac19e5a (v4) | RiteBite Max Protein Active Date & Almond 1 unit | 1 unit | — | Not yet classified |
| 08bb6068-2972-462a-a4e7-dcb5a0b4cf37 (v4) | RiteBite Max Protein Active Date & Almond 1 unit × 12 | 1 unit | — | Not yet classified |
| 5b75c01f-3ce9-486d-9694-ae5ca5552ae4 (v4) | RiteBite Max Protein Active Date & Almond 1 unit × 6 | 1 unit | — | Not yet classified |
| 26fa3ce0-2bac-425b-8677-9508cc0afccb (v4) | RiteBite Max Protein Active Green Coffee Beans 1 unit | 1 unit | — | Not yet classified |
| 486c1f50-94b9-4cf9-a2a8-b398bd057fd2 (v4) | RiteBite Max Protein Active Green Coffee Beans 1 unit × 12 | 1 unit | — | Not yet classified |
| 35f440af-0bdc-40dd-9102-9e123215c398 (v4) | RiteBite Max Protein Active Green Coffee Beans 1 unit × 6 | 1 unit | — | Not yet classified |
| e86ce04b-8627-4175-b9a2-ad7d988b50b1 (v4) | RiteBite Max Protein Daily Choco Almond 1 unit × 24 | 1 unit | — | Not yet classified |
| e445b0a2-5fed-4165-b78c-f2332be3e921 (v4) | RiteBite Max Protein Daily Choco Berry 1 unit × 24 | 1 unit | — | Not yet classified |
| 32b2da24-0ac3-4001-aeaf-f110d24a9896 (v4) | RiteBite Max Protein Daily Choco Classic 1 unit × 24 | 1 unit | — | Not yet classified |
| a5e5139f-9a43-492d-bdda-7c5ea7ba2590 (v4) | RiteBite Max Protein Daily Fruit & Nut 1 unit | 1 unit | — | Not yet classified |
| cf268cb2-7062-4881-bd5f-d877649531b3 (v4) | RiteBite Max Protein Daily Fruit & Nut 1 unit × 24 | 1 unit | — | Not yet classified |
| af4922e9-3aa2-439b-a179-b976d5322711 (v4) | RiteBite Max Protein Daily Fruit & Nut 1 unit × 6 | 1 unit | — | Not yet classified |
| c3f88970-132f-470e-8c22-82ec94b19458 (v4) | RiteBite Max Protein Daily Salt & Caramel Bar 50 g | 50 g | — | Not yet classified |
| 01f21070-28cb-4774-89d8-165edac8d22e (v4) | RiteBite Max Protein Daily Salt & Caramel Bar 50.0000000000000000 g × 24 | 50.0000000000000000 g | — | Not yet classified |
| 0834b7bb-e325-489a-b91c-1360861f7628 (v4) | RiteBite Max Protein Daily Salt & Caramel Bar 50.0000000000000000 g × 6 | 50.0000000000000000 g | — | Not yet classified |
| 5f2b92e8-d44c-42db-9bd2-83ebccf3313d (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Choco Temptation 1 unit | 1 unit | — | Not yet classified |
| 96f86c51-0078-44c8-8229-863965cefc9a (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Choco Temptation 1 unit × 12 | 1 unit | — | Not yet classified |
| f05f005c-bbcd-4ba8-9a0d-1d8a8b88fd87 (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Choco Temptation 1 unit × 6 | 1 unit | — | Not yet classified |
| c4ec9ff6-d095-4226-8267-18a10bf6938b (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Coffee Mousse 1 unit | 1 unit | — | Not yet classified |
| 895f1ad0-0f5b-4b5b-bd1f-683b36568d66 (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Coffee Mousse 1 unit × 12 | 1 unit | — | Not yet classified |
| fe66687f-7a31-449d-86a1-dfa50134cc54 (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Coffee Mousse 1 unit × 6 | 1 unit | — | Not yet classified |
| 350fca02-79ec-4d57-9d04-7f6ac27410ad (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Strawberry Truffle 1 unit | 1 unit | — | Not yet classified |
| 018b4584-b072-43c2-907b-00bc0c2b154b (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Strawberry Truffle 1 unit × 12 | 1 unit | — | Not yet classified |
| 5d9beb1b-958f-4410-8819-211001454b04 (v4) | RiteBite Max Protein Millet Wafer Protein Bar - Strawberry Truffle 1 unit × 6 | 1 unit | — | Not yet classified |
| 4b48f20a-fc15-4d25-a1ca-6c932cc5f039 (v4) | RiteBite Max Protein Peanut Butter Bar 1 unit | 1 unit | — | Not yet classified |
| bf476089-8cfe-43b5-8e59-a84bb0b9ef66 (v4) | RiteBite Max Protein Roots – Cocoa Brownie Protein Bar 1 unit | 1 unit | — | Not yet classified |
| 2daaeb39-4aa4-48cf-a2d3-090437c1c716 (v4) | RiteBite Max Protein Roots – Cocoa Brownie Protein Bar 1 unit × 6 | 1 unit | — | Not yet classified |
| 6b3facc4-57b5-4ef3-a1fe-02abf1e1bbf5 (v4) | RiteBite Max Protein Roots – Coffee Mocha Protein Bar 1 unit | 1 unit | — | Not yet classified |
| 292d8219-889e-45eb-805f-8764f1baca81 (v4) | RiteBite Max Protein Roots – Coffee Mocha Protein Bar 1 unit × 6 | 1 unit | — | Not yet classified |
| 63ae8b8b-73cc-43e0-a575-adf4f6da2afd (v4) | RiteBite Max Protein Roots – Orange Burst Protein Bar 1 unit | 1 unit | — | Not yet classified |
| a949c573-0a15-4a58-a1a6-d37d491cd8db (v4) | RiteBite Max Protein Roots – Orange Burst Protein Bar 1 unit × 6 | 1 unit | — | Not yet classified |
| d97aea8f-db9e-417e-9ce7-a1238b242896 (v4) | RiteBite Nuts & Seeds Bar (Pack of 12) | 1 unit × 12 | — | Not yet classified |
| b2c96cc5-4093-4e0c-b85b-239558c52a56 (v4) | RiteBite Nuts & Seeds Bar (Pack of 6) | 35 g × 6 | — | Not yet classified |
| ade1e79f-d702-4d43-aa00-b610a652f399 (v4) | RiteBite Nuts & Seeds Bar (Single Pack) | 35 g | — | Not yet classified |
| 138637f9-459d-4c2d-b6c5-1f3479559aeb (v4) | RiteBite Sports Bar (Pack of 12) | 1 unit × 12 | — | Not yet classified |
| 82903d9a-011c-4411-83cd-002d4125a9bd (v4) | RiteBite Sports Bar (PACK OF 6) | 40 g × 6 | — | Not yet classified |
| f6e264b0-810d-4934-a743-9496097a058f (v4) | RiteBite Sports Bar (Single Pack) | 40 g | — | Not yet classified |
| a8477c50-1124-4205-a663-eed44b574dc4 (v4) | RiteBite Yogurt Berry Bar (Pack of 12) | 35 g × 12 | — | Not yet classified |
| 395132ae-95dc-4b5a-b39f-b154e783fa24 (v4) | RiteBite Yogurt Berry Bar (Pack of 6) | 35 g × 6 | — | Not yet classified |
| 80dd8e0a-a104-4583-954b-ea7c3fdaac09 (v4) | RiteBite Yogurt Berry Bar (Single Pack) | 35 g | — | Not yet classified |

### Chips and Namkeens / Bhujia and Namkeens

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 1c996d4d-f5b9-4f4b-875c-3a384933045a (v5) | Open Secret Open Secret Unjunked Bhujia (175g x 2) 175 g ×2 | 175 g | — | Not yet classified |

### Chips and Namkeens / Nuts

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 90261797-14fc-4f31-be03-cb6fcc49bd51 (v5) | Open Secret Nutty Almonds : Orange Cocoa : 60g (Pack of 2) 60 g ×2 | 60 g | — | Not yet classified |
| e0b6ebf5-fc8c-463b-8141-f8312e659b27 (v5) | Open Secret Open Secret Tandoori Masala Nut Mix ( Pack of 60gm ) 60 g | 60 g | — | Not yet classified |

### Atta, Flour & Dal / Besan, Sooji and Maida

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 90bf99f8-b1c8-400e-ab1e-a1b895d3d199 (v4) | Aashirvaad Suji Rava | 500 g | — | Not yet classified |
| d9db03a2-34ea-4dcb-bed8-08aaf4de078c (v6) | Aashirvaad Suji Rava | 1 kg | — | Not yet classified |
| bdf32080-ab33-429f-8cf4-ffba77430d0b (v4) | Fortune Maida | 500 g | — | Not yet classified |

### Atta, Flour & Dal / Atta

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 51524c16-27d2-426e-99f9-9d871f659022 (v7) | Aashirvaad Atta with Multigrains 1 kg | 1 kg | — | Not yet classified |
| 8cfa8c9f-5a52-4874-b9c6-776bfdef04dc (v7) | Aashirvaad Atta with Multigrains 5 kg | 5 kg | — | Not yet classified |
| f2625c32-2085-40b5-ac6d-0d4181641848 (v7) | Aashirvaad Sugar Release Control Atta 1 kg | 1 kg | — | Not yet classified |
| 393af427-fc89-44b2-8b13-95023abb7ee3 (v5) | Pillsbury Multigrain Atta | 1 kg | — | Not yet classified |
| 8a59f35d-6676-407e-902e-08ac1709e188 (v5) | Aashirvaad Select 100% MP Sharbati Atta 1 kg | 1 kg | — | Not yet classified |
| 3b77c2fd-a5ff-4529-b2bc-c66efc481f4e (v5) | Aashirvaad Select 100% MP Sharbati Atta 5 kg | 5 kg | — | Not yet classified |
| 5be5f563-fdc4-4d50-9033-28201052aa6c (v5) | Aashirvaad Superior MP Atta 1 kg | 1 kg | — | Not yet classified |
| 6eea2c83-fe76-4dea-a44c-39418e6df7e5 (v5) | Aashirvaad Superior MP Atta 10 kg | 10 kg | — | Not yet classified |
| 1288a0a2-e181-4119-ac44-fa68b3cff70b (v5) | Aashirvaad Superior MP Atta 2 kg | 2 kg | — | Not yet classified |
| bea43582-6132-4095-9cac-58d027e21c49 (v5) | Aashirvaad Superior MP Atta 5 kg | 5 kg | — | Not yet classified |
| 31825dbc-17fc-43dc-b27d-bb600332b0b7 (v5) | Fortune Chakki Fresh Atta 1 kg | 1 kg | — | Not yet classified |
| 4a18b238-4507-45bc-b6a0-50b49d454ad9 (v5) | Fortune Chakki Fresh Atta 10 kg | 10 kg | — | Not yet classified |
| 2c22fd71-539a-4434-af7d-b68fbfd494c8 (v5) | Fortune Chakki Fresh Atta 5 kg | 5 kg | — | Not yet classified |
| 06014107-1403-4266-971f-941b17109edc (v3) | Pillsbury Chakki Fresh Atta | 1 kg | — | Not yet classified |
| 3e62a964-20f3-4398-85a1-f54bf8284ac8 (v3) | Pillsbury Chakki Fresh Atta | 5 kg | — | Not yet classified |
| b9833c19-8983-464c-9214-ad6da561a24f (v4) | Pillsbury Chakki Fresh Atta | 10 kg | — | Not yet classified |

### Atta, Flour & Dal / Basmati Rice

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| b56b72ea-82af-4fe1-bf50-3ef5edbfcd91 (v6) | Daawat Biryani Basmati Rice 1 kg | 1 kg | — | Not yet classified |
| 701dbdfc-6f7c-46c3-aa36-d0903bd57321 (v7) | Daawat Biryani Basmati Rice 500 g | 500 g | — | Not yet classified |
| 6fa8a6b8-8ec9-499d-b4f4-455e85482b0b (v4) | Daawat Traditional Basmati Rice | 1 kg | — | Not yet classified |
| 381eba54-c7c1-4779-858a-0c63200275ec (v5) | Fortune Everyday Basmati Rice 1 kg | 1 kg | — | Not yet classified |
| 8b35f9ac-bc64-44d8-8f46-f64b6198321d (v5) | India Gate Classic Basmati Rice | 5 kg | — | Not yet classified |
| a2e99a9a-2547-48c3-8ab6-80bc40299656 (v3) | India Gate Classic Basmati Rice | 1 kg | — | Not yet classified |
| ea3334a5-be81-457c-a457-3ba0d844fa87 (v7) | India Gate Classic Basmati Rice | 500 g | — | Not yet classified |
| 0ee65a01-80ff-4690-82d7-50069cf50a93 (v5) | India Gate Daily Premium Basmati Rice 1 kg | 1 kg | — | Not yet classified |
| d11a0a59-a8ca-4390-b850-7025ba29fec6 (v5) | India Gate Daily Premium Basmati Rice 5 kg | 5 kg | — | Not yet classified |
| e6b79f0d-a811-427c-8378-467bec0bdc2d (v6) | India Gate Everyday Basmati Rice 1 kg | 1 kg | — | Not yet classified |
| b87b4ceb-2021-4b3e-89f0-d6f14ce13c3a (v6) | India Gate Everyday Basmati Rice 5 kg | 5 kg | — | Not yet classified |
| 4f263fb4-d8ba-4a1b-b8ed-d240c14cc719 (v5) | India Gate Super Basmati Rice 1.5 kg | 1.5 kg | — | Not yet classified |
| ad360ce5-936c-46e7-8008-f81cb1a5f1f9 (v3) | Kohinoor Traditional Authentic Basmati Rice | 1 kg | — | Not yet classified |

### Tea Coffee and Milk Drinks / Drink Mixes

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| bb7c1a0b-0fd1-46fd-9836-437f69a13042 (v7) | MTR Badam Drink Can 180 ml | 180 ml | — | Not yet classified |
| 4bc3bd58-4c91-4e66-b2db-1158c950df05 (v7) | MTR Badam Drink Mix 100 g | 100 g | — | Not yet classified |
| d284b8d5-8fe3-466c-88ae-1484ad8c09d3 (v7) | MTR Badam Drink Mix 200 g | 200 g | — | Not yet classified |
| 8f832405-c0bd-4f25-b971-24fa425e6cf6 (v7) | MTR Badam Drink Mix Jar 1 kg | 1 kg | — | Not yet classified |
| 6756f399-9249-4285-8cce-7c063839e5f2 (v7) | MTR Badam Drink Mix Jar 500 g | 500 g | — | Not yet classified |
| 3b3d21ee-ddf8-40b3-9c5c-587def741d78 (v7) | MTR Badam Drink Refill Pack 450 g | 450 g | — | Not yet classified |

### Tea Coffee and Milk Drinks / Tea

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| a615eacb-cb93-4f2b-87ec-c5b00b281a0b (v8) | Tata Tea Agni 250 g | 250 g | — | Not yet classified |
| a8bf5393-8eb5-467b-96a1-0b9c0f192d09 (v8) | Tata Tea Agni 500 g | 500 g | — | Not yet classified |
| acfe51b1-7826-4623-82c3-d84ffc5dbed0 (v8) | Tata Tea Gold Care \| Rich in Taste, Goodness of 5 Natural Ingredients \| Elaichi, Ginger, Tulsi, Brahmi & Mulethi \| Strong Flavour \| 500g / 1Kg 1 kg | 1 kg | — | Not yet classified |
| 6bb8b10a-84fc-4243-bcb8-cc8e672c8bc2 (v8) | Tata Tea Gold Care \| Rich in Taste, Goodness of 5 Natural Ingredients \| Elaichi, Ginger, Tulsi, Brahmi & Mulethi \| Strong Flavour \| 500g / 1Kg 500 g | 500 g | — | Not yet classified |
| 295c4afd-cacf-4173-8bf1-dd8e656c5dea (v7) | Tata Tea Premium - Teaveda 250 g | 250 g | — | Not yet classified |
| f1961a3d-cf78-4d18-9450-af901d176a97 (v7) | Tata Tea Premium \| Desh ki Chai 250 g | 250 g | — | Not yet classified |
| f8d1425a-0b1f-4c1d-a4fc-09932c63029e (v7) | Tata Tea Premium \| Desh ki Chai 500 g | 500 g | — | Not yet classified |
| e9e78a07-6f68-4587-9b6a-8020105b4746 (v8) | Tata Tea Tata Gold \| Gently Rolled \| Aromatic Long Leaves \| Assam CTC leaves \| Premium Quality \| Loose Leaves Pack \|  250g / 500g / 1Kg 500 g | 500 g | — | Not yet classified |
| 3374849b-eefa-46cd-bf2d-4f4d4ca764d0 (v8) | Tata Tea Tata Tea Premium Leaf \| 1 Kg 1 kg | 1 kg | — | Not yet classified |
| 44362941-a883-443f-b818-364c7aeef329 (v8) | Tata Tea Gemini Dust Tea \| Strong Assam Tea 100 g | 100 g | — | Not yet classified |
| 1b2ab171-8295-4695-b1eb-e32ee2242fac (v8) | Tata Tea Tata Tea Agni -  Extra Josh \| 225 g 225 g | 225 g | — | Not yet classified |
| 964256aa-c081-4401-89a6-7607b0b24c42 (v8) | Tata Tea Tata Tea Agni -  Extra Josh \| 225 g 450 g | 450 g | — | Not yet classified |
| 4476c8a6-d33a-469a-86a4-c5a851a64efd (v8) | Tata Tea TATA TEA AGNI \| Strong Chai \| Dust Tea \| Black Tea \| - 500 Gm 500 g | 500 g | — | Not yet classified |
| a3b3d2db-203a-4b13-9120-00828c9fb3e1 (v8) | Tata Tea Elaichi Chai 250 g | 250 g | — | Not yet classified |
| 3f84e464-18a9-4e11-8813-816bc68a40bd (v8) | Tetley Earl Grey - Flavoured Tea \| Rich Assam Blend \| Environment Friendly, Staple-free Tea Bags \| Easy to Make \| 50 Tea Bags 50 tea_bag | 50 tea_bag | — | Not yet classified |
| f7deb6ab-a3a5-447d-b01e-2b477d00de1a (v8) | Tata Tea Chakra Gold - Care \| Goodness of 5 Natural Ingredients \| Tulsi, Ginger, Elaichi, Brahmi \| Rich Taste & Aromatic 100 g | 100 g | — | Not yet classified |
| 43dd82ed-5e32-4f50-a95f-68477a54e18b (v8) | Tata Tea Chakra Gold - Care \| Goodness of 5 Natural Ingredients \| Tulsi, Ginger, Elaichi, Brahmi \| Rich Taste & Aromatic 250 g | 250 g | — | Not yet classified |
| b3a5cfda-3e6d-499b-ba9a-2a3cdc774674 (v8) | Tata Tea Chakra Gold - Care \| Goodness of 5 Natural Ingredients \| Tulsi, Ginger, Elaichi, Brahmi \| Rich Taste & Aromatic 500 g | 500 g | — | Not yet classified |
| 3eedc41a-acb3-43c3-af13-2815fa87bfcd (v8) | Tata Tea Chakra Gold - Premium Leaf Tea \| With Added Longe Leaves \| From Assam \| Rich Aroma & Taste 250 g | 250 g | — | Not yet classified |
| 3eb0ba80-1661-42ad-b0b1-97026014dbdf (v8) | Tata Tea Chakra Gold - Premium Leaf Tea \| With Added Longe Leaves \| From Assam \| Rich Aroma & Taste 500 g | 500 g | — | Not yet classified |
| 244e20b6-fcde-4a2f-804e-e19af5895177 (v7) | Tata Tea Chakra Gold - Premium Tea \| Rich & Strong Taste \|Long lasting flavour \| High Quality Assam Tea \| 100g / 250g / 500g 100 g | 100 g | — | Not yet classified |
| 0264158a-c828-494c-8b05-9951cba823f2 (v7) | Tata Tea Chakra Gold - Premium Tea \| Rich & Strong Taste \|Long lasting flavour \| High Quality Assam Tea \| 100g / 250g / 500g 250 g | 250 g | — | Not yet classified |
| 9c564b2b-def0-47a0-bccd-a0d8d826a255 (v7) | Tata Tea Chakra Gold - Premium Tea \| Rich & Strong Taste \|Long lasting flavour \| High Quality Assam Tea \| 100g / 250g / 500g 500 g | 500 g | — | Not yet classified |
| 401ab025-9c40-4940-9aab-6c1973236d2e (v8) | Tata Tea Tata Tea Chakra Gold \| Premium Leaf Tea 100g 100 g | 100 g | — | Not yet classified |
| 4bb0c94b-fb5b-4b7a-94b4-66660b5bd46f (v8) | Tetley Masala Chai With Natural Flavour 50 tea_bag | 50 tea_bag | — | Not yet classified |
| 8fc19744-ba09-4ab6-a764-4907abd92b85 (v7) | Tetley Tetley Original Black Tea \| 250 Tea Bags 250 tea_bag | 250 tea_bag | — | Not yet classified |

### Tea Coffee and Milk Drinks / Green & Herbal Tea

| SKU ID (version) | Existing product | Pack | Proposed type | Review status |
|---|---|---|---|---|
| 29e046ee-40b1-46b5-85e7-a8ce2a815129 (v8) | Tata Tea Gold - Kashir Noon Chai 1 kg | 1 kg | — | Not yet classified |
| fab0fe95-0da1-42e6-ab34-48df75e757da (v8) | Tata Tea Gold - Kashir Noon Chai 250 g | 250 g | — | Not yet classified |
| a32c91d0-ab1e-4220-9cbc-8c67e2221b94 (v8) | Tata Tea Gold - Kashir Noon Chai 500 g | 500 g | — | Not yet classified |
| e47eea5c-e515-4772-a6a0-8f78f31dce08 (v7) | Tetley Green Tea - Long Leaf, Original Flavour\| Rich in Anti-Oxidants \| 100% plastic-free and staple-free tea bags \| 100g / 250g / 500g 100 g | 100 g | — | Not yet classified |
| 13a9a2ef-d09d-4ff2-a1e9-c32701197feb (v7) | Tetley Green Tea - Long Leaf, Original Flavour\| Rich in Anti-Oxidants \| 100% plastic-free and staple-free tea bags \| 100g / 250g / 500g 250 g | 250 g | — | Not yet classified |
| 217b8ba7-17d0-49b9-ba39-b9d32f09b619 (v7) | Tetley Green Tea - Long Leaf, Original Flavour\| Rich in Anti-Oxidants \| 100% plastic-free and staple-free tea bags \| 100g / 250g / 500g 500 g | 500 g | — | Not yet classified |
| 0cb8cc96-ad02-4ec8-8027-6157ba3be679 (v7) | Tetley Green Tea Immune, With Added Vitamin C \| Classic Green Tea Flavour \| Boosts Immunity \|Rich in Anti-Oxidants \| 100 tea bags 100 tea_bag | 100 tea_bag | — | Not yet classified |
| 6a28e73f-75a1-402c-ba8f-cb64584fbb36 (v7) | Tetley Green Tea Immune, With Added Vitamin C 10 tea_bag | 10 tea_bag | — | Not yet classified |
| a4e4b86f-d8b6-4a5b-bce7-82464b9a98b6 (v7) | Tetley Green Tea Immune, With Added Vitamin C 100 tea_bag | 100 tea_bag | — | Not yet classified |
| a0f7fc83-3d72-4125-a786-6c6e734965e2 (v7) | Tetley Green Tea Immune, With Added Vitamin C 25 tea_bag | 25 tea_bag | — | Not yet classified |
| efcb6657-a425-4d04-acc8-e720bac31d49 (v7) | Tetley Green Tea Immune, With Added Vitamin C 50 tea_bag | 50 tea_bag | — | Not yet classified |
| b96abe24-3e66-4394-a9e3-6cb93de319da (v7) | Tetley Green Tea With Tulsi 25 tea_bag | 25 tea_bag | — | Not yet classified |
| 00ebe295-151c-4171-b69a-8991c1e1d2a6 (v8) | Tetley Naturally Sweet Green Tea with Mango Flavour 25 tea_bag | 25 tea_bag | — | Not yet classified |
| d5ddc6fe-798e-415e-a365-bd19629c385e (v8) | Tetley Tetley \| Ginger, Mint & Lemon Flavored Green Tea \| 100 Tea Bags 100 tea_bag | 100 tea_bag | — | Not yet classified |

Review SHA-256: `0bfb827e7fa6b7a0d0d9f14120b476b0ab37314e2f1f095ab24d1631245d0181`
