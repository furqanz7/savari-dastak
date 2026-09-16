import { formatPrice } from "./catalogue";

export type DetailProduct = {
  id: string; name: string; brand?: string; variant?: string; packSize: string;
  description?: string; imageKey?: string; galleryImageKeys: string[];
  price: number; listPrice: number; quantityValue?: number; quantityUnit?: string; packCount?: number;
  facts?: Array<[string, string | undefined]>;
};

export function productUnitPrice(product: DetailProduct): string | undefined {
  const { quantityValue: value, quantityUnit: unit, packCount = 1 } = product;
  if (!value || value <= 0 || packCount <= 0 || !unit) return undefined;
  const base = unit === "kg" || unit === "l" ? value * 1000 : value;
  if (!["kg", "g", "l", "ml"].includes(unit)) return undefined;
  return `${formatPrice(Math.round(product.price * 100 / (base * packCount)))}/100 ${unit === "kg" || unit === "g" ? "g" : "ml"}`;
}

function presentationName(product: DetailProduct) {
  return product.name.toLowerCase()
    .replace(product.packSize.toLowerCase(), " ")
    .replace(/\b(?:pack|pk)\s*of\s*\d+\b/g, " ")
    .replace(/\b\d+(?:\.\d+)?\s*(?:kg|g|mg|l|ml)\b/g, " ")
    .replace(/\b\d+(?:\.\d+)?\s*[x×]\s*\d+(?:\.\d+)?\s*(?:kg|g|mg|l|ml)?\b/g, " ")
    .replace(/\s+/g, " ").trim();
}

// A different flavour/brand is a related product, never an invented pack variant.
export function sameProductFamily(a: DetailProduct, b: DetailProduct) {
  return a.id === b.id || (Boolean(a.brand) && a.brand === b.brand && a.variant === b.variant && presentationName(a) === presentationName(b));
}

/** Stable presentation key for legitimate size/unit variants of one product. */
export function productFamilyKey(product: DetailProduct) {
  return [product.brand?.toLowerCase() ?? "", product.variant?.toLowerCase() ?? "", presentationName(product)].join("|");
}

/** Keep one visual card per product presentation while retaining every exact SKU for the detail picker. */
export function groupProductFamilies<T extends DetailProduct>(products: T[]) {
  const groups = new Map<string, T[]>();
  for (const product of products) {
    const key = productFamilyKey(product);
    const group = groups.get(key) ?? [];
    group.push(product);
    groups.set(key, group);
  }
  return [...groups.values()];
}

export function productSwipeStep(horizontal: number, vertical: number): number | undefined {
  if (Math.abs(horizontal) < 56 || Math.abs(horizontal) <= Math.abs(vertical) * 1.5) return undefined;
  return horizontal < 0 ? 1 : -1;
}

export function adjacentProductId(products: Array<{ id: string }>, currentId: string, step: number) {
  const index = products.findIndex((product) => product.id === currentId);
  return index < 0 ? undefined : products[index + step]?.id;
}

export function merchantStockAction({ text, currentQuantity, reserved = 0, selected, addingEmptySKU, stale, busy, active }: {
  text: string; currentQuantity?: number; reserved?: number; selected: boolean;
  addingEmptySKU: boolean; stale: boolean; busy: boolean; active: boolean;
}) {
  const quantity = Number(text);
  const valid = /^\d+$/.test(text) && Number.isSafeInteger(quantity) && quantity >= 0 && quantity <= Math.max(0, 1_000_000 - reserved);
  const stockMode = selected || addingEmptySKU;
  return {
    quantity, stockMode, title: stockMode ? "Save Stock" : "Add",
    canEdit: stockMode && active && !busy && !stale,
    canSubmit: active && !busy && !stale && (!stockMode || (valid && quantity !== currentQuantity && (!addingEmptySKU || quantity > 0))),
  };
}
export function productPickerPose(distance: number) {
  const depth = Math.min(2.5, Math.abs(distance));
  return { scale: 1 - Math.min(depth, 2) * .12, opacity: 1 - Math.min(depth, 2) * .25,
    rotation: distance * 9, drop: Math.min(42, depth * depth * 10) };
}
