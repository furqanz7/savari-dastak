import { assertMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(new URL(
  "../../migrations/20260928224102_recognize_doorstep_collection_in_paid_invariant.sql",
  import.meta.url,
));

Deno.test("paid-order monitor accepts exact successful doorstep collection", () => {
  assertMatch(migration, /payment\.status = 'SUCCEEDED'/);
  assertMatch(migration, /collection\.outcome = 'COLLECTED'/);
  assertMatch(migration, /collection\.order_id = customer_order\.id/);
  assertMatch(migration, /collection\.collected_at = customer_order\.paid_at/);
  assertMatch(migration, /expected paid-authority monitor predicate was not found/);
  assertMatch(migration, /paid-authority monitor predicate was ambiguous/);
});
