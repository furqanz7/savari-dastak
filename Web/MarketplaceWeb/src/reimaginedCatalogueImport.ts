import { validateBrowseMap } from "./catalogueBrowse";
import { parseV1Catalogue, type V1CatalogueBrowseMap, type V1CatalogueBrowseSource } from "./dastakV1";
import type { ReimaginedCatalogue } from "./reimaginedCatalogue";

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Expected a catalogue snapshot object.");
  return value as Record<string, unknown>;
}
function text(value: unknown): string {
  if (typeof value !== "string" || !value.trim()) throw new Error("Invalid catalogue map field.");
  return value;
}
function optionalText(value: unknown) { return value === null ? null : text(value); }
function list(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new Error("Expected a catalogue list.");
  return value;
}

// Preview import expects { map: catalogueBrowseMap response, catalogue:
// customerCatalogue response }. It stays in memory and is never uploaded.
export function parseReimaginedCatalogueImport(value: unknown): ReimaginedCatalogue {
  const bundle = record(value);
  const rawMap = record(bundle.map);
  if (!Number.isSafeInteger(rawMap.version) || Number(rawMap.version) < 1) throw new Error("Invalid map version.");
  const map: V1CatalogueBrowseMap = { version: Number(rawMap.version), nodes: list(rawMap.nodes).map(value => {
    const node = record(value);
    if (node.kind !== "SECTION" && node.kind !== "DESTINATION" && node.kind !== "RAIL") throw new Error("Invalid map node kind.");
    if (!Number.isSafeInteger(node.sortOrder) || Number(node.sortOrder) < 0) throw new Error("Invalid map ordering.");
    return { key: text(node.key), label: text(node.label), parentKey: optionalText(node.parentKey), kind: node.kind, sortOrder: Number(node.sortOrder), sources: list(node.sources).map((value): V1CatalogueBrowseSource => {
      const source = record(value);
      return { typeSlug: text(source.typeSlug), categorySlug: optionalText(source.categorySlug), subcategorySlug: optionalText(source.subcategorySlug), excludedCategorySlugs: list(source.excludedCategorySlugs).map(text), excludedSubcategorySlugs: list(source.excludedSubcategorySlugs).map(text) };
    }) };
  }) };
  if (validateBrowseMap(map).length) throw new Error("The catalogue map has ambiguous or missing relationships.");
  const catalogue = parseV1Catalogue(bundle.catalogue);
  if (catalogue.nextCursor) throw new Error("This snapshot is incomplete. Import all catalogue pages together.");
  if (new Set(catalogue.skus.map(sku => sku.id)).size !== catalogue.skus.length) throw new Error("The snapshot contains duplicate SKU IDs.");
  return { map, catalogue };
}
