export type CustomerWishlistItemKind = "RETAIL_SKU" | "MENU_ITEM";

export type CustomerWishlistItem = {
  kind: CustomerWishlistItemKind;
  itemId: string;
  createdAt: string;
};

export type CustomerWishlistSnapshot = { items: CustomerWishlistItem[] };

type AuthenticatedInput = { supabaseUrl: string; publishableKey: string; accessToken: string };
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class CustomerWishlistRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "CustomerWishlistRequestError";
  }
}

export async function getCustomerWishlist(input: AuthenticatedInput, fetcher: Fetcher = fetch) {
  return parseSnapshot(await call(input, { operation: "snapshot" }, undefined, fetcher));
}

export async function setCustomerWishlistItem(
  input: AuthenticatedInput & {
    itemKind: CustomerWishlistItemKind;
    itemId: string;
    wished: boolean;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return parseSnapshot(await call(input, {
    operation: "set",
    itemKind: input.itemKind,
    itemId: input.itemId,
    wished: input.wished,
  }, input.idempotencyKey, fetcher));
}

async function call(
  auth: AuthenticatedInput,
  body: unknown,
  idempotencyKey: string | undefined,
  fetcher: Fetcher,
) {
  let response: Response;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/customer-wishlist`, {
      method: "POST",
      headers: {
        apikey: auth.publishableKey,
        authorization: `Bearer ${auth.accessToken}`,
        "content-type": "application/json",
        ...(idempotencyKey ? { "x-idempotency-key": idempotencyKey } : {}),
      },
      body: JSON.stringify(body),
    });
  } catch {
    throw new CustomerWishlistRequestError("network_error", "Dastak could not reach your Wishlist.", 0);
  }
  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    throw new CustomerWishlistRequestError(
      text(error?.code, 80) ?? "wishlist_unavailable",
      text(error?.message, 300) ?? "Your Wishlist is unavailable right now.",
      response.status,
    );
  }
  return payload;
}

function parseSnapshot(value: unknown): CustomerWishlistSnapshot {
  const source = record(value);
  if (!source || !Array.isArray(source.items)) invalid();
  return { items: source.items.map(parseItem) };
}

function parseItem(value: unknown): CustomerWishlistItem {
  const source = record(value);
  if (!source || (source.kind !== "RETAIL_SKU" && source.kind !== "MENU_ITEM")) invalid();
  const createdAt = requiredText(source.createdAt, 50);
  if (Number.isNaN(Date.parse(createdAt))) invalid();
  return { kind: source.kind, itemId: uuid(source.itemId), createdAt };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}
function text(value: unknown, maximum: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum ? value : undefined;
}
function requiredText(value: unknown, maximum: number) { return text(value, maximum) ?? invalid(); }
function uuid(value: unknown) {
  if (typeof value !== "string" || !uuidPattern.test(value)) invalid();
  return value.toLowerCase();
}
function invalid(): never {
  throw new CustomerWishlistRequestError("invalid_response", "Dastak received an invalid Wishlist response.", 502);
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
