import { describe, expect, it } from "vitest";
import {
  deleteCustomerAddress,
  getCustomerAddresses,
  saveCustomerAddress,
  setDefaultCustomerAddress,
} from "./customerAddresses";

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

const address = {
  addressId: "11111111-1111-4111-8111-111111111111",
  label: "Home",
  address: "CL Road, Vaniyambadi",
  building: "12",
  floor: "First floor",
  landmark: "Near the mosque",
  deliveryNotes: "Leave with security",
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

  it("saves structured doorstep details with idempotency", async () => {
    let body: unknown;
    let headers: Headers | undefined;
    const result = await saveCustomerAddress({
      ...auth,
      addressId: address.addressId,
      label: "Home",
      address: address.address,
      building: address.building,
      floor: address.floor,
      landmark: address.landmark,
      deliveryNotes: address.deliveryNotes,
      location: address.location,
      makeDefault: true,
      idempotencyKey: "address-key",
    }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      headers = new Headers(init?.headers);
      return Promise.resolve(new Response(JSON.stringify({ addresses: [address] }), { status: 200 }));
    });

    expect(headers?.get("x-idempotency-key")).toBe("address-key");
    expect(body).toEqual({
      operation: "save",
      addressId: address.addressId,
      label: "Home",
      address: address.address,
      building: "12",
      floor: "First floor",
      landmark: "Near the mosque",
      deliveryNotes: "Leave with security",
      location: address.location,
      makeDefault: true,
    });
    expect(result.addresses[0].displayAddress).toContain("CL Road");
  });

  it("selects and deletes an address by id", async () => {
    const operations: unknown[] = [];
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      operations.push(JSON.parse(String(init?.body)));
      return Promise.resolve(new Response(JSON.stringify({ addresses: [address] }), { status: 200 }));
    };

    await setDefaultCustomerAddress({ ...auth, addressId: address.addressId, idempotencyKey: "default-key" }, fetcher);
    await deleteCustomerAddress({ ...auth, addressId: address.addressId, idempotencyKey: "delete-key" }, fetcher);

    expect(operations).toEqual([
      { operation: "setDefault", addressId: address.addressId },
      { operation: "delete", addressId: address.addressId },
    ]);
  });
});
