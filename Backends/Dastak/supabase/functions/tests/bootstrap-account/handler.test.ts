import { assertEquals, assertExists } from "jsr:@std/assert";
import {
  canonicalBootstrapDigest,
  handleBootstrapAccount,
} from "../../bootstrap-account/handler.ts";
import type {
  AuthenticateBearer,
  BootstrapAccount,
  BootstrapAccountInput,
} from "../../bootstrap-account/handler.ts";

Deno.test("bootstrap account accepts browser CORS preflight", async () => {
  let authenticationAttempts = 0;
  const response = await handleBootstrapAccount(
    preflightRequest("bootstrap-account"),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({
          accountId: "22222222-2222-4222-8222-222222222222",
          oauthProviders: ["apple"],
        });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 204);
  assertCorsHeaders(response);
});

Deno.test("bootstrap account rejects missing authorization", async () => {
  let authenticationAttempts = 0;
  const response = await handleBootstrapAccount(
    request({ headers: { "X-Idempotency-Key": "key-1" } }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({
          accountId: "22222222-2222-4222-8222-222222222222",
          oauthProviders: ["apple"],
        });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 401);
  assertEquals(await jsonBody(response), {
    error: {
      code: "authentication_required",
      message: "A valid bearer token is required.",
    },
  });
});

Deno.test("bootstrap account authenticates an invalid bearer before request validation", async () => {
  let authenticationAttempts = 0;
  const response = await handleBootstrapAccount(
    request({
      authorization: "Bearer invalid-session-token",
      body: { displayName: "   ", phoneNumber: "not-a-phone-number" },
    }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.reject(new Error("invalid bearer token"));
      },
    }),
  );

  assertEquals(authenticationAttempts, 1);
  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("bootstrap account rejects malformed authorization without authenticating", async () => {
  let authenticationAttempts = 0;
  const response = await handleBootstrapAccount(
    request({
      authorization: "Token session-token",
      headers: { "X-Idempotency-Key": "key-1" },
    }),
    dependencies({
      authenticateBearer: () => {
        authenticationAttempts += 1;
        return Promise.resolve({
          accountId: "22222222-2222-4222-8222-222222222222",
          oauthProviders: ["google"],
        });
      },
    }),
  );

  assertEquals(authenticationAttempts, 0);
  assertEquals(response.status, 401);
  assertEquals((await jsonBody(response)).error.code, "authentication_required");
});

Deno.test("bootstrap account rejects missing idempotency key", async () => {
  const response = await handleBootstrapAccount(
    request({ authorization: "Bearer session-token" }),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals((await jsonBody(response)).error.code, "validation_failed");
});

Deno.test("bootstrap account rejects authenticated sessions without Apple or Google", async () => {
  const response = await handleBootstrapAccount(
    request({
      authorization: "Bearer session-token",
      headers: { "X-Idempotency-Key": "key-no-oauth" },
    }),
    dependencies({
      authenticateBearer: () =>
        Promise.resolve({
          accountId: "22222222-2222-4222-8222-222222222222",
          oauthProviders: [],
        }),
    }),
  );

  assertEquals(response.status, 403);
  assertEquals((await jsonBody(response)).error.code, "oauth_identity_required");
});

Deno.test("bootstrap account rejects missing display name", async () => {
  const response = await handleBootstrapAccount(
    request({
      authorization: "Bearer session-token",
      body: { displayName: "   ", phoneNumber: "+14155552671" },
    }),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals((await jsonBody(response)).error.code, "validation_failed");
});

Deno.test("bootstrap account rejects invalid phone numbers", async () => {
  const response = await handleBootstrapAccount(
    request({
      authorization: "Bearer session-token",
      body: { displayName: "Test User", phoneNumber: "+1 415 555 2671" },
      headers: { "X-Idempotency-Key": "key-1" },
    }),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals((await jsonBody(response)).error.code, "invalid_phone_number");
});

Deno.test("bootstrap account forwards normalized server-only RPC payload", async () => {
  let recorded: BootstrapAccountInput | undefined;
  const response = await handleBootstrapAccount(
    request({
      authorization: "Bearer session-token",
      body: { displayName: "  Test   User  ", phoneNumber: " +14155552671 " },
      headers: { "X-Idempotency-Key": "key-1" },
    }),
    dependencies({
      bootstrapAccount: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: {
            accountId: "22222222-2222-4222-8222-222222222222",
            phoneState: "unverified",
          },
          responseStatus: 200,
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await jsonBody(response), {
    accountId: "22222222-2222-4222-8222-222222222222",
    phoneState: "unverified",
  });
  assertExists(recorded);
  assertEquals(recorded.accountId, "22222222-2222-4222-8222-222222222222");
  assertEquals(recorded.displayName, "Test User");
  assertEquals(recorded.phoneNumber, "+14155552671");
  assertEquals(recorded.idempotencyKey, "key-1");
  assertEquals(
    recorded.requestDigest,
    await canonicalBootstrapDigest({
      displayName: "Test User",
      phoneNumber: "+14155552671",
    }),
  );
});

Deno.test("bootstrap account replays typed database errors", async () => {
  const response = await handleBootstrapAccount(
    request({
      authorization: "Bearer session-token",
      headers: { "X-Idempotency-Key": "key-1" },
    }),
    dependencies({
      bootstrapAccount: () =>
        Promise.resolve({
          responseBody: {
            error: {
              code: "idempotency_conflict",
              message: "The idempotency key was already used with a different request.",
            },
          },
          responseStatus: 409,
        }),
    }),
  );

  assertEquals(response.status, 409);
  assertEquals((await jsonBody(response)).error.code, "idempotency_conflict");
});

Deno.test("bootstrap account forwards account already exists database response", async () => {
  const response = await handleBootstrapAccount(
    request({
      authorization: "Bearer session-token",
      headers: { "X-Idempotency-Key": "key-2" },
    }),
    dependencies({
      bootstrapAccount: () =>
        Promise.resolve({
          responseBody: {
            error: {
              code: "account_already_exists",
              message: "An account already exists for this authenticated user.",
            },
          },
          responseStatus: 409,
        }),
    }),
  );

  assertEquals(response.status, 409);
  assertEquals((await jsonBody(response)).error.code, "account_already_exists");
});

function dependencies(
  overrides: Partial<{
    authenticateBearer: AuthenticateBearer;
    bootstrapAccount: BootstrapAccount;
  }> = {},
) {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() =>
        Promise.resolve({
          accountId: "22222222-2222-4222-8222-222222222222",
          oauthProviders: ["apple"],
        })),
    bootstrapAccount: overrides.bootstrapAccount ??
      (() =>
        Promise.resolve({
          responseBody: {
            accountId: "22222222-2222-4222-8222-222222222222",
            phoneState: "unverified",
          },
          responseStatus: 200,
        })),
  };
}

function request(options: {
  authorization?: string;
  headers?: Record<string, string>;
  body?: unknown;
} = {}) {
  const headers = new Headers({
    "content-type": "application/json",
    ...options.headers,
  });
  if (options.authorization) {
    headers.set("authorization", options.authorization);
  }
  return new Request("http://localhost/functions/v1/bootstrap-account", {
    method: "POST",
    headers,
    body: JSON.stringify(
      options.body ?? { displayName: "Test User", phoneNumber: "+14155552671" },
    ),
  });
}

async function jsonBody(response: Response) {
  return await response.json();
}

function preflightRequest(functionName: string) {
  return new Request(`http://localhost/functions/v1/${functionName}`, {
    method: "OPTIONS",
    headers: {
      origin: "https://dastak-customer.vercel.app",
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
