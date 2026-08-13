import { assertEquals } from "jsr:@std/assert@1";
import { handleCustomerAddresses } from "../../customer-addresses/handler.ts";

const accountId = "11111111-1111-4111-8111-111111111111";

Deno.test("customer address snapshot uses authenticated account", async () => {
  let received = "";
  const response = await handleCustomerAddresses(request({ operation: "snapshot" }), {
    authenticateBearer: async () => ({ accountId }),
    snapshot: async (value) => {
      received = value;
      return { responseBody: { addresses: [] }, responseStatus: 200 };
    },
    saveDefault: async () => ({ responseBody: {}, responseStatus: 200 }),
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
      saveDefault: async (input) => {
        received = input;
        return { responseBody: { addresses: [] }, responseStatus: 200 };
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(received.accountId, accountId);
  assertEquals(received.label, "Home");
  assertEquals(received.address, "Gandhi Road");
  assertEquals(typeof received.requestDigest, "string");
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

function dependencies() {
  return {
    authenticateBearer: async () => ({ accountId }),
    snapshot: async () => ({ responseBody: {}, responseStatus: 200 }),
    saveDefault: async () => ({ responseBody: {}, responseStatus: 200 }),
  };
}
