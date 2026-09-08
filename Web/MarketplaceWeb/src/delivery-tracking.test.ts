import { describe, expect, it, vi } from "vitest";
import { advanceV1DeliveryMission, canArriveAtDestination, publishV1MissionLocation } from "./delivery";

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};
const missionId = "11111111-1111-4111-8111-111111111111";
const recordedAt = "2026-09-09T10:00:00Z";

describe("delivery tracking and ordered handoff", () => {
  it("expires arrival locally even if no further server response arrives", () => {
    const arrival = { eligible: true, reason: "ELIGIBLE", distanceMeters: 49,
      radiusMeters: 50, validUntil: "2026-09-09T10:00:30Z" };
    expect(canArriveAtDestination(arrival, Date.parse(recordedAt))).toBe(true);
    expect(canArriveAtDestination(arrival, Date.parse(arrival.validUntil))).toBe(false);
    expect(canArriveAtDestination({ ...arrival, eligible: false }, Date.parse(recordedAt))).toBe(false);
    expect(canArriveAtDestination(undefined)).toBe(false);
  });

  it("publishes mission-bound GPS without a caller-controlled actor", async () => {
    const fetcher = vi.fn(async () => Response.json({ currentMission: null, offer: null }));
    await publishV1MissionLocation({ ...auth, missionId, latitude: 12.68, longitude: 78.62,
      accuracyMeters: 5, recordedAt }, fetcher);
    const request = fetcher.mock.calls as unknown as Array<[unknown, RequestInit]>;
    expect(JSON.parse(String(request[0][1].body))).toEqual({
      operation: "v1PublishLocation", missionId, latitude: 12.68, longitude: 78.62,
      accuracyMeters: 5, recordedAt,
    });
  });

  it("rejects non-finite and excessively inaccurate GPS before network use", async () => {
    const fetcher = vi.fn();
    const input = { ...auth, missionId, latitude: 12.68, longitude: 78.62,
      accuracyMeters: 5, recordedAt };
    await expect(publishV1MissionLocation({ ...input, latitude: NaN }, fetcher)).rejects.toThrow();
    await expect(publishV1MissionLocation({ ...input, accuracyMeters: 201 }, fetcher)).rejects.toThrow();
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("separates six-digit PIN verification from completion", async () => {
    const bodies: unknown[] = [];
    const fetcher = async (_: RequestInfo | URL, init?: RequestInit) => {
      bodies.push(JSON.parse(String(init?.body)));
      return Response.json({ currentMission: null, offer: null });
    };
    await expect(advanceV1DeliveryMission({ ...auth, missionId,
      operation: "v1VerifyCustomerPIN", verificationCode: "12", idempotencyKey: "bad" },
    fetcher)).rejects.toThrow("six-digit");
    await advanceV1DeliveryMission({ ...auth, missionId, operation: "v1VerifyCustomerPIN",
      verificationCode: "123456", idempotencyKey: "pin" }, fetcher);
    await advanceV1DeliveryMission({ ...auth, missionId, operation: "v1CompleteDelivery",
      idempotencyKey: "complete" }, fetcher);
    expect(bodies).toEqual([
      { operation: "v1VerifyCustomerPIN", missionId, verificationCode: "123456" },
      { operation: "v1CompleteDelivery", missionId },
    ]);
  });
});
