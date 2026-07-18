import { assertEquals } from "jsr:@std/assert";
import {
  type ControlledCategoryDependencies,
  handleControlledCategories,
} from "../../controlled-categories/handler.ts";

const accountId = "11111111-1111-4111-8111-111111111111";
const storeId = "22222222-2222-4222-8222-222222222222";
const productId = "33333333-3333-4333-8333-333333333333";
const quoteId = "44444444-4444-4444-8444-444444444444";
const assignmentId = "55555555-5555-4555-8555-555555555555";

Deno.test("controlled categories authenticate before accepting operations", async () => {
  const response = await handleControlledCategories(
    request({ operation: "browse", scope: "medicine", location: location() }, "Bearer bad"),
    dependencies({ authenticateBearer: () => Promise.reject(new Error("bad token")) }),
  );
  await assertError(response, 401, "authentication_required");
});

Deno.test("adult attestation forwards both explicit affirmations and server identity", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleControlledCategories(
    request({
      operation: "attestAdult",
      policyVersion: "2026-01",
      affirmedAdult: true,
      affirmedNotForMinor: true,
      accountId: storeId,
    }),
    dependencies({
      attestAdult: (input) => {
        recorded = input;
        return ok({ policyVersion: "2026-01", attestedAt: "2026-07-19T10:00:00Z" });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.affirmedAdult, true);
  assertEquals(recorded?.affirmedNotForMinor, true);
});

Deno.test("controlled quote accepts product intent but no client price or compliance result", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleControlledCategories(
    request({
      operation: "quote",
      scope: "medicine",
      storeId,
      lines: [{ productId, quantity: 2 }],
      dropoff: location(),
      prescriptionEvidencePath: `prescription/${accountId}/rx.pdf`,
      itemSubtotalPaise: 1,
      complianceApproved: true,
      ageVerified: true,
    }),
    dependencies({
      quoteOrder: (input) => {
        recorded = input;
        return ok({ quoteId });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.scope, "medicine");
  assertEquals("itemSubtotalPaise" in (recorded ?? {}), false);
  assertEquals("complianceApproved" in (recorded ?? {}), false);
  assertEquals("ageVerified" in (recorded ?? {}), false);
});

Deno.test("restricted handoff records only the assigned partner observation", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleControlledCategories(
    request({
      operation: "verifyRestrictedHandoff",
      assignmentId,
      verificationCode: "1234",
      visualAgeCheck: "uncertain",
      reason: "Recipient could not provide acceptable proof of age.",
      orderStatus: "delivered",
    }),
    dependencies({
      verifyRestrictedHandoff: (input) => {
        recorded = input;
        return ok({ offer: null, currentJob: null });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.visualAgeCheck, "uncertain");
  assertEquals("orderStatus" in (recorded ?? {}), false);
});

Deno.test("failed or uncertain visual checks require a reason", async () => {
  for (const visualAgeCheck of ["failed", "uncertain"]) {
    const response = await handleControlledCategories(
      request({
        operation: "verifyRestrictedHandoff",
        assignmentId,
        verificationCode: "1234",
        visualAgeCheck,
      }),
      dependencies(),
    );
    await assertError(response, 400, "validation_failed");
  }
});

function dependencies(
  overrides: Partial<ControlledCategoryDependencies> = {},
): ControlledCategoryDependencies {
  return {
    authenticateBearer: () => Promise.resolve({ accountId }),
    attestAdult: () => ok({}),
    browseCatalogue: () => ok({ stores: [], categories: [], products: [] }),
    quoteOrder: () => ok({ quoteId }),
    createOrder: () => ok({ orderId: quoteId }),
    getOrderSnapshot: () => ok({ orderId: quoteId }),
    submitStoreCompliance: () => ok({}),
    reviewStoreCompliance: () => ok({}),
    submitProduct: () => ok({}),
    reviewProduct: () => ok({}),
    upsertPolicy: () => ok({}),
    upsertExclusionZone: () => ok({}),
    verifyRestrictedHandoff: () => ok({ offer: null, currentJob: null }),
    confirmRestrictedReturn: () => ok({ orderId: quoteId }),
    getPrescriptionEvidencePath: () => Promise.resolve(null),
    signEvidenceDownload: () => Promise.resolve("https://signed.example/rx"),
    ...overrides,
  };
}

function request(
  body: Record<string, unknown>,
  authorization = "Bearer valid",
  idempotencyKey = "controlled-key-1",
) {
  return new Request("http://localhost/functions/v1/controlled-categories", {
    method: "POST",
    headers: {
      authorization,
      "content-type": "application/json",
      "X-Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify(body),
  });
}

function location() {
  return { latitude: 12.6819, longitude: 78.6201 };
}

function ok(responseBody: unknown, responseStatus = 200) {
  return Promise.resolve({ responseBody, responseStatus });
}

async function assertError(response: Response, status: number, code: string) {
  assertEquals(response.status, status);
  assertEquals((await response.json()).error.code, code);
}
