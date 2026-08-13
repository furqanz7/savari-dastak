import { assertMatch, assertNotMatch } from "jsr:@std/assert";

Deno.test("delivery earnings use the canonical Dastak partner role", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260813003805_fix_dastak_delivery_earnings_role.sql",
      import.meta.url,
    ),
  );
  const normalized = migration.replace(/\s+/g, " ");

  assertMatch(normalized, /membership\.role = 'dastak_partner'/i);
  assertNotMatch(normalized, /membership\.role = 'delivery_partner'/i);
  assertMatch(normalized, /security invoker/i);
  assertMatch(normalized, /set search_path = ''/i);
  assertMatch(
    normalized,
    /revoke execute on function public\.get_dastak_delivery_earnings\(uuid\) from public, anon, authenticated/i,
  );
  assertMatch(
    normalized,
    /grant execute on function public\.get_dastak_delivery_earnings\(uuid\) to service_role/i,
  );
});
