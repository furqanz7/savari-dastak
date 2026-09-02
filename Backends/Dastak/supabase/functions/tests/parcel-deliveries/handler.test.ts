import { assertEquals } from "jsr:@std/assert";
import {
  handleParcelDeliveries,
  type ParcelDeliveryDependencies,
} from "../../parcel-deliveries/handler.ts";

const accountId = "11111111-1111-4111-8111-111111111111";
const parcelId = "22222222-2222-4222-8222-222222222222";
const quoteId = "33333333-3333-4333-8333-333333333333";
const assignmentId = "44444444-4444-4444-8444-444444444444";

Deno.test("parcel delivery authenticates before validating the operation", async () => {
  let authenticated = false;
  const response = await handleParcelDeliveries(
    request({ authorization: "Bearer invalid", body: {} }),
    dependencies({
      authenticateBearer: () => {
        authenticated = true;
        return Promise.reject(new Error("invalid"));
      },
    }),
  );

  assertEquals(authenticated, true);
  await assertError(response, 401, "authentication_required");
});

Deno.test("quote uses the server route and ignores client-owned pricing", async () => {
  let routed: Record<string, unknown> | undefined;
  let quoted: Record<string, unknown> | undefined;
  const response = await handleParcelDeliveries(
    request({
      body: {
        operation: "quote",
        deliveryMethod: "bike",
        pickup: { latitude: 12.68, longitude: 78.62, address: "1 Pickup Road" },
        dropoff: { latitude: 12.69, longitude: 78.64, address: "2 Drop Road" },
        routeDistanceMeters: 1,
        deliveryFeePaise: 1,
        courierPayoutPaise: 1,
        accountId: parcelId,
      },
    }),
    dependencies({
      routeParcel: (input) => {
        routed = input;
        return Promise.resolve({ distanceMeters: 4_250, durationSeconds: 720 });
      },
      quoteParcel: (input) => {
        quoted = input;
        return Promise.resolve({ responseBody: quote(), responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(routed?.deliveryMethod, "bike");
  assertEquals("address" in ((routed?.pickup ?? {}) as Record<string, unknown>), false);
  assertEquals(quoted?.accountId, accountId);
  assertEquals(quoted?.routeDistanceMeters, 4_250);
  assertEquals(quoted?.routeDurationSeconds, 720);
  assertEquals("deliveryFeePaise" in (quoted ?? {}), false);
  assertEquals("courierPayoutPaise" in (quoted ?? {}), false);
});

Deno.test("retired walking and bicycle parcel methods are rejected", async () => {
  for (const deliveryMethod of ["walking", "bicycle"]) {
    let routeCalled = false;
    const response = await handleParcelDeliveries(
      request({
        body: {
          operation: "quote",
          deliveryMethod,
          pickup: { latitude: 12.68, longitude: 78.62, address: "1 Pickup Road" },
          dropoff: { latitude: 12.69, longitude: 78.64, address: "2 Drop Road" },
        },
      }),
      dependencies({
        routeParcel: () => {
          routeCalled = true;
          return Promise.resolve({ distanceMeters: 4_250, durationSeconds: 720 });
        },
      }),
    );

    assertEquals(routeCalled, false);
    await assertError(response, 400, "validation_failed");
  }
});

Deno.test("create parcel forwards only customer intent", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleParcelDeliveries(
    request({
      body: {
        operation: "createParcel",
        quoteId,
        recipientName: "  Asha   Khan  ",
        recipientPhoneNumber: "+919876543210",
        declaredContents: "  Sealed   documents  ",
        declaredValuePaise: 2_500,
        paymentStatus: "paid",
        status: "delivered",
        deliveryFeePaise: 1,
      },
    }),
    dependencies({
      createParcel: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: parcel(), responseStatus: 201 });
      },
    }),
  );

  assertEquals(response.status, 201);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.quoteId, quoteId);
  assertEquals(recorded?.recipientName, "Asha Khan");
  assertEquals(recorded?.declaredContents, "Sealed documents");
  assertEquals("paymentStatus" in (recorded ?? {}), false);
  assertEquals("status" in (recorded ?? {}), false);
  assertEquals("deliveryFeePaise" in (recorded ?? {}), false);
});

Deno.test("snapshots derive customer, recipient, and partner identity from bearer auth", async () => {
  const recorded: Array<[string, string, string?]> = [];
  const deps = dependencies({
    getParcelSnapshot: (actor, requestedParcelId) => {
      recorded.push(["parcel", actor, requestedParcelId]);
      return Promise.resolve({ responseBody: parcel(), responseStatus: 200 });
    },
    getPartnerSnapshot: (actor) => {
      recorded.push(["partner", actor]);
      return Promise.resolve({ responseBody: partnerSnapshot(), responseStatus: 200 });
    },
    getCustomerSnapshot: (actor) => {
      recorded.push(["customer", actor]);
      return Promise.resolve({ responseBody: [parcel()], responseStatus: 200 });
    },
  });

  assertEquals(
    (await handleParcelDeliveries(
      request({ body: { operation: "parcelSnapshot", parcelId, accountId: parcelId } }),
      deps,
    )).status,
    200,
  );
  assertEquals(
    (await handleParcelDeliveries(request({ body: { operation: "partnerSnapshot" } }), deps))
      .status,
    200,
  );
  assertEquals(
    (await handleParcelDeliveries(request({ body: { operation: "customerSnapshot" } }), deps))
      .status,
    200,
  );
  assertEquals(recorded, [["parcel", accountId, parcelId], ["partner", accountId], [
    "customer",
    accountId,
  ]]);
});

Deno.test("assignment and lifecycle operations map to server-owned actions", async () => {
  const cases = [
    ["acknowledgeAssignment", "acknowledge", null],
    ["declineAssignment", "decline", null],
    ["startToPickup", "start_to_pickup", null],
    ["confirmPickup", "confirm_pickup", "123456"],
    ["startDelivery", "start_delivery", null],
    ["completeDelivery", "complete_delivery", "654321"],
  ] as const;

  for (const [operation, expectedAction, verificationCode] of cases) {
    let recorded: Record<string, unknown> | undefined;
    const response = await handleParcelDeliveries(
      request({
        body: {
          operation,
          assignmentId,
          verificationCode,
          status: "delivered",
          parcelId,
        },
      }),
      dependencies({
        acknowledgeAssignment: (input) => {
          recorded = { ...input, action: "acknowledge" };
          return ok(partnerSnapshot());
        },
        declineAssignment: (input) => {
          recorded = { ...input, action: "decline" };
          return ok(partnerSnapshot());
        },
        advanceParcel: (input) => {
          recorded = input;
          return ok(partnerSnapshot());
        },
      }),
    );

    assertEquals(response.status, 200);
    assertEquals(recorded?.accountId, accountId);
    assertEquals(recorded?.assignmentId, assignmentId);
    assertEquals(recorded?.action, expectedAction);
    assertEquals(recorded?.verificationCode ?? null, verificationCode);
    assertEquals("status" in (recorded ?? {}), false);
    assertEquals("parcelId" in (recorded ?? {}), false);
  }
});

Deno.test("handoff transitions require six-digit codes", async () => {
  for (const operation of ["confirmPickup", "completeDelivery"]) {
    for (const verificationCode of [undefined, "1234", "12345a", "1234567"]) {
      const response = await handleParcelDeliveries(
        request({ body: { operation, assignmentId, verificationCode } }),
        dependencies(),
      );
      await assertError(response, 400, "validation_failed");
    }
  }
});

Deno.test("cancellation and safety reports use the authenticated customer", async () => {
  let cancellation: Record<string, unknown> | undefined;
  let incident: Record<string, unknown> | undefined;
  const deps = dependencies({
    cancelParcel: (input) => {
      cancellation = input;
      return ok(parcel({ status: "cancelled" }));
    },
    reportSafetyIncident: (input) => {
      incident = input;
      return ok({ incidentId: assignmentId, status: "open", emergencyNumber: "112" });
    },
  });

  const cancelled = await handleParcelDeliveries(
    request({ body: { operation: "cancelParcel", parcelId, reason: "No longer needed" } }),
    deps,
  );
  const reported = await handleParcelDeliveries(
    request({
      body: {
        operation: "reportSafetyIncident",
        parcelId,
        incidentType: "unsafe_handoff",
        reportText: "Recipient location is unsafe.",
      },
    }),
    deps,
  );

  assertEquals(cancelled.status, 200);
  assertEquals(cancellation?.accountId, accountId);
  assertEquals(reported.status, 200);
  assertEquals(incident?.accountId, accountId);
});

Deno.test("parcel support is validated and owned by the authenticated customer", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleParcelDeliveries(
    request({
      body: {
        operation: "customerSupport",
        parcelId,
        category: "delivery_status",
        message: "  My parcel has not moved.  ",
      },
      idempotencyKey: "support-key-1",
    }),
    dependencies({
      createCustomerSupport: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: { supportCase: {} }, responseStatus: 201 });
      },
    }),
  );

  assertEquals(response.status, 201);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.parcelId, parcelId);
  assertEquals(recorded?.category, "delivery_status");
  assertEquals(recorded?.message, "My parcel has not moved.");
});

Deno.test("dependency failures do not leak private details", async () => {
  const response = await handleParcelDeliveries(
    request({ body: { operation: "partnerSnapshot" } }),
    dependencies({
      getPartnerSnapshot: () => Promise.reject(new Error("private parcel digest leaked")),
    }),
  );
  const body = await response.json();
  assertEquals(response.status, 500);
  assertEquals(body.error.code, "internal_error");
  assertEquals(JSON.stringify(body).includes("digest"), false);
});

function dependencies(
  overrides: Partial<ParcelDeliveryDependencies> = {},
): ParcelDeliveryDependencies {
  return {
    authenticateBearer: () => Promise.resolve({ accountId }),
    routeParcel: () => Promise.resolve({ distanceMeters: 4_250, durationSeconds: 720 }),
    quoteParcel: () => ok(quote()),
    createParcel: () => Promise.resolve({ responseBody: parcel(), responseStatus: 201 }),
    getCustomerSnapshot: () => ok([parcel()]),
    getParcelSnapshot: () => ok(parcel()),
    getPartnerSnapshot: () => ok(partnerSnapshot()),
    acknowledgeAssignment: () => ok(partnerSnapshot()),
    declineAssignment: () => ok(partnerSnapshot()),
    advanceParcel: () => ok(partnerSnapshot()),
    cancelParcel: () => ok(parcel({ status: "cancelled" })),
    createCustomerSupport: () =>
      Promise.resolve({ responseBody: { supportCase: {} }, responseStatus: 201 }),
    reportSafetyIncident: () =>
      ok({ incidentId: assignmentId, status: "open", emergencyNumber: "112" }),
    ...overrides,
  };
}

function ok(responseBody: unknown) {
  return Promise.resolve({ responseBody, responseStatus: 200 });
}

function quote() {
  return {
    quoteId,
    deliveryMethod: "bike",
    routeDistanceMeters: 4_250,
    routeDurationSeconds: 720,
    deliveryFee: { currency: "INR", paise: 5000 },
    courierPayout: { currency: "INR", paise: 4000 },
    expiresAt: "2026-07-19T12:05:00Z",
  };
}

function parcel(overrides: Record<string, unknown> = {}) {
  return {
    parcelId,
    status: "payment_pending",
    paymentStatus: "pending",
    refundStatus: "not_requested",
    deliveryMethod: "bike",
    pickup: { latitude: 12.68, longitude: 78.62, address: "1 Pickup Road" },
    dropoff: { latitude: 12.69, longitude: 78.64, address: "2 Drop Road" },
    recipient: { name: "Asha Khan", phoneNumber: "+919876543210" },
    declaredContents: "Sealed documents",
    declaredValue: { currency: "INR", paise: 2500 },
    deliveryFee: { currency: "INR", paise: 5000 },
    courierPayout: { currency: "INR", paise: 4000 },
    handoffCode: null,
    ...overrides,
  };
}

function partnerSnapshot() {
  return { offer: null, currentJob: null };
}

function request(
  options: {
    authorization?: string | null;
    body?: unknown;
    idempotencyKey?: string;
  } = {},
) {
  const headers = new Headers({ "content-type": "application/json" });
  if (options.authorization !== null) {
    headers.set("authorization", options.authorization ?? "Bearer valid");
  }
  headers.set("X-Idempotency-Key", options.idempotencyKey ?? "test-key");
  return new Request("http://localhost/functions/v1/parcel-deliveries", {
    method: "POST",
    headers,
    body: JSON.stringify(options.body ?? { operation: "partnerSnapshot" }),
  });
}

async function assertError(response: Response, status: number, code: string) {
  assertEquals(response.status, status);
  assertEquals((await response.json()).error.code, code);
}
