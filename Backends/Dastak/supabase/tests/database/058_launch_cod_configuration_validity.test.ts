import { assertEquals, assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260901174500_align_launch_cod_validation.sql",
    import.meta.url,
  ),
);

Deno.test("launch COD default and validation remain aligned", () => {
  assertMatch(
    migration,
    /where setting_key = 'commerce\.allow_cod'/,
  );
  assertMatch(migration, /default_value = 'true'::jsonb/);
  assertMatch(migration, /\{"allowedValues":\[true\]\}/);
  assertEquals(/platform_settings/i.test(migration), false);
});
