import { describe, expect, it } from "vitest";
import { getCustomerAddresses, saveDefaultCustomerAddress } from "./customerAddresses";

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

const address = {
  addressId: "11111111-1111-4111-8111-111111111111",
  label: "Home",
  address: "CL Road, Vaniyambadi",
  details: "12, first floor",
  displayAddress: "12, first floor, CL Road, Vaniyambadi",
  location: { latitude: 12.6819, longitude: 78.6201 },
  isDefault: true,
  updatedAt: "2026-08-13T10:00:00Z",
};

describe("customer delivery addresses", () => {
  it("loads the server-confirmed default address", async () => {
    const result = await getCustomerAddresses(auth, () =>
      Promise.resolve(new Response(JSON.stringify({ addresses: [address] }), { status: 200 })));
    expect(result.addresses[0]).toEqual(address);
  });

  it("saves normalized address details with idempotency", async () => {
    let body: unknown;
    let headers: Headers | undefined;
    const result = await saveDefaultCustomerAddress({
      ...auth,
      label: "Home",
      address: address.address,
      details: address.details,
      location: address.location,
      idempotencyKey: "address-key",
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      headers = new Headers(init?.headers);
      return Promise.resolve(new Response(JSON.stringify({ addresses: [address] }), { status: 200 }));
    });

    expect(headers?.get("x-idempotency-key")).toBe("address-key");
    expect(body).toEqual({
      operation: "saveDefault",
      label: "Home",
      address: address.address,
      details: address.details,
      location: address.location,
    });
    expect(result.addresses[0].displayAddress).toContain("CL Road");
  });
});
