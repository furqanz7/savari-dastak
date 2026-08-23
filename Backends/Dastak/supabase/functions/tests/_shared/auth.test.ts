import { assertEquals, assertThrows } from "jsr:@std/assert";
import { dastakOAuthProviders } from "../../_shared/auth.ts";

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
