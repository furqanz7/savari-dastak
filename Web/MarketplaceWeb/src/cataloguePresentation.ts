// Customer-facing names are presentation metadata. Canonical slugs and IDs
// remain unchanged so SKU identity, merchant selections, and history are stable.
const departmentNames: Record<string, string> = {
  "staples-pantry": "Atta, Flour & Dal",
  "masala-cooking": "Masalas",
};

export const CATALOGUE_NAVIGATION_VERSION = 1;

export type CatalogueRailTarget = {
  label: string;
  typeSlug: string;
  categorySlug: string;
  subcategorySlug?: string;
};

// Explicit parent paths are essential: slugs such as "rice" and display names
// can occur in more than one branch of the canonical taxonomy.
export const curatedCatalogueRails: Record<string, readonly CatalogueRailTarget[]> = {
  "staples-pantry": [
    { label: "Atta", typeSlug: "staples-pantry", categorySlug: "atta-flours" },
    { label: "Rice", typeSlug: "staples-pantry", categorySlug: "rice" },
    { label: "Toor, Moong and Urad", typeSlug: "staples-pantry", categorySlug: "dals-pulses" },
    { label: "Basmati Rice", typeSlug: "staples-pantry", categorySlug: "rice", subcategorySlug: "basmati-rice" },
    { label: "Besan, Sooji and Maida", typeSlug: "staples-pantry", categorySlug: "atta-flours", subcategorySlug: "besan-sooji-maida" },
    { label: "Rajma, Chola and Others", typeSlug: "staples-pantry", categorySlug: "dals-pulses", subcategorySlug: "rajma-chola-others" },
    { label: "Poha & Puffed Rice", typeSlug: "staples-pantry", categorySlug: "rice", subcategorySlug: "poha-puffed-rice" },
    { label: "Premium Brands", typeSlug: "staples-pantry", categorySlug: "atta-flours", subcategorySlug: "premium-brands" },
    { label: "Soya Chunk & Badi", typeSlug: "staples-pantry", categorySlug: "dals-pulses", subcategorySlug: "soya-chunk-badi" },
    { label: "Other Flours", typeSlug: "staples-pantry", categorySlug: "atta-flours", subcategorySlug: "other-flours" },
    { label: "Millets & Daliya", typeSlug: "staples-pantry", categorySlug: "millets-grains", subcategorySlug: "millets-daliya" },
    { label: "Ready to Cook Flour Mix", typeSlug: "staples-pantry", categorySlug: "atta-flours", subcategorySlug: "ready-to-cook-flour-mix" },
  ],
  "masala-cooking": [
    { label: "Powdered Spices", typeSlug: "masala-cooking", categorySlug: "powdered-spices" },
    { label: "Whole Spices", typeSlug: "masala-cooking", categorySlug: "whole-spices" },
    { label: "Cold Grind", typeSlug: "masala-cooking", categorySlug: "cold-grind" },
    { label: "Sugar and Jaggery", typeSlug: "masala-cooking", categorySlug: "sugar-sweeteners" },
    { label: "Papad & Fryums", typeSlug: "masala-cooking", categorySlug: "papad-fryums" },
    { label: "Ready Masala", typeSlug: "masala-cooking", categorySlug: "blended-masalas" },
    { label: "Salt", typeSlug: "masala-cooking", categorySlug: "salt" },
    { label: "Paste and Puree", typeSlug: "masala-cooking", categorySlug: "cooking-pastes" },
    { label: "Pickles & Chutney", typeSlug: "masala-cooking", categorySlug: "pickles-chutneys" },
    { label: "Herbs & Seasoning", typeSlug: "masala-cooking", categorySlug: "herbs-seasoning" },
    { label: "Coconut Milk & Powder", typeSlug: "masala-cooking", categorySlug: "coconut-products" },
  ],
};

export function resolveCatalogueRail<T extends { id: string; slug: string }, C extends { id: string; categoryTypeId?: string; slug: string }, S extends { id: string; categoryId: string; slug: string }>(
  target: CatalogueRailTarget,
  types: T[],
  categories: C[],
  subcategories: S[],
): C | S | undefined {
  const matchingTypes = types.filter((item) => item.slug === target.typeSlug);
  if (matchingTypes.length !== 1) return undefined;
  const matchingCategories = categories.filter((item) => item.categoryTypeId === matchingTypes[0].id && item.slug === target.categorySlug);
  if (matchingCategories.length !== 1) return undefined;
  if (!target.subcategorySlug) return matchingCategories[0];
  const matchingSubcategories = subcategories.filter((item) => item.categoryId === matchingCategories[0].id && item.slug === target.subcategorySlug);
  return matchingSubcategories.length === 1 ? matchingSubcategories[0] : undefined;
}

export function validateCatalogueRails<T extends { id: string; slug: string }, C extends { id: string; categoryTypeId?: string; slug: string }, S extends { id: string; categoryId: string; slug: string }>(
  types: T[], categories: C[], subcategories: S[],
): string[] {
  return Object.entries(curatedCatalogueRails).flatMap(([displayParent, targets]) => targets
    .filter((target) => !resolveCatalogueRail(target, types, categories, subcategories))
    .map((target) => `${displayParent}: ${target.label} has a missing or ambiguous canonical target`));
}

export function catalogueDepartmentName(slug: string, canonicalName: string): string {
  return departmentNames[slug] ?? canonicalName;
}

// A broad rail should not duplicate products already placed in its dedicated
// child rails. This does not change canonical SKU classification.
export function riceRailExcludedSubcategoryIds(
  riceSubcategories: Array<{ id: string; slug: string }>,
): Set<string> {
  return new Set(riceSubcategories
    .filter((item) => item.slug === "basmati-rice" || item.slug === "poha-puffed-rice")
    .map((item) => item.id));
}

export function catalogueNavigationGroups<T extends {
  slug: string;
  name: string;
  sortOrder: number;
  navigationSection?: { key: string; name: string; sortOrder: number };
}>(categoryTypes: T[]) {
  const groups = new Map<string, {
    key: string;
    name: string;
    sortOrder: number;
    types: T[];
  }>();
  for (const type of categoryTypes) {
    const section = type.navigationSection ?? { key: "more", name: "More to explore", sortOrder: 999 };
    const group = groups.get(section.key) ?? { ...section, types: [] };
    group.types.push(type);
    groups.set(section.key, group);
  }
  return [...groups.values()]
    .map((group) => ({ ...group, types: [...group.types].sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name)) }))
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
}

export type CatalogueHomeTile<T, C> = {
  key: string;
  label: string;
  typeId: string;
  categoryId?: string;
  item: T | C;
};

export function catalogueHomeTiles<
  T extends { id: string; slug: string; name: string },
  C extends { id: string; categoryTypeId?: string; slug: string; name: string },
>(groupKey: string, groupTypes: T[], allTypes: T[], categories: C[]): Array<CatalogueHomeTile<T, C>> {
  const type = (slug: string, label?: string): CatalogueHomeTile<T, C> | undefined => {
    const item = allTypes.find((candidate) => candidate.slug === slug);
    return item && { key: `type:${slug}`, label: label ?? catalogueDepartmentName(slug, item.name), typeId: item.id, item };
  };
  const category = (typeSlug: string, categorySlug: string, label?: string): CatalogueHomeTile<T, C> | undefined => {
    const parent = allTypes.find((candidate) => candidate.slug === typeSlug);
    const item = parent && categories.find((candidate) => candidate.categoryTypeId === parent.id && candidate.slug === categorySlug);
    return parent && item && { key: `category:${typeSlug}/${categorySlug}`, label: label ?? item.name, typeId: parent.id, categoryId: item.id, item };
  };
  if (groupKey === "fresh-items") return [
    category("fresh-produce", "fresh-vegetables", "Fresh Vegetables"),
    category("fresh-produce", "fresh-fruits", "Fresh Fruits"),
    type("dairy-bread-eggs", "Dairy, Bread & Eggs"),
    category("fresh-produce", "fresh-meat-seafood", "Meat and Seafood"),
  ].filter((item): item is CatalogueHomeTile<T, C> => Boolean(item));
  if (groupKey === "grocery-kitchen") return [
    type("staples-pantry", "Atta, Flour & Dal"),
    type("masala-cooking", "Masalas"),
    type("oils-ghee", "Oils and Ghee"),
    type("breakfast-spreads", "Cereals and Breakfast"),
  ].filter((item): item is CatalogueHomeTile<T, C> => Boolean(item));
  return groupTypes.filter((item) => !(groupKey === "snacks-drinks" && item.slug === "breakfast-spreads"))
    .map((item) => ({ key: `type:${item.slug}`, label: catalogueDepartmentName(item.slug, item.name), typeId: item.id, item }));
}
