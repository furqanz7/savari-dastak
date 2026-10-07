import type { V1CatalogueBrowseMap, V1CatalogueBrowseNode } from "./dastakV1";

export type BrowseTaxonomy = {
  types: Array<{ id: string; slug: string }>;
  categories: Array<{ id: string; typeId: string; slug: string }>;
  subcategories: Array<{ id: string; categoryId: string; slug: string }>;
};

export function browseChildren(map: V1CatalogueBrowseMap, parentKey: string | null): V1CatalogueBrowseNode[] {
  return map.nodes.filter((node) => node.parentKey === parentKey)
    .sort((left, right) => left.sortOrder - right.sortOrder || left.key.localeCompare(right.key));
}

// Fail closed on malformed trees: an ambiguous browse path must never silently
// resolve to an unrelated canonical category or SKU.
export function validateBrowseMap(map: V1CatalogueBrowseMap): string[] {
  const issues: string[] = [];
  if (!map.nodes.length) issues.push("Browse map has no nodes");
  const nodes = new Map<string, V1CatalogueBrowseNode>();
  for (const node of map.nodes) {
    if (nodes.has(node.key)) issues.push(`Duplicate browse key: ${node.key}`);
    nodes.set(node.key, node);
  }
  for (const node of map.nodes) {
    const parent = node.parentKey === null ? undefined : nodes.get(node.parentKey);
    if (node.kind === "SECTION" && node.parentKey !== null) issues.push(`Section has parent: ${node.key}`);
    if (node.kind === "DESTINATION" && parent?.kind !== "SECTION") issues.push(`Destination has invalid parent: ${node.key}`);
    if (node.kind === "RAIL" && parent?.kind !== "DESTINATION") issues.push(`Rail has invalid parent: ${node.key}`);
    if (node.kind !== "RAIL" && node.parentKey !== null && !parent) issues.push(`Missing parent: ${node.key}`);
  }
  return issues;
}

export function browseSkuIds(
  map: V1CatalogueBrowseMap,
  nodeKey: string,
  taxonomy: BrowseTaxonomy,
  skus: Array<{ id: string; categoryId: string; subcategoryId: string }>,
): Set<string> {
  if (validateBrowseMap(map).length) return new Set();
  const node = map.nodes.find((item) => item.key === nodeKey);
  if (!node) return new Set();
  const types = new Map(taxonomy.types.map((item) => [item.id, item.slug]));
  const categories = new Map(taxonomy.categories.map((item) => [item.id, item]));
  const subcategories = new Map(taxonomy.subcategories.map((item) => [item.id, item]));
  return new Set(skus.flatMap((sku) => {
    const subcategory = subcategories.get(sku.subcategoryId);
    const category = categories.get(sku.categoryId);
    if (!subcategory || !category || subcategory.categoryId !== category.id) return [];
    const typeSlug = types.get(category.typeId);
    const match = node.sources.some((source) =>
      typeSlug === source.typeSlug &&
      (source.categorySlug === null || category.slug === source.categorySlug) &&
      (source.subcategorySlug === null || subcategory.slug === source.subcategorySlug) &&
      !source.excludedCategorySlugs.includes(category.slug) &&
      !source.excludedSubcategorySlugs.includes(subcategory.slug));
    return match ? [sku.id] : [];
  }));
}
