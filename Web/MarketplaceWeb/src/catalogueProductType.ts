// Shared SKU metadata, separate from flavour/variant. Never infer from names.
export const PRODUCT_TYPE_MAX_LENGTH = 100;
export function validProductType(value: string): boolean {
  return value.trim().length <= PRODUCT_TYPE_MAX_LENGTH && !Array.from(value).some(character => {
    const code = character.charCodeAt(0);
    return code < 32 || code === 127;
  });
}
export function catalogueProductType(attributes: Record<string, unknown> | undefined): string | undefined {
  const value = attributes?.productType;
  return typeof value === "string" && validProductType(value) ? value.trim() || undefined : undefined;
}
export function withCatalogueProductType(attributes: Record<string, unknown>, value: string): Record<string, unknown> {
  if (!validProductType(value)) throw new Error("Product Type must be at most 100 characters and contain no control characters.");
  const result = { ...attributes };
  if (value.trim()) result.productType = value.trim();
  else delete result.productType;
  return result;
}
