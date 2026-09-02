import { assertEquals } from "jsr:@std/assert";
import {
  type DeliveryPartnerDependencies,
  handleDeliveryPartners,
} from "../../delivery-partners/handler.ts";

const accountId = "11111111-1111-4111-8111-111111111111";
const applicationId = "abcdefab-cdef-4abc-8def-abcdefabcdef";
const evidencePath = `dastak-partner/${accountId}/identity.pdf`;
const vehicleEvidencePath = `dastak-partner/${accountId}/vehicle.pdf`;

Deno.test("delivery partners accept browser CORS preflight", async () => {
  let authenticationAttempts = 0;
  const response = await handleDeliveryPartners(
    preflightRequest("delivery-partners"),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 204);
  assertCorsHeaders(response);
});

Deno.test("delivery partners reject missing authorization", async () => {
  const response = await handleDeliveryPartners(request({ authorization: null }), dependencies());
  await assertError(response, 401, "authentication_required");
});

Deno.test("delivery partners authenticate before validating the operation", async () => {
  let authenticated = false;
  const response = await handleDeliveryPartners(
    request({ authorization: "Bearer invalid", body: {} }),
    dependencies({
      authenticateBearer: () => {
        authenticated = true;
        return Promise.reject(new Error("invalid token"));
      },
    }),
  );

  assertEquals(authenticated, true);
  await assertError(response, 401, "authentication_required");
});

Deno.test("partner submission forwards normalized self-owned evidence only", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleDeliveryPartners(
    request({
      body: {
        operation: "submit",
        accountId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        deliveryMethod: "bike",
        identityEvidenceObjectPath: evidencePath,
        vehicleRegistrationNumber: " tn 23 ab 1234 ",
        vehicleMakeModel: "  Honda   Activa 6G ",
        vehicleEvidenceObjectPath: vehicleEvidencePath,
        approved: true,
      },
    }),
    dependencies({
      submitApplication: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: { applicationId, status: "pending", deliveryMethod: "bike" },
          responseStatus: 200,
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.deliveryMethod, "bike");
  assertEquals(recorded?.identityEvidenceObjectPath, evidencePath);
  assertEquals(recorded?.vehicleRegistrationNumber, "TN 23 AB 1234");
  assertEquals(recorded?.vehicleMakeModel, "Honda Activa 6G");
  assertEquals(recorded?.vehicleEvidenceObjectPath, vehicleEvidencePath);
  assertEquals(recorded?.idempotencyKey, "test-key");
  assertEquals(typeof recorded?.requestDigest, "string");
  assertEquals("approved" in (recorded ?? {}), false);
});

Deno.test("motor delivery methods require self-owned vehicle details and proof", async () => {
  const missingVehicle = await handleDeliveryPartners(
    request({
      body: {
        operation: "submit",
        deliveryMethod: "auto",
        identityEvidenceObjectPath: evidencePath,
      },
    }),
    dependencies(),
  );
  await assertError(missingVehicle, 400, "validation_failed");

  const sameDocument = await handleDeliveryPartners(
    request({
      body: {
        operation: "submit",
        deliveryMethod: "car",
        identityEvidenceObjectPath: evidencePath,
        vehicleRegistrationNumber: "TN 23 AB 1234",
        vehicleMakeModel: "Maruti Suzuki Swift",
        vehicleEvidenceObjectPath: evidencePath,
      },
    }),
    dependencies(),
  );
  await assertError(sameDocument, 400, "validation_failed");
});

Deno.test("motorbike and scooter onboarding preserve the selected transport type", async () => {
  const recorded: string[] = [];
  for (const deliveryMethod of ["motorbike", "scooter"] as const) {
    const response = await handleDeliveryPartners(
      request({
        body: {
          operation: "submit",
          deliveryMethod,
          identityEvidenceObjectPath: evidencePath,
          vehicleRegistrationNumber: "TN 23 AB 1234",
          vehicleMakeModel: "Verified vehicle",
          vehicleEvidenceObjectPath: vehicleEvidencePath,
        },
        idempotencyKey: `submit-${deliveryMethod}`,
      }),
      dependencies({
        submitApplication: (input) => {
          recorded.push(input.deliveryMethod);
          return Promise.resolve({
            responseBody: { applicationId, status: "pending", deliveryMethod },
            responseStatus: 200,
          });
        },
      }),
    );
    assertEquals(response.status, 200);
  }
  assertEquals(recorded, ["motorbike", "scooter"]);
});

Deno.test("walking and bicycle applications cannot smuggle vehicle data", async () => {
  const response = await handleDeliveryPartners(
    request({
      body: {
        operation: "submit",
        deliveryMethod: "walking",
        identityEvidenceObjectPath: evidencePath,
        vehicleRegistrationNumber: "TN 23 AB 1234",
      },
    }),
    dependencies(),
  );
  await assertError(response, 400, "validation_failed");
});

Deno.test("partner submission rejects unsupported methods and foreign evidence", async () => {
  const unsupported = await handleDeliveryPartners(
    request({
      body: {
        operation: "submit",
        deliveryMethod: "truck",
        identityEvidenceObjectPath: evidencePath,
      },
    }),
    dependencies(),
  );
  await assertError(unsupported, 400, "validation_failed");

  const foreign = await handleDeliveryPartners(
    request({
      body: {
        operation: "submit",
        deliveryMethod: "walking",
        identityEvidenceObjectPath:
          "dastak-partner/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/identity.pdf",
      },
    }),
    dependencies(),
  );
  await assertError(foreign, 400, "validation_failed");
});

Deno.test("self snapshot uses only the authenticated account", async () => {
  let recordedAccountId: string | undefined;
  const response = await handleDeliveryPartners(
    request({ body: { operation: "selfSnapshot", accountId: applicationId } }),
    dependencies({
      getSelfSnapshot: (inputAccountId) => {
        recordedAccountId = inputAccountId;
        return Promise.resolve({
          responseBody: { onboardingState: "not_applied", availability: null },
          responseStatus: 200,
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recordedAccountId, accountId);
});

Deno.test("only an active owner can list and review partner applications", async () => {
  let listed = false;
  const denied = await handleDeliveryPartners(
    request({ body: { operation: "listPending" } }),
    dependencies({ isActiveOwner: () => Promise.resolve(false) }),
  );
  await assertError(denied, 403, "access_denied");

  const allowed = await handleDeliveryPartners(
    request({ body: { operation: "listPending" } }),
    dependencies({
      listPendingApplications: () => {
        listed = true;
        return Promise.resolve([]);
      },
    }),
  );
  assertEquals(allowed.status, 200);
  assertEquals(listed, true);

  let review: Record<string, unknown> | undefined;
  const reviewed = await handleDeliveryPartners(
    request({
      body: {
        operation: "review",
        applicationId: applicationId.toUpperCase(),
        decision: "reject",
        reason: "  Identity image is unclear.  ",
        accountId,
      },
    }),
    dependencies({
      reviewApplication: (input) => {
        review = input;
        return Promise.resolve({
          responseBody: { applicationId, status: "rejected", deliveryMethod: "bike" },
          responseStatus: 200,
        });
      },
    }),
  );
  assertEquals(reviewed.status, 200);
  assertEquals(review?.ownerId, accountId);
  assertEquals(review?.applicationId, applicationId);
  assertEquals(review?.decision, "reject");
  assertEquals(review?.reason, "Identity image is unclear.");
});

Deno.test("availability sends no client service zone or partner identity", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const deps = dependencies({
    setAvailability: (input) => {
      calls.push(input);
      return Promise.resolve({
        responseBody: {
          status: input.online ? "online" : "offline",
          location: input.online ? { latitude: 12.68, longitude: 78.62 } : null,
          serviceZoneId: input.online ? applicationId : null,
          availableUntil: input.online ? "2026-07-16T12:15:00Z" : null,
          stateVersion: calls.length,
        },
        responseStatus: 200,
      });
    },
  });

  const online = await handleDeliveryPartners(
    request({
      body: {
        operation: "setAvailability",
        online: true,
        location: { latitude: 12.68, longitude: 78.62 },
        serviceZoneId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      },
    }),
    deps,
  );
  assertEquals(online.status, 200);
  assertEquals(calls[0]?.accountId, accountId);
  assertEquals(calls[0]?.latitude, 12.68);
  assertEquals(calls[0]?.longitude, 78.62);
  assertEquals("serviceZoneId" in calls[0], false);

  const offline = await handleDeliveryPartners(
    request({ body: { operation: "setAvailability", online: false } }),
    deps,
  );
  assertEquals(offline.status, 200);
  assertEquals(calls[1]?.latitude, null);
  assertEquals(calls[1]?.longitude, null);
});

Deno.test("availability rejects missing online location and offline location payloads", async () => {
  const missingLocation = await handleDeliveryPartners(
    request({ body: { operation: "setAvailability", online: true } }),
    dependencies(),
  );
  await assertError(missingLocation, 400, "validation_failed");

  const offlineLocation = await handleDeliveryPartners(
    request({
      body: {
        operation: "setAvailability",
        online: false,
        location: { latitude: 12.68, longitude: 78.62 },
      },
    }),
    dependencies(),
  );
  await assertError(offlineLocation, 400, "validation_failed");
});

Deno.test("location publication uses the authenticated partner and exact coordinates", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleDeliveryPartners(
    request({
      body: {
        operation: "publishLocation",
        accountId: applicationId,
        location: { latitude: 12.681, longitude: 78.623 },
        availableUntil: "2099-01-01T00:00:00Z",
      },
    }),
    dependencies({
      publishLocation: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: {
            status: "online",
            location: { latitude: input.latitude, longitude: input.longitude },
            serviceZoneId: applicationId,
            availableUntil: "2026-07-16T12:15:00Z",
            stateVersion: 2,
          },
          responseStatus: 200,
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.latitude, 12.681);
  assertEquals(recorded?.longitude, 78.623);
  assertEquals(recorded?.idempotencyKey, "test-key");
  assertEquals(typeof recorded?.requestDigest, "string");
  assertEquals("availableUntil" in (recorded ?? {}), false);
});

Deno.test("location publication rejects invalid coordinates", async () => {
  const response = await handleDeliveryPartners(
    request({
      body: { operation: "publishLocation", location: { latitude: 91, longitude: 78.62 } },
    }),
    dependencies(),
  );
  await assertError(response, 400, "validation_failed");
});

Deno.test("delivery partner dependency failures do not leak details", async () => {
  const response = await handleDeliveryPartners(
    request({ body: { operation: "selfSnapshot" } }),
    dependencies({
      getSelfSnapshot: () => Promise.reject(new Error("private schema unavailable")),
    }),
  );
  const body = await response.json();
  assertEquals(response.status, 500);
  assertEquals(body.error.code, "internal_error");
  assertEquals(JSON.stringify(body).includes("private schema"), false);
});

function dependencies(
  overrides: Partial<DeliveryPartnerDependencies> = {},
): DeliveryPartnerDependencies {
  return {
    authenticateBearer: () => Promise.resolve({ accountId }),
    isActiveOwner: () => Promise.resolve(true),
    submitApplication: () =>
      Promise.resolve({
        responseBody: { applicationId, status: "pending", deliveryMethod: "walking" },
        responseStatus: 200,
      }),
    getSelfSnapshot: () =>
      Promise.resolve({
        responseBody: { onboardingState: "not_applied", availability: null },
        responseStatus: 200,
      }),
    listPendingApplications: () => Promise.resolve([]),
    reviewApplication: () =>
      Promise.resolve({
        responseBody: { applicationId, status: "approved", deliveryMethod: "walking" },
        responseStatus: 200,
      }),
    setAvailability: () =>
      Promise.resolve({
        responseBody: {
          status: "offline",
          location: null,
          serviceZoneId: null,
          availableUntil: null,
          stateVersion: 1,
        },
        responseStatus: 200,
      }),
    publishLocation: () =>
      Promise.resolve({
        responseBody: {
          status: "online",
          location: { latitude: 12.68, longitude: 78.62 },
          serviceZoneId: applicationId,
          availableUntil: "2026-07-16T12:15:00Z",
          stateVersion: 2,
        },
        responseStatus: 200,
      }),
    ...overrides,
  };
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
  return new Request("http://localhost/functions/v1/delivery-partners", {
    method: "POST",
    headers,
    body: JSON.stringify(options.body ?? { operation: "selfSnapshot" }),
  });
}

async function assertError(response: Response, status: number, code: string) {
  assertEquals(response.status, status);
  assertEquals((await response.json()).error.code, code);
}

function preflightRequest(functionName: string) {
  return new Request(`http://localhost/functions/v1/${functionName}`, {
    method: "OPTIONS",
    headers: {
      origin: "https://dastak-delivery.vercel.app",
      "access-control-request-method": "POST",
      "access-control-request-headers": "apikey,authorization,content-type,x-idempotency-key",
    },
  });
}

function assertCorsHeaders(response: Response) {
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
  assertEquals(response.headers.get("access-control-allow-methods"), "POST, OPTIONS");
  assertEquals(
    response.headers.get("access-control-allow-headers"),
    "authorization, x-client-info, apikey, content-type, x-idempotency-key",
  );
}
