import { assertEquals } from "jsr:@std/assert";
import { type EarningsDependencies, handleEarnings } from "../../earnings/handler.ts";

const request = (body: unknown, authorization = "Bearer valid") =>
  new Request("https://example.test/earnings", {
    method: "POST",
    headers: { authorization, "content-type": "application/json" },
    body: JSON.stringify(body),
  });

const dependencies = (
  overrides: Partial<EarningsDependencies> = {},
): EarningsDependencies => ({
  authenticateBearer: async () => ({ accountId: "account-1", accessToken: "valid" }),
  fetchSnapshot: async () => [{
    response_body: {
      currency: "INR",
      completedPaise: 100,
      pendingPaise: 20,
      thisWeekPaise: 100,
    },
    response_status: 200,
  }],
  ...overrides,
});

Deno.test("earnings accepts browser CORS preflight", async () => {
  const response = await handleEarnings(
    new Request("https://example.test/earnings", { method: "OPTIONS" }),
    dependencies(),
  );
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
});

Deno.test("earnings rejects unauthenticated callers", async () => {
  const response = await handleEarnings(
    request({ operation: "merchantSnapshot" }, ""),
    dependencies({ authenticateBearer: async () => Promise.reject(new Error("invalid")) }),
  );
  assertEquals(response.status, 401);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
});

Deno.test("earnings forwards the authenticated delivery partner snapshot", async () => {
  let call: [string, string] | undefined;
  const response = await handleEarnings(
    request({ operation: "deliveryPartnerSnapshot" }),
    dependencies({
      fetchSnapshot: async (rpc, accountId) => {
        call = [rpc, accountId];
        return [{ response_body: { currency: "INR" }, response_status: 200 }];
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(call, ["get_dastak_delivery_earnings", "account-1"]);
});

Deno.test("earnings rejects unsupported operations", async () => {
  const response = await handleEarnings(request({ operation: "ownerSnapshot" }), dependencies());
  assertEquals(response.status, 400);
});

Deno.test("earnings maps invalid RPC responses without leaking details", async () => {
  const response = await handleEarnings(
    request({ operation: "merchantSnapshot" }),
    dependencies({ fetchSnapshot: async () => ({ response_status: "200" }) }),
  );
  assertEquals(response.status, 503);
  assertEquals(await response.json(), {
    error: {
      code: "earnings_unavailable",
      message: "Earnings are temporarily unavailable.",
    },
  });
});
