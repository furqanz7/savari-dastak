import { assertEquals, assertThrows } from "jsr:@std/assert";
import { dastakOAuthProviders, oauthAuthenticationTimestamp } from "../../_shared/auth.ts";

Deno.test("Dastak bearer identity accepts Apple, Google and explicitly linked pairs", () => {
  assertEquals(dastakOAuthProviders({ identities: [{ provider: "apple" }] }), ["apple"]);
  assertEquals(dastakOAuthProviders({ identities: [{ provider: "google" }] }), ["google"]);
  assertEquals(
    dastakOAuthProviders({ identities: [{ provider: "google" }, { provider: "apple" }] }),
    ["apple", "google"],
  );
});

Deno.test("Dastak bearer identity rejects anonymous, password, phone and missing identity", () => {
  assertThrows(() => dastakOAuthProviders({ is_anonymous: true, identities: [] }));
  assertThrows(() => dastakOAuthProviders({ identities: [] }));
  assertThrows(() => dastakOAuthProviders({ identities: [{ provider: "email" }] }));
  assertThrows(() => dastakOAuthProviders({ identities: [{ provider: "phone" }] }));
  assertThrows(() =>
    dastakOAuthProviders({ identities: [{ provider: "apple" }, { provider: "email" }] })
  );
});

Deno.test("Dastak bearer identity reads the most recent OAuth authentication time", () => {
  const token = jwt({
    session_id: "11111111-1111-4111-8111-111111111111",
    amr: [
      { method: "oauth", timestamp: 1_700_000_000 },
      { method: "token_refresh", timestamp: 1_700_000_100 },
      { method: "oauth", timestamp: 1_700_000_200 },
    ],
  });
  assertEquals(oauthAuthenticationTimestamp(token), 1_700_000_200);
  assertEquals(
    oauthAuthenticationTimestamp(jwt({ amr: [{ method: "password", timestamp: 1 }] })),
    undefined,
  );
});

function jwt(payload: unknown) {
  const encoded = btoa(JSON.stringify(payload)).replaceAll("=", "").replaceAll("+", "-")
    .replaceAll("/", "_");
  return `header.${encoded}.signature`;
}
