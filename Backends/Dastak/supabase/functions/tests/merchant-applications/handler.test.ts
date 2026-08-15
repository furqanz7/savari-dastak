import { assert, assertEquals } from "jsr:@std/assert";
import {
  handleMerchantApplications,
  type GetMerchantApplicationSnapshot,
  type ListMerchantApplications,
  type ReviewMerchantApplication,
  type ReviewMerchantApplicationInput,
  type SubmitMerchantApplication,
  type SubmitMerchantApplicationInput,
} from "../../merchant-applications/handler.ts";
import type { AuthenticateBearer } from "../../bootstrap-account/handler.ts";

Deno.test("merchant applications answer browser preflight without authentication", async () => {
  let authenticationAttempts = 0;
  const response = await handleMerchantApplications(
    new Request("http://localhost/functions/v1/merchant-applications", { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
  assertEquals(authenticationAttempts, 0);
});

Deno.test("merchant applications reject missing authorization", async () => {
  let authenticationAttempts = 0;
  const response = await handleMerchantApplications(
    request({ operation: "list" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("merchant applications authenticate before validating the operation", async () => {
  const response = await handleMerchantApplications(
    request({ operation: "unsupported" }, "Bearer invalid-token"),
    dependencies({
      authenticateBearer: () => Promise.reject(new Error("invalid bearer")),
    }),
  );

  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("merchant submission forwards only normalized server-owned input", async () => {
  let recorded: SubmitMerchantApplicationInput | undefined;
  const response = await handleMerchantApplications(
    request(
      {
        operation: "submit",
        accountId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        businessName: "  Corner   Store  ",
        businessAddress: "  12   Main Road  ",
        evidenceObjectPath: `merchant/${accountId}/registration.pdf`,
      },
      "Bearer session-token",
      "merchant-submit-1",
    ),
    dependencies({
      submitMerchantApplication: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: { applicationId, status: "pending" },
          responseStatus: 200,
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await jsonBody(response), { applicationId, status: "pending" });
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.businessName, "Corner Store");
  assertEquals(recorded?.businessAddress, "12 Main Road");
  assertEquals(recorded?.evidenceObjectPath, `merchant/${accountId}/registration.pdf`);
  assertEquals(recorded?.idempotencyKey, "merchant-submit-1");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
});

Deno.test("merchant submission rejects another account evidence path", async () => {
  let submissions = 0;
  const response = await handleMerchantApplications(
    request(
      {
        operation: "submit",
        businessName: "Corner Store",
        businessAddress: "12 Main Road",
        evidenceObjectPath: "merchant/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/registration.pdf",
      },
      "Bearer session-token",
      "merchant-submit-2",
    ),
    dependencies({
      submitMerchantApplication: () => {
        submissions += 1;
        return Promise.resolve({ responseBody: {}, responseStatus: 200 });
      },
    }),
  );

  assertEquals(submissions, 0);
  assertEquals(response.status, 400);
  assertEquals((await jsonBody(response)).error.code, "validation_failed");
});

Deno.test("merchant self snapshot is scoped to the authenticated account", async () => {
  let recordedAccountId: string | undefined;
  const snapshot = {
    onboardingState: "rejected",
    applicationId,
    businessName: "Corner Store",
    businessAddress: "12 Main Road",
    evidenceObjectPath: `merchant/${accountId}/registration.pdf`,
    reviewReason: "Document is unclear.",
  };
  const response = await handleMerchantApplications(
    request({ operation: "selfSnapshot", accountId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }, "Bearer session-token"),
    dependencies({
      getMerchantApplicationSnapshot: (authenticatedAccountId) => {
        recordedAccountId = authenticatedAccountId;
        return Promise.resolve({ responseBody: snapshot, responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recordedAccountId, accountId);
  assertEquals(await jsonBody(response), snapshot);
});

Deno.test("merchant application list denies a non-owner", async () => {
  let listCalls = 0;
  const response = await handleMerchantApplications(
    request({ operation: "list" }, "Bearer session-token"),
    dependencies({
      isActiveOwner: () => Promise.resolve(false),
      listMerchantApplications: () => {
        listCalls += 1;
        return Promise.resolve([]);
      },
    }),
  );

  assertEquals(listCalls, 0);
  assertEquals(response.status, 403);
  assertEquals((await jsonBody(response)).error.code, "access_denied");
});

Deno.test("active owner can list pending merchant applications", async () => {
  const applications = [{
    applicationId,
    accountId,
    businessName: "Corner Store",
    businessAddress: "12 Main Road",
    evidenceObjectPath: `merchant/${accountId}/registration.pdf`,
    status: "pending" as const,
  }];
  const response = await handleMerchantApplications(
    request({ operation: "list" }, "Bearer session-token"),
    dependencies({
      isActiveOwner: (ownerId) => Promise.resolve(ownerId === accountId),
      listMerchantApplications: () => Promise.resolve(applications),
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await jsonBody(response), { applications });
});

Deno.test("active owner review forwards verified owner and normalized reason", async () => {
  let recorded: ReviewMerchantApplicationInput | undefined;
  const response = await handleMerchantApplications(
    request(
      {
        operation: "review",
        ownerId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        applicationId,
        decision: "reject",
        reason: "  Missing   registration  ",
      },
      "Bearer session-token",
      "merchant-review-1",
    ),
    dependencies({
      isActiveOwner: () => Promise.resolve(true),
      reviewMerchantApplication: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: { applicationId, status: "rejected" },
          responseStatus: 200,
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.ownerId, accountId);
  assertEquals(recorded?.applicationId, applicationId);
  assertEquals(recorded?.decision, "reject");
  assertEquals(recorded?.reason, "Missing registration");
  assertEquals(recorded?.idempotencyKey, "merchant-review-1");
  assert(recorded?.requestDigest.match(/^[0-9a-f]{64}$/));
});

Deno.test("merchant application dependency failures do not leak details", async () => {
  const response = await handleMerchantApplications(
    request({ operation: "list" }, "Bearer session-token"),
    dependencies({
      isActiveOwner: () => Promise.reject(new Error("private schema unavailable")),
    }),
  );

  assertEquals(response.status, 500);
  assertEquals(await jsonBody(response), {
    error: {
      code: "internal_error",
      message: "Merchant applications could not be processed.",
    },
  });
});

const accountId = "22222222-2222-4222-8222-222222222222";
const applicationId = "33333333-3333-4333-8333-333333333333";

function dependencies(
  overrides: Partial<{
    authenticateBearer: AuthenticateBearer;
    isActiveOwner: (accountId: string) => Promise<boolean>;
    submitMerchantApplication: SubmitMerchantApplication;
    getMerchantApplicationSnapshot: GetMerchantApplicationSnapshot;
    listMerchantApplications: ListMerchantApplications;
    reviewMerchantApplication: ReviewMerchantApplication;
  }> = {},
) {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve({ accountId })),
    isActiveOwner: overrides.isActiveOwner ?? (() => Promise.resolve(false)),
    submitMerchantApplication: overrides.submitMerchantApplication ??
      (() => Promise.resolve({ responseBody: {}, responseStatus: 200 })),
    getMerchantApplicationSnapshot: overrides.getMerchantApplicationSnapshot ??
      (() => Promise.resolve({ responseBody: {}, responseStatus: 200 })),
    listMerchantApplications: overrides.listMerchantApplications ??
      (() => Promise.resolve([])),
    reviewMerchantApplication: overrides.reviewMerchantApplication ??
      (() => Promise.resolve({ responseBody: {}, responseStatus: 200 })),
  };
}

function request(
  body: unknown,
  authorization?: string,
  idempotencyKey?: string,
) {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request("http://localhost/functions/v1/merchant-applications", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function jsonBody(response: Response) {
  return await response.json();
}
