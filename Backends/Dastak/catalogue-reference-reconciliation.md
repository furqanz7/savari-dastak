# Dastak catalogue reference reconciliation

Status: audit baseline, not a deployed catalogue map. Source: the 90 images in
`/Users/Furqan/Downloads/Catalogue Map Dastak` (IMG_3322–IMG_3413), the user's
later corrections, and a read-only production taxonomy/SKU count on 26 Sep 2026.
The screenshots are layout and category references, **not** authorization to
create the products pictured in them. Reorganize existing Dastak SKUs only.

## Non-negotiable decisions

- One consistent browse map for customer, merchant and admin; native clients must
  not fall back to a conflicting canonical hierarchy.
- Keep existing SKU IDs and merchant selections. Do not duplicate SKU rows to
  display a product in more than one browse destination.
- Remove High Protein Atta from the browse map.
- Use **Atta, Flour & Dal** and **Masalas** on both the home and detail screens.
- A browse rail must have an explicit parent-qualified target. Never resolve a
  rail by a display name, unqualified slug, or its position in the array.
- An empty reference destination may be visible, but must say zero products;
  it must never borrow SKUs from a neighbouring destination.

## Reference home destinations

| Section | Destinations, in reference order | Present canonical source(s) |
| --- | --- | --- |
| Fresh Items | Fresh Vegetables; Fresh Fruits; Dairy, Bread & Eggs; Meat and Seafood | `fresh-produce` and `dairy-bread-eggs` |
| Grocery & Kitchen | Atta, Flour & Dal; Masalas; Oils and Ghee; Cereals and Breakfast | `staples-pantry`; `masala-cooking`; pending `oils-ghee`; `breakfast-spreads` |
| Snacks & Drinks | Cold Drinks and Juices; Ice Creams and Frozen; Chips and Namkeens; Chocolates; Biscuits and Cakes; Tea Coffee and Milk Drinks; Sauces and Spreads; Sweet Corner; Noodles Pasta Vermicelli; Frozen Food; Dry Fruits and Seeds Mix; Paan Corner | `beverages`; `instant-ready-frozen-food`; `snacks-munchies`; `chocolates-sweets`; `biscuits-bakery`; `tea-coffee-drink-mixes`; **two sources** for Sauces and Spreads (`breakfast-spreads/spreads` and `masala-cooking/sauces-condiments`); `paan-corner` |
| Beauty & Wellness | Bath and Body; Hair Care; Skincare; Makeup; Feminine Hygiene; Sexual Wellness; Health and Pharma; Baby Care | `personal-care`; `beauty-grooming`; `health-hygiene`; `pharmacy`; `baby-care`; Sexual Wellness has no canonical source yet |
| Household & Lifestyle | Home and Kitchen; Pooja Store; Cleaners and Repellents; Toys and Stationery; Electronics and Appliances; Fashion; Pet Supplies; Sports and Fitness | `kitchen-dining`/`home-utility`; `puja-festive`; `home-cleaning`; `toys-games-kids`/`stationery-office-school`; `electronics-accessories`; `pet-care`; Fashion and Sports and Fitness have no canonical source yet |

The reference also contains detailed rails under each destination. The current
shared web presentation module curates only **Atta, Flour & Dal** and
**Masalas**. All other web destinations fall back to the old taxonomy, and
the native customer browser uses that taxonomy directly. Therefore matching
home labels alone is not a three-app fix.

## Production SKU baseline (before the 2026-09-26 Pani Puri Kit removal)

At that checkpoint there were **574 active existing SKUs**. By canonical department:

| Department slug | Active SKUs |
| --- | ---: |
| `masala-cooking` | 179 |
| `breakfast-spreads` | 84 |
| `snacks-munchies` | 73 |
| `instant-ready-frozen-food` | 70 |
| `dairy-bread-eggs` | 63 |
| `tea-coffee-drink-mixes` | 46 |
| `staples-pantry` | 39 |
| `biscuits-bakery` | 17 |
| `beverages` | 3 |
| All other departments | 0 |

Specific collisions and gaps confirmed from live rows:

1. `staples-pantry/rice` has 13 active SKUs; every product name is Basmati.
   A separate broad Rice rail therefore has zero existing non-Basmati SKUs.
2. `breakfast-spreads/spreads` has 14 active SKUs, while
   `masala-cooking/sauces-condiments` has 14. The single reference destination
   “Sauces and Spreads” must aggregate both paths without cloning products.
3. `snacks-munchies/papad-fryums` has two active Appalam SKUs but the
   reference places Papad & Fryums under Masalas. A pending local migration
   reparents that existing category; it is not live yet.
4. `staples-pantry/salt` has one active Tata Salt SKU but the reference places
   Salt under Masalas. A pending local migration reparents it; it is not live.
5. `staples-pantry/sugar-sweeteners` is the old Sugar & Sweeteners destination
   with zero active SKUs. A pending local migration reparents and renames it
   Sugar and Jaggery; it is not live.
6. `masala-cooking/blended-masalas` has 84 active SKUs. The reference calls
   this Ready Masala, but prepared meals must remain under Ready to Eat;
   the pending local migration moves two identified MTR meals out.
7. One Peanut Butter Bar is currently in `breakfast-spreads/spreads`; its
   product form suggests a snack. That individual SKU needs a deliberate
   classification decision during the SKU-by-SKU pass, not a name-based bulk
   move.

## Draft browse-map coverage checkpoint (2026-09-26)

A read-only comparison before deletion put 572 of 574 active SKUs in exactly
one first-level destination, none in two, and left two unmapped. The user then
requested those exact two Aachi Pani Puri Kit SKUs be deleted. Their IDs were
`5e968e4d-2812-4d3a-a10e-ec17d6a87905` and
`bc70f474-87e2-4618-9a9b-96b84799e660`. The linked database now reports
zero remaining target SKUs, two deletion audit events, and **572 active SKUs**.
Consequently, the same path-level projection has no unmapped SKU. This is not
proof that the draft migration has run on the live database or that all three
apps use the map.

The former exceptions were under `instant-ready-frozen-food/ready-to-cook`.
The same category also has five
flour-based mixes (adhirasam, bajji/bonda, murukku), now assigned to the
reference's Ready to Cook Flour Mix rail under Atta, Flour & Dal. The user
chose Rice for the three biryani kits; they are mapped to the broad Rice rail,
not Basmati Rice. The draft map must still pass its full database and
three-app verification before activation.

### Rail-by-rail pass (later on 2026-09-26)

The draft migration now has 71 explicit reference rails. After the user
approved placing Ching's Secret Shirataki Noodles under Instant Noodles and
the two Open Secret flavoured-nut SKUs under Nuts in Chips and Namkeens, a
path-level projection of the 572 current live SKUs onto the draft map,
including the pending Salt, Papad and Oil/Ghee reparenting, places **all 572
SKUs in exactly one first-level destination and one rail**, **zero in multiple
destinations or rails**, and leaves **zero without a destination or rail**.
This is a grouped-path projection, not an SKU-by-SKU production test or a
deployed change. The migration parses and applies in an isolated local
PostgreSQL database, but pgTAP is unavailable there and the full reconciliation
query requires populated SKU tables.

The Dairy, Tea, Oil/Ghee, Breakfast, Sauces/Spreads, Cold Drinks, Chips,
Biscuits and Sweet Corner rails now cover their unambiguous stocked paths.
High Protein Atta remains removed. The draft remains `DRAFT` until the
remaining empty reference rails, downstream app consumers, and full end-to-end
tests are resolved. The web customer, merchant and admin catalogue screens now
have a staged path that reads the active server browse map and matches SKUs by
its explicit source paths. The legacy browser remains in use while the map is
   `DRAFT`. The web build and targeted catalogue tests pass, but full
   UI-to-database verification and activation have not been completed; no live
   UI claim is justified yet.

### Native browse-map checkpoint (2026-09-27)

Customer, merchant and admin native catalogue views now have a staged path
that reads the same active browse map. Their shelves use explicit canonical
type/category/subcategory source paths and exclusions; customer and admin
paginate their SKU reads before presenting the mapped shelves. Invalid maps
fail closed rather than falling back to a similarly named category. While the
map is `DRAFT`, the existing navigation remains in use. The shared matcher
tests pass (2/2), the DastakUI package builds, and its existing suite passes
(81/81). This is local code verification, not a device UI test or proof that
the draft map is active in production. The live migration, cross-app end-to-end
checks, native app distribution and deployment remain outstanding.

## Implementation gate before deployment

1. Represent reference browse destinations and rails as versioned data with
   stable keys and explicit source paths. Support multiple source paths per
   destination (especially Sauces and Spreads) and exclusions (broad Rice vs
   Basmati and Poha). Keep SKU's one canonical classification.
2. Reconcile every one of the current 572 active SKU IDs against that map. Record
   deliberate zero-product destinations and any ambiguous SKU for review.
3. Make customer, merchant, admin and native catalogue navigation consume the
   same versioned map. Fail closed on a missing or ambiguous target; no fallback
   to a category with the same name in another department.
4. Test the UI-to-API-to-database-to-render path for Rice/Basmati/Poha,
   Sugar/Jaggery, Ready Masala, Salt, Papad, Sauces/Spreads and every home
   destination. Assert SKU IDs remain unique and merchant selections survive.
5. Only after those checks pass, apply migrations and deploy the affected
   apps together, then verify the live URLs/builds. This audit document alone
   does not satisfy that gate.
