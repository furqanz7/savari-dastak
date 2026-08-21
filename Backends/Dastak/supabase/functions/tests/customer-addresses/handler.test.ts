import { assertEquals } from "jsr:@std/assert@1";
import { handleCustomerAddresses } from "../../customer-addresses/handler.ts";

const accountId = "11111111-1111-4111-8111-111111111111";
type Dependencies = Parameters<typeof handleCustomerAddresses>[1];

Deno.test("customer address snapshot uses authenticated account", async () => {
  let received = "";
  const response = await handleCustomerAddresses(request({ operation: "snapshot" }), {
    authenticateBearer: async () => ({ accountId }),
    snapshot: async (value) => {
      received = value;
      return { responseBody: { addresses: [] }, responseStatus: 200 };
    },
    save: async () => ({ responseBody: {}, responseStatus: 200 }),
    setDefault: async () => ({ responseBody: {}, responseStatus: 200 }),
    deleteAddress: async () => ({ responseBody: {}, responseStatus: 200 }),
  });
  assertEquals(response.status, 200);
  assertEquals(received, accountId);
});

Deno.test("customer address save normalizes and forwards a digest", async () => {
  let received: Record<string, unknown> = {};
  const response = await handleCustomerAddresses(
    request({
      operation: "saveDefault",
      label: "  Home  ",
      address: "  Gandhi Road  ",
      details: "  Flat 2  ",
      location: { latitude: 12.6819, longitude: 78.6201 },
    }),
    {
      authenticateBearer: async () => ({ accountId }),
      snapshot: async () => ({ responseBody: {}, responseStatus: 200 }),
      save: async (input) => {
        received = input;
        return { responseBody: { addresses: [] }, responseStatus: 200 };
      },
      setDefault: async () => ({ responseBody: {}, responseStatus: 200 }),
      deleteAddress: async () => ({ responseBody: {}, responseStatus: 200 }),
    },
  );
  assertEquals(response.status, 200);
  assertEquals(received.accountId, accountId);
  assertEquals(received.label, "Home");
  assertEquals(received.address, "Gandhi Road");
  assertEquals(received.building, "Flat 2");
  assertEquals(typeof received.requestDigest, "string");
});

Deno.test("customer address save accepts structured doorstep instructions", async () => {
  let received: Record<string, unknown> = {};
  const response = await handleCustomerAddresses(
    request({
      operation: "save",
      label: "Work",
      address: "Gandhi Road",
      building: "Second floor, 18",
      floor: "Second floor",
      landmark: "Opposite the library",
      deliveryNotes: "Call from the gate",
      location: { latitude: 12.6819, longitude: 78.6201 },
      makeDefault: false,
    }),
    dependencies({
      save: async (input) => {
        received = input;
        return { responseBody: { addresses: [] }, responseStatus: 200 };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(received.floor, "Second floor");
  assertEquals(received.landmark, "Opposite the library");
  assertEquals(received.deliveryNotes, "Call from the gate");
  assertEquals(received.makeDefault, false);
});

Deno.test("customer address selection is scoped to the authenticated account", async () => {
  let received: Record<string, unknown> = {};
  const addressId = "22222222-2222-4222-8222-222222222222";
  const response = await handleCustomerAddresses(
    request({ operation: "setDefault", addressId }),
    dependencies({
      setDefault: async (input) => {
        received = input;
        return { responseBody: { addresses: [] }, responseStatus: 200 };
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(received.accountId, accountId);
  assertEquals(received.addressId, addressId);
});

Deno.test("customer address save rejects incomplete doorstep details", async () => {
  const response = await handleCustomerAddresses(
    request({
      operation: "saveDefault",
      label: "Home",
      address: "Gandhi Road",
      details: "",
      location: { latitude: 12.6819, longitude: 78.6201 },
    }),
    dependencies(),
  );
  assertEquals(response.status, 400);
});

function request(body: unknown) {
  return new Request("https://example.test/customer-addresses", {
    method: "POST",
    headers: {
      authorization: "Bearer token",
      "content-type": "application/json",
      "x-idempotency-key": "test-key",
    },
    body: JSON.stringify(body),
  });
}

function dependencies(overrides: Partial<Dependencies> = {}): Dependencies {
  return {
    authenticateBearer: async () => ({ accountId }),
    snapshot: async () => ({ responseBody: {}, responseStatus: 200 }),
    save: async () => ({ responseBody: {}, responseStatus: 200 }),
    setDefault: async () => ({ responseBody: {}, responseStatus: 200 }),
    deleteAddress: async () => ({ responseBody: {}, responseStatus: 200 }),
    ...overrides,
  };
}
