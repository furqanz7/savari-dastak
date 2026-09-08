import { assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260908151354_deduplicate_preparation_notifications.sql",
    import.meta.url,
  ),
);

Deno.test("preparation notifications fan out only from the canonical order event", () => {
  assertMatch(
    migration,
    /v_event\.event_type\s*<>\s*'PREPARATION_STARTED'[\s\S]*?v_event\.aggregate_type\s*=\s*'ORDER'/i,
  );
});

Deno.test("deduplication preserves the outbox publisher security boundary", () => {
  assertMatch(migration, /security definer/i);
  assertMatch(migration, /set search_path\s*=\s*''/i);
  assertMatch(migration, /status\s*=\s*'PUBLISHED'/i);
});
