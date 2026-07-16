import { assertEquals } from "jsr:@std/assert";
import {
  handleResolveAppAccess,
  type ResolveAppAccess,
  type ResolveAppAccessInput,
} from "../../resolve-app-access/handler.ts";
import type { AuthenticateBearer } from "../../bootstrap-account/handler.ts";

Deno.test("resolve app access rejects missing authorization", async () => {
  let authenticationAttempts = 0;
  const response = await handleResolveAppAccess(
    request({ application: "customer" }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({ accountId: accountId });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("resolve app access authenticates before validating the body", async () => {
  const response = await handleResolveAppAccess(
    request({ application: "unsupported" }, "Bearer invalid-token"),
    dependencies({
      authenticateBearer: () => Promise.reject(new Error("invalid bearer")),
    }),
  );

  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("resolve app access rejects unsupported applications", async () => {
  let resolverCalls = 0;
  const response = await handleResolveAppAccess(
    request({ application: "unsupported" }, "Bearer session-token"),
    dependencies({
      resolveAppAccess: () => {
        resolverCalls += 1;
        return Promise.resolve({ route: "active" });
      },
    }),
  );

  assertEquals(resolverCalls, 0);
  assertEquals(response.status, 400);
  assertEquals((await jsonBody(response)).error.code, "invalid_application");
});

Deno.test("resolve app access forwards only the authenticated account and application", async () => {
  let recorded: ResolveAppAccessInput | undefined;
  const response = await handleResolveAppAccess(
    request({ application: "merchant" }, "Bearer session-token"),
    dependencies({
      resolveAppAccess: (input) => {
        recorded = input;
        return Promise.resolve({ route: "pending_approval" });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await jsonBody(response), { route: "pending_approval" });
  assertEquals(recorded, { accountId, application: "merchant" });
});

Deno.test("resolve app access fails closed when the resolver fails", async () => {
  const response = await handleResolveAppAccess(
    request({ application: "admin" }, "Bearer session-token"),
    dependencies({
      resolveAppAccess: () => Promise.reject(new Error("database unavailable")),
    }),
  );

  assertEquals(response.status, 500);
  assertEquals(await jsonBody(response), {
    error: {
      code: "internal_error",
      message: "Application access could not be resolved.",
    },
  });
});

const accountId = "22222222-2222-4222-8222-222222222222";

function dependencies(
  overrides: Partial<{
    authenticateBearer: AuthenticateBearer;
    resolveAppAccess: ResolveAppAccess;
  }> = {},
) {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve({ accountId })),
    resolveAppAccess: overrides.resolveAppAccess ??
      (() => Promise.resolve({ route: "active" as const })),
  };
}

function request(body: unknown, authorization?: string) {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) {
    headers.set("authorization", authorization);
  }
  return new Request("http://localhost/functions/v1/resolve-app-access", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function jsonBody(response: Response) {
  return await response.json();
}
