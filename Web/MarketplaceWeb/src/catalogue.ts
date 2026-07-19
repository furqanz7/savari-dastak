export type CatalogueLocation = { latitude: number; longitude: number };

export type CatalogueStore = {
  storeId: string;
  name: string;
  address: string;
  location: CatalogueLocation;
  serviceZoneId: string;
  isPublished: boolean;
  acceptingOrders: boolean;
};

export type CatalogueCategory = {
  categoryId: string;
  storeId: string;
  name: string;
  displayOrder: number;
  isActive: boolean;
};

export type CatalogueProduct = {
  productId: string;
  storeId: string;
  categoryId: string;
  name: string;
  description: string | null;
  unitLabel: string;
  price: { paise: number };
  imageObjectPath: string | null;
  availability: "in_stock" | "out_of_stock";
  catalogueKind: "general" | "otc_medicine" | "prescription_medicine" | "paan_corner";
  restrictedApprovalState: "not_applicable" | "pending" | "approved" | "rejected" | "suspended";
  isActive: boolean;
};

export type CatalogueSnapshot = {
  serviceZoneId: string | null;
  stores: CatalogueStore[];
  categories: CatalogueCategory[];
  products: CatalogueProduct[];
};

export type GroupedCatalogueStore = CatalogueStore & {
  categories: Array<CatalogueCategory & { products: CatalogueProduct[] }>;
};

export class CatalogueRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "CatalogueRequestError";
  }
}

type BrowseInput = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
  location: CatalogueLocation;
};

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const availabilityValues = new Set(["in_stock", "out_of_stock"]);
const catalogueKindValues = new Set(["general", "otc_medicine", "prescription_medicine", "paan_corner"]);
const approvalValues = new Set(["not_applicable", "pending", "approved", "rejected", "suspended"]);

export async function browseCatalogue(input: BrowseInput, fetcher: Fetcher = fetch) {
  if (!validLocation(input.location)) throw new CatalogueRequestError("invalid_location", "Choose a valid delivery location.", 400);

  let response: Response;
  try {
    response = await fetcher(`${input.supabaseUrl.replace(/\/$/, "")}/functions/v1/catalogue`, {
      method: "POST",
      headers: {
        apikey: input.publishableKey,
        authorization: `Bearer ${input.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ operation: "browse", location: input.location }),
    });
  } catch {
    throw new CatalogueRequestError("network_error", "Dastak could not reach the catalogue.", 0);
  }

  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    const code = text(error?.code, 80) ?? "catalogue_unavailable";
    const message = text(error?.message, 240) ?? "The catalogue is unavailable right now.";
    throw new CatalogueRequestError(code, message, response.status);
  }
  return parseCatalogueSnapshot(payload);
}

export function parseCatalogueSnapshot(value: unknown): CatalogueSnapshot {
  const source = record(value);
  if (!source || !Array.isArray(source.stores) || !Array.isArray(source.categories) || !Array.isArray(source.products)) invalid();

  const serviceZoneId = source.serviceZoneId === null ? null : uuid(source.serviceZoneId);
  if (serviceZoneId === undefined) invalid();

  return {
    serviceZoneId,
    stores: source.stores.map(parseStore),
    categories: source.categories.map(parseCategory),
    products: source.products.map(parseProduct),
  };
}

export function groupCatalogue(snapshot: CatalogueSnapshot): GroupedCatalogueStore[] {
  const stores = new Map(snapshot.stores.filter((store) => store.isPublished).map((store) => [store.storeId, store]));
  const categories = snapshot.categories
    .filter((category) => category.isActive && stores.has(category.storeId))
    .sort((left, right) => left.displayOrder - right.displayOrder || left.name.localeCompare(right.name));
  const products = snapshot.products.filter((product) => {
    const category = categories.find((candidate) => candidate.categoryId === product.categoryId);
    return product.isActive && product.catalogueKind === "general" &&
      product.restrictedApprovalState === "not_applicable" && category?.storeId === product.storeId;
  });

  return [...stores.values()]
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((store) => ({
      ...store,
      categories: categories.filter((category) => category.storeId === store.storeId).map((category) => ({
        ...category,
        products: products
          .filter((product) => product.categoryId === category.categoryId)
          .sort((left, right) => left.name.localeCompare(right.name)),
      })),
    }));
}

export function formatPrice(paise: number) {
  const hasPaise = paise % 100 !== 0;
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    minimumFractionDigits: hasPaise ? 2 : 0,
    maximumFractionDigits: hasPaise ? 2 : 0,
  }).format(paise / 100);
}

export function catalogueImageUrl(supabaseUrl: string, path: string | null) {
  if (!path) return null;
  const segments = path.split("/");
  if (segments.some((segment) => !segment || segment === "." || segment === ".." || segment.includes("\\"))) return null;
  return `${supabaseUrl.replace(/\/$/, "")}/storage/v1/object/public/dastak-catalogue/${segments.map(encodeURIComponent).join("/")}`;
}

function parseStore(value: unknown): CatalogueStore {
  const source = record(value);
  const location = record(source?.location);
  const latitude = number(location?.latitude);
  const longitude = number(location?.longitude);
  if (!source || latitude === undefined || longitude === undefined) invalid();
  const parsed = { latitude, longitude };
  if (!validLocation(parsed)) invalid();
  return {
    storeId: requiredUUID(source.storeId),
    name: requiredText(source.name, 120),
    address: requiredText(source.address, 300),
    location: parsed,
    serviceZoneId: requiredUUID(source.serviceZoneId),
    isPublished: requiredBoolean(source.isPublished),
    acceptingOrders: requiredBoolean(source.acceptingOrders),
  };
}

function parseCategory(value: unknown): CatalogueCategory {
  const source = record(value);
  if (!source) invalid();
  const displayOrder = number(source.displayOrder);
  if (displayOrder === undefined || !Number.isInteger(displayOrder) || displayOrder < 0) invalid();
  return {
    categoryId: requiredUUID(source.categoryId),
    storeId: requiredUUID(source.storeId),
    name: requiredText(source.name, 80),
    displayOrder,
    isActive: requiredBoolean(source.isActive),
  };
}

function parseProduct(value: unknown): CatalogueProduct {
  const source = record(value);
  const price = record(source?.price);
  if (!source || !price) invalid();
  const paise = number(price.paise);
  const availability = text(source.availability, 30);
  const catalogueKind = text(source.catalogueKind, 40);
  const approval = text(source.restrictedApprovalState, 40);
  if (paise === undefined || !Number.isInteger(paise) || paise < 1 || paise > 100_000_000 ||
    !availabilityValues.has(availability ?? "") ||
    !catalogueKindValues.has(catalogueKind ?? "") || !approvalValues.has(approval ?? "")) invalid();
  return {
    productId: requiredUUID(source.productId),
    storeId: requiredUUID(source.storeId),
    categoryId: requiredUUID(source.categoryId),
    name: requiredText(source.name, 160),
    description: nullableText(source.description, 1_000),
    unitLabel: requiredText(source.unitLabel, 40),
    price: { paise },
    imageObjectPath: nullableText(source.imageObjectPath, 500),
    availability: availability as CatalogueProduct["availability"],
    catalogueKind: catalogueKind as CatalogueProduct["catalogueKind"],
    restrictedApprovalState: approval as CatalogueProduct["restrictedApprovalState"],
    isActive: requiredBoolean(source.isActive),
  };
}

function validLocation(value: CatalogueLocation) {
  return Number.isFinite(value.latitude) && value.latitude >= -90 && value.latitude <= 90 &&
    Number.isFinite(value.longitude) && value.longitude >= -180 && value.longitude <= 180;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}

function text(value: unknown, maximumLength: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximumLength ? value : undefined;
}

function requiredText(value: unknown, maximumLength: number) {
  const result = text(value, maximumLength);
  if (result === undefined) invalid();
  return result;
}

function nullableText(value: unknown, maximumLength: number) {
  if (value === null) return null;
  return requiredText(value, maximumLength);
}

function uuid(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : undefined;
}

function requiredUUID(value: unknown) {
  const result = uuid(value);
  if (result === undefined) invalid();
  return result;
}

function number(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function requiredBoolean(value: unknown) {
  if (typeof value !== "boolean") invalid();
  return value;
}

function invalid(): never {
  throw new CatalogueRequestError("invalid_response", "Dastak received an invalid catalogue response.", 502);
}
