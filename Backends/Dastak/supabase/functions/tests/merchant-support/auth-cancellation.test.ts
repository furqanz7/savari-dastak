import { deepStrictEqual as assertEquals, rejects } from "node:assert";
import { verifyBearerUser } from "../../_shared/auth.ts";

for (const stage of ["identity", "revocation", "success", "revoked"] as const) {
  Deno.test(`optional auth signal preserves security checks: ${stage}`, async () => {
    const environment = {
      SUPABASE_URL: "https://support-fixture.supabase.co",
      SUPABASE_PUBLISHABLE_KEY: "fixture-publishable",
      SUPABASE_SERVICE_ROLE_KEY: "fixture-service-only",
    };
    const previous = Object.fromEntries(
      Object.keys(environment).map((key) => [key, Deno.env.get(key)]),
    );
    for (const [key, value] of Object.entries(environment)) Deno.env.set(key, value);
    const original = globalThis.fetch;
    const controller = new AbortController();
    const signals: AbortSignal[] = [];
    let contacted!: () => void;
    const contact = new Promise<void>((resolve) => contacted = resolve);
    globalThis.fetch = (url, init) => {
      if (init?.signal) signals.push(init.signal);
      const auth = String(url).includes("/auth/v1/user");
      if ((stage === "identity" && auth) || (stage === "revocation" && !auth)) {
        contacted();
        return new Promise((_resolve, reject) => {
          init!.signal!.addEventListener(
            "abort",
            () => reject(new DOMException("Fixture aborted", "AbortError")),
            { once: true },
          );
        });
      }
      return Promise.resolve(
        new Response(
          JSON.stringify(
            auth
              ? {
                id: "11111111-1111-4111-8111-111111111111",
                email: "support@example.test",
                identities: [{ provider: "apple" }],
              }
              : stage === "revoked",
          ),
          { headers: { "Content-Type": "application/json" } },
        ),
      );
    };
    const token = `header.${
      btoa(JSON.stringify({ session_id: "22222222-2222-4222-8222-222222222222" }))
    }.signature`;
    try {
      const pending = verifyBearerUser(`Bearer ${token}`, { signal: controller.signal });
      if (stage === "identity" || stage === "revocation") {
        const rejected = rejects(pending);
        await contact;
        controller.abort();
        await rejected;
      } else if (stage === "revoked") await rejects(pending, /revoked/);
      else assertEquals((await pending).oauthProviders, ["apple"]);
      assertEquals(signals.length, stage === "identity" ? 1 : 2);
      assertEquals(signals.every((signal) => signal === controller.signal), true);
    } finally {
      globalThis.fetch = original;
      for (const [key, value] of Object.entries(previous)) {
        if (value === undefined) Deno.env.delete(key);
        else Deno.env.set(key, value);
      }
    }
  });
}
