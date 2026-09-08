import { assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260908133157_restore_handoff_key_integrity.sql",
    import.meta.url,
  ),
);

Deno.test("handoff key repair preserves an existing key and restores a missing key", () => {
  assertMatch(
    migration,
    /insert into private\.order_handoff_code_keys[\s\S]*?on conflict \(singleton\) do nothing/i,
  );
  assertNotMatch(migration, /update\s+private\.order_handoff_code_keys/i);
});

Deno.test("handoff code configuration fails explicitly and resists deletion", () => {
  assertMatch(migration, /message\s*=\s*'SYSTEM_CONFIGURATION_ERROR'/i);
  assertMatch(
    migration,
    /create trigger order_handoff_code_keys_no_delete[\s\S]*?before delete/i,
  );
});
