export type CustomerDeliveryAddress = {
  addressId: string;
  label: string;
  address: string;
  building: string;
  floor?: string;
  landmark?: string;
  deliveryNotes?: string;
  details: string;
  displayAddress: string;
  location: { latitude: number; longitude: number };
  isDefault: boolean;
  updatedAt: string;
};

export type CustomerDeliveryAddressCollection = { addresses: CustomerDeliveryAddress[] };

type AuthenticatedInput = { supabaseUrl: string; publishableKey: string; accessToken: string };
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class CustomerAddressRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "CustomerAddressRequestError";
  }
}

export async function getCustomerAddresses(input: AuthenticatedInput, fetcher: Fetcher = fetch) {
  return parseCollection(await call(input, { operation: "snapshot" }, undefined, fetcher));
}

export async function saveCustomerAddress(
  input: AuthenticatedInput & {
    addressId?: string;
    label: string;
    address: string;
    building: string;
    floor?: string;
    landmark?: string;
    deliveryNotes?: string;
    location: { latitude: number; longitude: number };
    makeDefault?: boolean;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return parseCollection(await call(input, {
    operation: "save",
    addressId: input.addressId,
    label: input.label,
    address: input.address,
    building: input.building,
    floor: input.floor,
    landmark: input.landmark,
    deliveryNotes: input.deliveryNotes,
    location: input.location,
    makeDefault: input.makeDefault ?? true,
  }, input.idempotencyKey, fetcher));
}

export async function setDefaultCustomerAddress(
  input: AuthenticatedInput & { addressId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseCollection(await call(input, {
    operation: "setDefault",
    addressId: input.addressId,
  }, input.idempotencyKey, fetcher));
}

export async function deleteCustomerAddress(
  input: AuthenticatedInput & { addressId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseCollection(await call(input, {
    operation: "delete",
    addressId: input.addressId,
  }, input.idempotencyKey, fetcher));
}

// Kept while older screens transition to the address-book contract.
export async function saveDefaultCustomerAddress(
  input: AuthenticatedInput & {
    label: string;
    address: string;
    details: string;
    location: { latitude: number; longitude: number };
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  const [building = input.details, ...remainder] = input.details.split(" • ");
  return saveCustomerAddress({
    ...input,
    building,
    landmark: remainder.join(" • ") || undefined,
    makeDefault: true,
  }, fetcher);
}

async function call(auth: AuthenticatedInput, body: unknown, idempotencyKey: string | undefined, fetcher: Fetcher) {
  let response: Response;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/customer-addresses`, {
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
    throw new CustomerAddressRequestError("network_error", "Dastak could not reach saved addresses.", 0);
  }
  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    throw new CustomerAddressRequestError(
      text(error?.code, 80) ?? "address_unavailable",
      text(error?.message, 300) ?? "The delivery address is unavailable right now.",
      response.status,
    );
  }
  return payload;
}

function parseCollection(value: unknown): CustomerDeliveryAddressCollection {
  const source = record(value);
  if (!source || !Array.isArray(source.addresses)) invalid();
  return { addresses: source.addresses.map(parseAddress) };
}

function parseAddress(value: unknown): CustomerDeliveryAddress {
  const source = record(value);
  const location = record(source?.location);
  if (!source || !location || typeof source.isDefault !== "boolean") invalid();
  const latitude = location.latitude;
  const longitude = location.longitude;
  if (typeof latitude !== "number" || !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    typeof longitude !== "number" || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) invalid();
  const updatedAt = requiredText(source.updatedAt, 50);
  if (Number.isNaN(Date.parse(updatedAt))) invalid();
  const details = requiredText(source.details, 700);
  const legacy = details.split(" • ");
  return {
    addressId: uuid(source.addressId),
    label: requiredText(source.label, 40),
    address: requiredText(source.address, 300),
    building: optional(source.building, 180) ?? legacy[0] ?? invalid(),
    floor: optional(source.floor, 80),
    landmark: optional(source.landmark, 110) ?? (legacy.slice(1).join(" • ") || undefined),
    deliveryNotes: optional(source.deliveryNotes, 240),
    details,
    displayAddress: requiredText(source.displayAddress, 1020),
    location: { latitude, longitude },
    isDefault: source.isDefault,
    updatedAt,
  };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
function text(value: unknown, maximum: number) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum ? value : undefined;
}
function optional(value: unknown, maximum: number) {
  return value === null || value === undefined ? undefined : text(value, maximum) ?? invalid();
}
function requiredText(value: unknown, maximum: number) { return text(value, maximum) ?? invalid(); }
function uuid(value: unknown) {
  if (typeof value !== "string" || !uuidPattern.test(value)) invalid();
  return value.toLowerCase();
}
function invalid(): never {
  throw new CustomerAddressRequestError("invalid_response", "Dastak received an invalid address response.", 502);
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
