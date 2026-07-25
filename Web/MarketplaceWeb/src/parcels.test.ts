import { describe, expect, it } from "vitest";
import { getCustomerParcels, mutateParcelAssignment, parseParcel, quoteParcel } from "./parcels";

const parcelId = "22222222-2222-4222-8222-222222222222";
const assignmentId = "33333333-3333-4333-8333-333333333333";
const parcel = {
  audience: "sender",
  parcelId,
  status: "assigned",
  paymentStatus: "paid",
  refundStatus: "not_requested",
  deliveryMethod: "bike",
  pickup: { latitude: 12.68, longitude: 78.62, address: "Pickup" },
  dropoff: { latitude: 12.69, longitude: 78.64, address: "Drop-off" },
  recipient: { name: "Asha", phoneNumber: "+919876543210" },
  declaredContents: "Documents",
  declaredValue: { currency: "INR", paise: 1000 },
  deliveryFee: { currency: "INR", paise: 3500 },
  courierPayout: { currency: "INR", paise: 3000 },
  handoffCode: { purpose: "pickup", code: "123456", expiresAt: "2026-07-23T00:00:00Z" },
};

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

describe("parcel delivery", () => {
  it("parses customer parcel snapshots", async () => {
    const fetcher = () => Promise.resolve(new Response(JSON.stringify([parcel]), { status: 200 }));
    await expect(getCustomerParcels(auth, fetcher)).resolves.toEqual([{ ...parseParcel(parcel), audience: "sender" }]);
  });

  it("keeps recipient parcels read-only and identifies their audience", async () => {
    const incoming = { ...parcel, audience: "recipient", handoffCode: { purpose: "delivery", code: "654321", expiresAt: "2026-07-23T00:00:00Z" } };
    const fetcher = () => Promise.resolve(new Response(JSON.stringify([incoming]), { status: 200 }));
    await expect(getCustomerParcels(auth, fetcher)).resolves.toEqual([{ ...parseParcel(incoming), audience: "recipient" }]);
  });

  it("uses server routing and pricing for quotes", async () => {
    let body: Record<string, unknown> | undefined;
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({
        quoteId: "44444444-4444-4444-8444-444444444444",
        deliveryMethod: "bike",
        routeDistanceMeters: 4250,
        routeDurationSeconds: 720,
        deliveryFee: { currency: "INR", paise: 5100 },
        courierPayout: { currency: "INR", paise: 4400 },
        expiresAt: "2026-07-22T12:00:00Z",
      }), { status: 200 }));
    };
    const result = await quoteParcel({
      ...auth,
      deliveryMethod: "bike",
      pickup: parcel.pickup,
      dropoff: parcel.dropoff,
      idempotencyKey: "quote-key",
    }, fetcher);
    expect(body).not.toHaveProperty("deliveryFeePaise");
    expect(result.deliveryFee.paise).toBe(5100);
  });

  it("sends six-digit handoff codes only to lifecycle actions", async () => {
    let body: unknown;
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({
        offer: null,
        currentJob: {
          assignmentId,
          assignmentStatus: "acknowledged",
          offeredAt: "2026-07-22T10:00:00Z",
          respondBy: "2026-07-22T10:01:00Z",
          acknowledgedAt: "2026-07-22T10:00:10Z",
          distanceMeters: 200,
          parcel,
        },
      }), { status: 200 }));
    };
    await mutateParcelAssignment({
      ...auth,
      operation: "confirmPickup",
      assignmentId,
      verificationCode: "123456",
      idempotencyKey: "pickup-key",
    }, fetcher);
    expect(body).toMatchObject({ operation: "confirmPickup", verificationCode: "123456" });
  });
});
