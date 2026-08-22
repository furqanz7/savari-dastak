import { assertEquals } from "jsr:@std/assert";
import { handleIssueEvidenceUrl } from "../../issue-evidence-url/handler.ts";
import type {
  AuthenticateBearer,
  IsActiveOwner,
  SignEvidenceDownload,
} from "../../issue-evidence-url/handler.ts";

const accountId = "22222222-2222-4222-8222-222222222222";
const otherAccountId = "33333333-3333-4333-8333-333333333333";
const selfPath = `dastak-partner/${accountId}/delivery-photo.jpg`;

Deno.test("evidence URL serves browser preflight without authentication", async () => {
  const response = await handleIssueEvidenceUrl(
    new Request("http://localhost/functions/v1/issue-evidence-url", { method: "OPTIONS" }),
    dependencies(),
  );

  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
});

Deno.test("evidence URL rejects missing authorization before validation", async () => {
  let calls = 0;
  const response = await handleIssueEvidenceUrl(
    request({ authorization: null, body: { bucket: "wrong" } }),
    dependencies({
      authenticateBearer: () => {
        calls += 1;
        return Promise.resolve({ accountId });
      },
    }),
  );

  assertEquals(calls, 0);
  assertError(response, 401, "authentication_required");
});

Deno.test("evidence URL authenticates an invalid bearer before payload validation", async () => {
  let calls = 0;
  const response = await handleIssueEvidenceUrl(
    request({ authorization: "Bearer invalid", body: { bucket: "wrong" } }),
    dependencies({
      authenticateBearer: () => {
        calls += 1;
        return Promise.reject(new Error("invalid"));
      },
    }),
  );

  assertEquals(calls, 1);
  assertError(response, 401, "authentication_required");
});

Deno.test("evidence URL rejects invalid bucket, operation, and path", async () => {
  assertError(
    await handleIssueEvidenceUrl(
      request({ body: { bucket: "wrong", objectPath: selfPath, operation: "download" } }),
      dependencies(),
    ),
    400,
    "validation_failed",
  );
  assertError(
    await handleIssueEvidenceUrl(
      request({ body: { bucket: "dastak-evidence", objectPath: selfPath, operation: "upload" } }),
      dependencies(),
    ),
    400,
    "validation_failed",
  );
  assertError(
    await handleIssueEvidenceUrl(
      request({
        body: {
          bucket: "dastak-evidence",
          objectPath: `dastak-partner/${accountId}/nested/file`,
          operation: "download",
        },
      }),
      dependencies(),
    ),
    400,
    "validation_failed",
  );
});

Deno.test("evidence URL signs a self-owned Dastak partner object for exactly 300 seconds", async () => {
  let signed: { bucket: string; objectPath: string; expiresIn: number } | undefined;
  const response = await handleIssueEvidenceUrl(
    request({ body: { bucket: "dastak-evidence", objectPath: selfPath, operation: "download" } }),
    dependencies({
      signDownload: (input) => {
        signed = input;
        return Promise.resolve("https://example.test/evidence");
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    signedUrl: "https://example.test/evidence",
    expiresIn: 300,
  });
  assertEquals(signed, { bucket: "dastak-evidence", objectPath: selfPath, expiresIn: 300 });
});

Deno.test("evidence URL signs self-owned rider delivery evidence and lets Operations inspect it", async () => {
  const evidenceId = "44444444-4444-4444-8444-444444444444";
  const riderPath = `rider-delivery/${accountId}/${evidenceId}.jpg`;
  const selfResponse = await handleIssueEvidenceUrl(
    request({
      body: { bucket: "dastak-evidence", objectPath: riderPath, operation: "download" },
    }),
    dependencies({ isActiveOwner: () => Promise.reject(new Error("must not be called")) }),
  );
  assertEquals(selfResponse.status, 200);

  const operationsResponse = await handleIssueEvidenceUrl(
    request({
      body: {
        bucket: "dastak-evidence",
        objectPath: `rider-delivery/${otherAccountId}/${evidenceId}.jpg`,
        operation: "download",
      },
    }),
    dependencies({ isActiveOwner: () => Promise.resolve(true) }),
  );
  assertEquals(operationsResponse.status, 200);
});

Deno.test("evidence URL denies another user's evidence object", async () => {
  let signingCalls = 0;
  const response = await handleIssueEvidenceUrl(
    request({
      body: {
        bucket: "dastak-evidence",
        objectPath: `dastak-partner/${otherAccountId}/delivery-photo.jpg`,
        operation: "download",
      },
    }),
    dependencies({
      signDownload: () => {
        signingCalls += 1;
        return Promise.resolve("https://example.test/unexpected");
      },
    }),
  );

  assertEquals(signingCalls, 0);
  assertError(response, 403, "access_denied");
});

Deno.test("evidence URL permits an active owner to download another user's Dastak partner object", async () => {
  let ownerLookupAccountId: string | undefined;
  const response = await handleIssueEvidenceUrl(
    request({
      body: {
        bucket: "dastak-evidence",
        objectPath: `dastak-partner/${otherAccountId}/delivery-photo.jpg`,
        operation: "download",
      },
    }),
    dependencies({
      isActiveOwner: (id) => {
        ownerLookupAccountId = id;
        return Promise.resolve(true);
      },
    }),
  );

  assertEquals(ownerLookupAccountId, accountId);
  assertEquals(response.status, 200);
});

Deno.test("evidence URL denies an inactive or suspended owner for an owner-only root", async () => {
  let ownerLookupAccountId: string | undefined;
  let signingCalls = 0;
  const response = await handleIssueEvidenceUrl(
    request({
      body: {
        bucket: "dastak-evidence",
        objectPath: "prescription/44444444-4444-4444-8444-444444444444/order.pdf",
        operation: "download",
      },
    }),
    dependencies({
      isActiveOwner: (id) => {
        ownerLookupAccountId = id;
        return Promise.resolve(false);
      },
      signDownload: () => {
        signingCalls += 1;
        return Promise.resolve("https://example.test/unexpected");
      },
    }),
  );

  assertEquals(ownerLookupAccountId, accountId);
  assertEquals(signingCalls, 0);
  assertError(response, 403, "access_denied");
});

Deno.test("evidence URL maps owner lookup failures to internal_error without signing", async () => {
  let ownerLookupCalls = 0;
  let signingCalls = 0;
  const response = await handleIssueEvidenceUrl(
    request({
      body: {
        bucket: "dastak-evidence",
        objectPath: `dastak-partner/${otherAccountId}/route-photo.jpg`,
        operation: "download",
      },
    }),
    dependencies({
      isActiveOwner: () => {
        ownerLookupCalls += 1;
        return Promise.reject(new Error("membership lookup unavailable"));
      },
      signDownload: () => {
        signingCalls += 1;
        return Promise.resolve("https://example.test/unexpected");
      },
    }),
  );

  assertEquals(ownerLookupCalls, 1);
  assertEquals(signingCalls, 0);
  assertError(response, 500, "internal_error");
});

Deno.test("evidence URL permits an active owner to download foundation-only object roots", async () => {
  let ownerLookupAccountId: string | undefined;
  const response = await handleIssueEvidenceUrl(
    request({
      body: {
        bucket: "dastak-evidence",
        objectPath: "pharmacy/44444444-4444-4444-8444-444444444444/prescription.pdf",
        operation: "download",
      },
    }),
    dependencies({
      isActiveOwner: (id) => {
        ownerLookupAccountId = id;
        return Promise.resolve(true);
      },
    }),
  );

  assertEquals(ownerLookupAccountId, accountId);
  assertEquals(response.status, 200);
});

Deno.test("evidence URL permits an active owner to inspect immutable merchant Ready evidence", async () => {
  const response = await handleIssueEvidenceUrl(
    request({
      body: {
        bucket: "dastak-evidence",
        objectPath:
          "merchant-ready/44444444-4444-4444-8444-444444444444/55555555-5555-4555-8555-555555555555.jpg",
        operation: "download",
      },
    }),
    dependencies({ isActiveOwner: () => Promise.resolve(true) }),
  );
  assertEquals(response.status, 200);
});

Deno.test("evidence URL maps storage failures without exposing implementation details", async () => {
  const response = await handleIssueEvidenceUrl(
    request({ body: { bucket: "dastak-evidence", objectPath: selfPath, operation: "download" } }),
    dependencies({ signDownload: () => Promise.reject(new Error("storage unavailable")) }),
  );

  assertError(response, 502, "evidence_url_unavailable");
});

function dependencies(
  overrides: Partial<
    {
      authenticateBearer: AuthenticateBearer;
      isActiveOwner: IsActiveOwner;
      signDownload: SignEvidenceDownload;
    }
  > = {},
) {
  return {
    authenticateBearer: overrides.authenticateBearer ?? (() => Promise.resolve({ accountId })),
    isActiveOwner: overrides.isActiveOwner ?? (() => Promise.resolve(false)),
    signDownload: overrides.signDownload ??
      (() => Promise.resolve("https://example.test/evidence")),
  };
}

function request(options: { authorization?: string | null; body?: unknown } = {}) {
  const headers = new Headers({ "content-type": "application/json" });
  const authorization = options.authorization === undefined
    ? "Bearer session-token"
    : options.authorization;
  if (authorization) headers.set("authorization", authorization);
  return new Request("http://localhost/functions/v1/issue-evidence-url", {
    method: "POST",
    headers,
    body: JSON.stringify(options.body ?? {}),
  });
}

async function assertError(response: Response, status: number, code: string) {
  assertEquals(response.status, status);
  assertEquals((await response.json()).error.code, code);
}
