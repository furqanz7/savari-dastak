# Janamaz and Tasbih catalogue replacement

The user requested replacing all former Pooja Store categories/subcategories with prayer essentials and removing every old product. Live preflight found nine categories, 31 subcategories, zero SKUs, zero merchant selections and zero order lines under the canonical `puja-festive` type. There were no old products to delete.

Migration `20261014224848_replace_pooja_catalogue_with_prayer_essentials.sql` retires the old type/categories/subcategories and clears their image references. A new ACTIVE `prayer-essentials` type contains nine categories and 30 subcategories:

| Section | Subcategories |
| --- | --- |
| Janamaz | Standard, Padded, Travel, Children's Janamaz |
| Tasbih | 33-Bead, 99-Bead, Digital Tasbih, Finger Counters |
| Ittar | Oud, Musk, Floral, Sandalwood Ittar, Ittar Gift Sets |
| Quran Stands | Wooden, Foldable, Adjustable Quran Stands |
| Salah Caps | Cotton, Crochet, Embroidered, Children's Salah Caps |
| Prayer Clothing | Prayer Dresses, Prayer Hijabs and Khimars, Children's Prayer Sets |
| Miswak | Natural Miswak, Miswak Holders |
| Qibla Compasses | Pocket, Digital Qibla Compasses |
| Prayer Accessories | Janamaz Bags, Tasbih Pouches, Prayer Gift Sets |

The existing destination key is retained for compatibility with installed clients, but its sole source is now `prayer-essentials`. Nine customer browse rails map to the nine new categories. New products, prices and merchant stock were not fabricated.

The migration was exercised against the linked database inside a transaction and rolled back. The dry run produced the expected nine groups and 30 subcategories. It was then applied in production through the one targeted SQL file, with its migration history entry recorded separately because an unrelated earlier migration-history mismatch prevents a normal blanket push. No unrelated migration was applied.

Post-application verification returned all nine customer browse rails and all 30 ACTIVE subcategories, zero ACTIVE old categories, zero ACTIVE old subcategories, zero old products, and `prayer-essentials` as the destination's sole source. Diff whitespace checks passed. These are live database checks; the screens themselves were not reverified during this change.

If a database replay contains old SKUs, the migration archives them and clears merchant selections before retiring their parent taxonomy, preserving historical order identities. The actual live environment contained zero such SKUs.

Related section choices were checked against retailers' own catalogues:
- https://www.alhannah.com/shop/
- https://www.alhannah.com/product-category/prayer-rugs/
- https://www.islamicplace.com/pages/popular-searches
- https://www.islamicplace.com/collections/for-home?page=6
