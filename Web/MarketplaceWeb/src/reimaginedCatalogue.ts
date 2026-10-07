import { browseChildren, browseSkuIds, validateBrowseMap } from "./catalogueBrowse";
import { getV1Catalogue, getV1CatalogueBrowseMap, type DastakV1Auth, type V1CatalogueBrowseMap, type V1CatalogueSku, type V1CatalogueSnapshot } from "./dastakV1";
import type { ReimaginedState, ReimaginedView } from "./reimaginedState";
import { productFamilyKey } from "./productDetail";

export type ReimaginedCatalogue = { map: V1CatalogueBrowseMap; catalogue: V1CatalogueSnapshot };
export type GroceryShelf = { key: string; label: string; skus: V1CatalogueSku[] };
export type GroceryQuickPick = { key: string; label: string; destinationKey: string };

// The current catalogue supplies variants, not a separate product-type taxonomy.
// Use those explicit values only: never classify a SKU by guessing from its name.
export function groceryProductTypes(skus: V1CatalogueSku[]): string[] {
  const types = [...new Set(skus.map(sku => sku.variant?.trim()).filter((value): value is string => Boolean(value)))];
  return types.length > 1 ? types : [];
}

export function filterGroceryShelf(shelf: GroceryShelf, selectedType?: string): GroceryShelf {
  if (!selectedType || !groceryProductTypes(shelf.skus).includes(selectedType)) return shelf;
  return { ...shelf, skus: shelf.skus.filter(sku => sku.variant?.trim() === selectedType) };
}

// Presentation only: every member remains an exact purchasable SKU. Do not
// guess families for unbranded products or across canonical category boundaries.
export function groupGroceryProducts(skus: V1CatalogueSku[]): V1CatalogueSku[][] {
  const groups = new Map<string, V1CatalogueSku[]>();
  for (const sku of skus) {
    const key = sku.brand?.name ? JSON.stringify([sku.categoryId, sku.subcategoryId, sku.brand.name, sku.variant ?? "",
      productFamilyKey({ ...sku, brand: sku.brand.name, price: sku.sellingPricePaise, listPrice: sku.listPricePaise })]) : sku.id;
    const group = groups.get(key) ?? [];
    if (!group.some(member => member.id === sku.id)) group.push(sku);
    groups.set(key, group);
  }
  return [...groups.values()];
}

export function grocerySubtotal(state: ReimaginedState, data?: ReimaginedCatalogue): number | undefined {
  if (!data) return undefined;
  const skus = new Map(data.catalogue.skus.map(sku => [sku.id, sku]));
  let total = 0;
  for (const [id, quantity] of Object.entries(state.shopping.retail)) {
    const sku = skus.get(id);
    if (!sku) return undefined;
    total += sku.sellingPricePaise * quantity;
  }
  return total;
}

function groceryTaxonomy({ catalogue }: ReimaginedCatalogue) {
  return {
    types: catalogue.categoryTypes,
    categories: catalogue.categories.flatMap(item => item.categoryTypeId ? [{ id: item.id, typeId: item.categoryTypeId, slug: item.slug }] : []),
    subcategories: catalogue.subcategories,
  };
}

// Discovery shortcuts reuse canonical rail identities; empty rails are omitted.
export function groceryQuickPicks(data: ReimaginedCatalogue): GroceryQuickPick[] {
  if (validateBrowseMap(data.map).length) return [];
  const taxonomy = groceryTaxonomy(data), picks: GroceryQuickPick[] = [];
  for (const section of browseChildren(data.map, null)) {
    for (const destination of browseChildren(data.map, section.key).filter(node => node.kind === "DESTINATION")) {
      for (const rail of browseChildren(data.map, destination.key).filter(node => node.kind === "RAIL")) {
        if (!browseSkuIds(data.map, rail.key, taxonomy, data.catalogue.skus).size) continue;
        picks.push({ key: rail.key, label: rail.label, destinationKey: destination.key });
        if (picks.length === 6) return picks;
      }
    }
  }
  return picks;
}

export function groceryShelves(data: ReimaginedCatalogue, view: ReimaginedView): GroceryShelf[] {
  const { map, catalogue } = data;
  if (validateBrowseMap(map).length) return [];
  const taxonomy = groceryTaxonomy(data);
  if (view.kind === "search") return [{ key: "search-results", label: `Results for “${view.query}”`, skus: searchGrocery(data, view.query) }];
  if (view.kind !== "home" && view.kind !== "browse") return [];
  const destination = view.kind === "browse" ? map.nodes.find(node => node.key === view.nodeKey && node.kind === "DESTINATION") : undefined;
  if (view.kind === "browse" && !destination) return [];
  if (view.kind === "browse" && view.railKey) {
    const rail = map.nodes.find(node => node.key === view.railKey && node.kind === "RAIL" && node.parentKey === destination?.key);
    if (!rail) return [];
    const ids = browseSkuIds(map, rail.key, taxonomy, catalogue.skus);
    return [{ key: rail.key, label: rail.label, skus: catalogue.skus.filter(sku => ids.has(sku.id)) }];
  }
  const nodes = destination ? browseChildren(map, destination.key).filter(node => node.kind === "RAIL") : browseChildren(map, null).flatMap(section => browseChildren(map, section.key).filter(node => node.kind === "DESTINATION"));
  // A destination without rails still resolves by its own canonical sources.
  return (destination && !nodes.length ? [destination] : nodes).map(node => {
    const ids = browseSkuIds(map, node.key, taxonomy, catalogue.skus);
    return { key: node.key, label: node.label, skus: catalogue.skus.filter(sku => ids.has(sku.id)) };
  });
}

export function searchGrocery({ catalogue }: ReimaginedCatalogue, query: string): V1CatalogueSku[] {
  const terms = query.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  if (!terms.length) return [];
  const categoryNames = new Map(catalogue.categories.map(item => [item.id, item.name]));
  const subcategoryNames = new Map(catalogue.subcategories.map(item => [item.id, item.name]));
  return catalogue.skus.filter(sku => {
    const text = [sku.name, sku.brand?.name, sku.packSize, sku.variant, categoryNames.get(sku.categoryId), subcategoryNames.get(sku.subcategoryId)].filter(Boolean).join(" ").toLocaleLowerCase();
    return terms.every(term => text.includes(term));
  });
}

// Read-only adapter over existing authenticated API contracts. Never treat page 1
// as a complete catalogue; fail visibly on cursor loops or version drift.
export async function loadReimaginedCatalogue(auth: DastakV1Auth, signal: AbortSignal, clients = { getV1Catalogue, getV1CatalogueBrowseMap }): Promise<ReimaginedCatalogue> {
  const mapRequest = clients.getV1CatalogueBrowseMap({ ...auth, signal });
  const firstRequest = clients.getV1Catalogue({ ...auth, signal, limit: 250 });
  const [map, first] = await Promise.all([mapRequest, firstRequest]);
  if (!map || validateBrowseMap(map).length) throw new Error("The store directory is unavailable. Try again.");
  const skus = new Map(first.skus.map(sku => [sku.id, sku]));
  const cursors = new Set<string>();
  let cursor = first.nextCursor;
  while (cursor) {
    if (signal.aborted) throw new DOMException("Catalogue request cancelled", "AbortError");
    const key = JSON.stringify(cursor);
    if (cursors.has(key) || cursors.size >= 100) throw new Error("The catalogue could not be loaded completely. Try again.");
    cursors.add(key);
    const page = await clients.getV1Catalogue({ ...auth, signal, limit: 250, cursor });
    if (first.catalogueVersion !== page.catalogueVersion) throw new Error("The catalogue changed while loading. Try again.");
    for (const sku of page.skus) skus.set(sku.id, sku);
    cursor = page.nextCursor;
  }
  if (signal.aborted) throw new DOMException("Catalogue request cancelled", "AbortError");
  return { map, catalogue: { ...first, skus: [...skus.values()], nextCursor: undefined } };
}
