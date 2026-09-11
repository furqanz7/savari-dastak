// @vitest-environment node
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const serviceWorker = readFileSync(new URL("../public/dastak-sw.js", import.meta.url), "utf8");

describe("Delivery notification service-worker routes", () => {
  it("routes rider offers, assigned missions and returns without changing customer routes", () => {
    expect(serviceWorker).toContain('data.notificationType.startsWith("rider.")');
    expect(serviceWorker).toContain('data.eventType === "RIDER_POOL_OPENED"');
    expect(serviceWorker).toContain('data.eventType === "RETURN_RIDER_ASSIGNED"');
    expect(serviceWorker).toContain('typeof data.returnMissionId === "string"');
    expect(serviceWorker).toContain('typeof data.missionId === "string"');
    expect(serviceWorker).toContain('data.entityType === "parcel" ? "parcel"');
    expect(serviceWorker).toContain('"v1-orders"');
  });
});
