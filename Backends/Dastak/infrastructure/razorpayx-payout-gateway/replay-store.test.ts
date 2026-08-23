import { assertEquals } from "jsr:@std/assert";
import { FileReplayStore } from "./replay-store.ts";

Deno.test("replay claims survive gateway restart and expire deterministically", async () => {
  const directory = await Deno.makeTempDir({ prefix: "dastak-payout-replay-" });
  const path = `${directory}/replay.jsonl`;
  let now = new Date("2026-08-23T12:00:00.000Z");
  const digest = "a".repeat(64);
  try {
    const first = await FileReplayStore.open(path, () => now);
    assertEquals(await first.claim(digest, new Date(now.valueOf() + 120_000)), true);
    assertEquals(await first.claim(digest, new Date(now.valueOf() + 120_000)), false);

    const afterRestart = await FileReplayStore.open(path, () => now);
    assertEquals(await afterRestart.claim(digest, new Date(now.valueOf() + 120_000)), false);

    now = new Date(now.valueOf() + 120_001);
    assertEquals(await afterRestart.claim(digest, new Date(now.valueOf() + 120_000)), true);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
