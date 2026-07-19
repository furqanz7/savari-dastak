import { assertEquals, assertRejects } from "jsr:@std/assert";
import { signRideQuote, verifyRideQuote } from "../../passenger-rides/quote-token.ts";

Deno.test("signed ride quote round trips and rejects tampering", async () => {
  const token = await signRideQuote(claims, secret);
  assertEquals(await verifyRideQuote(token, secret, 2_000_000_000), claims);

  const [payload, signature] = token.split(".");
  await assertRejects(() => verifyRideQuote(`${payload}x.${signature}`, secret, 2_000_000_000));
});

Deno.test("signed ride quote rejects expiration", async () => {
  const token = await signRideQuote(claims, secret);
  await assertRejects(() => verifyRideQuote(token, secret, claims.expiresAtEpochSeconds));
});

const secret = "test-secret-with-at-least-thirty-two-bytes";
const claims = {
  version: 1 as const,
  accountId: "22222222-2222-4222-8222-222222222222",
  pickup: { label: "Current location", latitude: 12.6819, longitude: 78.6201 },
  destination: {
    label: "Railway Station",
    address: "Station Road",
    latitude: 12.676,
    longitude: 78.616,
  },
  distanceMeters: 5_000,
  durationSeconds: 900,
  autoFarePaise: 8_000,
  bikeFarePaise: 5_000,
  expiresAtEpochSeconds: 2_000_000_300,
};
