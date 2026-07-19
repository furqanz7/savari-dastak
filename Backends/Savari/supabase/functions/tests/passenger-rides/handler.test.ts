import { assert, assertEquals } from "jsr:@std/assert";
import {
  calculateFarePaise,
  handlePassengerRides,
  MapsUnavailableError,
  type PassengerRideDependencies,
  type RideCreateInput,
  type RideQuoteClaims,
} from "../../passenger-rides/handler.ts";

Deno.test("passenger rides accept browser preflight without authentication", async () => {
  let authenticationAttempts = 0;
  const response = await handlePassengerRides(
    new Request("http://localhost/functions/v1/passenger-rides", { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
});

Deno.test("passenger rides require authentication before validation", async () => {
  const response = await handlePassengerRides(
    request({ operation: "unsupported" }),
    dependencies(),
  );

  assertEquals(response.status, 401);
  assertEquals((await body(response)).error.code, "authentication_required");
});

Deno.test("destination search uses the authenticated location and filters outside results", async () => {
  let recorded: unknown;
  const response = await handlePassengerRides(
    request({
      operation: "searchDestination",
      query: "railway station",
      userLocation: pickup,
      accountId: otherAccountId,
    }, "Bearer session"),
    dependencies({
      searchPlaces: (input) => {
        recorded = input;
        return Promise.resolve([
          destination,
          { ...destination, label: "Outside", latitude: 13.2, longitude: 79.2 },
        ]);
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded, {
    query: "railway station",
    userLocation: { latitude: pickup.latitude, longitude: pickup.longitude },
  });
  assertEquals((await body(response)).results, [destination]);
});

Deno.test("maps failures return a safe diagnostic reference", async () => {
  const response = await handlePassengerRides(
    request({
      operation: "searchDestination",
      query: "railway station",
      userLocation: pickup,
    }, "Bearer session"),
    dependencies({
      searchPlaces: () => Promise.reject(new MapsUnavailableError("token-http-401")),
    }),
  );

  assertEquals(response.status, 503);
  assertEquals((await body(response)).error, {
    code: "maps_unavailable",
    message: "Map search or routing is temporarily unavailable.",
    reference: "token-http-401",
  });
});

Deno.test("quote uses server route and rate cards instead of client fare", async () => {
  let signed: RideQuoteClaims | undefined;
  const response = await handlePassengerRides(
    request({
      operation: "quote",
      pickup,
      destination,
      distanceMeters: 1,
      farePaise: 1,
    }, "Bearer session"),
    dependencies({
      routeRide: () => Promise.resolve({ distanceMeters: 5_000, durationSeconds: 900 }),
      signQuote: (claims) => {
        signed = claims;
        return Promise.resolve(signedQuoteToken);
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(signed?.accountId, accountId);
  assertEquals(signed?.distanceMeters, 5_000);
  assertEquals(signed?.autoFarePaise, 8_000);
  assertEquals(signed?.bikeFarePaise, 5_000);
  assertEquals((await body(response)).quoteToken, signedQuoteToken);
});

Deno.test("ride request consumes an own signed quote and server fare", async () => {
  let created: RideCreateInput | undefined;
  const response = await handlePassengerRides(
    request(
      { operation: "requestRide", quoteToken: signedQuoteToken, vehicleType: "auto", farePaise: 1 },
      "Bearer session",
      rideId,
    ),
    dependencies({
      verifyQuote: () => Promise.resolve(quoteClaims),
      createRide: (input) => {
        created = input;
        return Promise.resolve({ responseBody: rideSnapshot, responseStatus: 201 });
      },
    }),
  );

  assertEquals(response.status, 201);
  assertEquals(created?.rideId, rideId);
  assertEquals(created?.accountId, accountId);
  assertEquals(created?.vehicleType, "Auto");
  assertEquals(created?.farePaise, 8_000);
  assertEquals(created?.distanceMeters, 5_000);
});

Deno.test("ride request rejects a quote issued to another account", async () => {
  let calls = 0;
  const response = await handlePassengerRides(
    request(
      { operation: "requestRide", quoteToken: signedQuoteToken, vehicleType: "bike" },
      "Bearer session",
      rideId,
    ),
    dependencies({
      verifyQuote: () => Promise.resolve({ ...quoteClaims, accountId: otherAccountId }),
      createRide: () => {
        calls += 1;
        return Promise.resolve({ responseBody: {}, responseStatus: 201 });
      },
    }),
  );

  assertEquals(calls, 0);
  assertEquals(response.status, 403);
  assertEquals((await body(response)).error.code, "access_denied");
});

Deno.test("snapshot and cancellation derive passenger identity from bearer auth", async () => {
  let snapshotAccount: string | undefined;
  let cancelledAccount: string | undefined;
  const snapshotResponse = await handlePassengerRides(
    request({ operation: "snapshot", accountId: otherAccountId }, "Bearer session"),
    dependencies({
      getRideSnapshot: (input) => {
        snapshotAccount = input.accountId;
        return Promise.resolve({ responseBody: { ride: rideSnapshot }, responseStatus: 200 });
      },
    }),
  );
  const cancelResponse = await handlePassengerRides(
    request(
      { operation: "cancelRide", rideId, reason: "  Plans   changed  ", accountId: otherAccountId },
      "Bearer session",
      cancellationId,
    ),
    dependencies({
      cancelRide: (input) => {
        cancelledAccount = input.accountId;
        assertEquals(input.reason, "Plans changed");
        return Promise.resolve({ responseBody: rideSnapshot, responseStatus: 200 });
      },
    }),
  );

  assertEquals(snapshotResponse.status, 200);
  assertEquals(cancelResponse.status, 200);
  assertEquals(snapshotAccount, accountId);
  assertEquals(cancelledAccount, accountId);
});

Deno.test("fare calculation preserves minimum and uses distance only", () => {
  assertEquals(
    calculateFarePaise(500, {
      minimumFarePaise: 5_000,
      baseFarePaise: 2_000,
      perKilometrePaise: 1_200,
    }),
    5_000,
  );
  assertEquals(
    calculateFarePaise(5_000, {
      minimumFarePaise: 5_000,
      baseFarePaise: 2_000,
      perKilometrePaise: 1_200,
    }),
    8_000,
  );
});

const accountId = "22222222-2222-4222-8222-222222222222";
const otherAccountId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const rideId = "33333333-3333-4333-8333-333333333333";
const cancellationId = "44444444-4444-4444-8444-444444444444";
const signedQuoteToken = "signed-quote-token-for-testing";
const pickup = { label: "Current location", latitude: 12.6819, longitude: 78.6201 };
const destination = {
  label: "Vaniyambadi Railway Station",
  address: "Railway Station Road",
  latitude: 12.676,
  longitude: 78.616,
};
const quoteClaims: RideQuoteClaims = {
  version: 1,
  accountId,
  pickup,
  destination,
  distanceMeters: 5_000,
  durationSeconds: 900,
  autoFarePaise: 8_000,
  bikeFarePaise: 5_000,
  expiresAtEpochSeconds: 2_000_000_300,
};
const rideSnapshot = { rideId, status: "requested", vehicleType: "Auto" };

function dependencies(
  overrides: Partial<PassengerRideDependencies> = {},
): PassengerRideDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ?? (() => Promise.resolve({ accountId })),
    searchPlaces: overrides.searchPlaces ?? (() => Promise.resolve([destination])),
    routeRide: overrides.routeRide ??
      (() => Promise.resolve({ distanceMeters: 5_000, durationSeconds: 900 })),
    signQuote: overrides.signQuote ?? (() => Promise.resolve(signedQuoteToken)),
    verifyQuote: overrides.verifyQuote ?? (() => Promise.resolve(quoteClaims)),
    createRide: overrides.createRide ??
      (() => Promise.resolve({ responseBody: rideSnapshot, responseStatus: 201 })),
    getRideSnapshot: overrides.getRideSnapshot ??
      (() => Promise.resolve({ responseBody: { ride: rideSnapshot }, responseStatus: 200 })),
    cancelRide: overrides.cancelRide ??
      (() => Promise.resolve({ responseBody: rideSnapshot, responseStatus: 200 })),
    now: overrides.now ?? (() => new Date("2033-05-18T03:33:20.000Z")),
    serviceArea: overrides.serviceArea ??
      { center: { latitude: 12.6819, longitude: 78.6201 }, radiusMeters: 12_000 },
    rateCards: overrides.rateCards ?? {
      auto: { minimumFarePaise: 5_000, baseFarePaise: 2_000, perKilometrePaise: 1_200 },
      bike: { minimumFarePaise: 3_000, baseFarePaise: 1_000, perKilometrePaise: 800 },
    },
  };
}

function request(bodyValue: unknown, authorization?: string, idempotencyKey?: string) {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request("http://localhost/functions/v1/passenger-rides", {
    method: "POST",
    headers,
    body: JSON.stringify(bodyValue),
  });
}

async function body(response: Response) {
  return await response.json();
}
