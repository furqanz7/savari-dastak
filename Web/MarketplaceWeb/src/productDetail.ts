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

// A different flavour/brand is a related product, never an invented pack variant.
export function sameProductFamily(a: DetailProduct, b: DetailProduct) {
  const name = (p: DetailProduct) => p.name.toLowerCase().replace(p.packSize.toLowerCase(), "").replace(/\s+/g, " ").trim();
  return a.id === b.id || (Boolean(a.brand) && a.brand === b.brand && a.variant === b.variant && name(a) === name(b));
}
