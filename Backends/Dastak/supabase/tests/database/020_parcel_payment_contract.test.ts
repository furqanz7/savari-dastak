import { assert, assertMatch } from "jsr:@std/assert";

Deno.test("Razorpay parcel events narrow the validated amount to the parcel contract", async () => {
  const migrationsDirectory = new URL("../../migrations/", import.meta.url);
  const migrationNames: string[] = [];

  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith(".sql")) migrationNames.push(entry.name);
  }

  let latestDefinition = "";
  for (const migrationName of migrationNames.toSorted()) {
    const sql = await Deno.readTextFile(new URL(migrationName, migrationsDirectory));
    if (/create(?: or replace)? function public\.record_razorpay_parcel_event\s*\(/i.test(sql)) {
      latestDefinition = sql;
    }
  }

  assert(latestDefinition, "record_razorpay_parcel_event must be defined by a migration");
  assertMatch(
    latestDefinition.replace(/\s+/g, " "),
    /from public\.record_parcel_payment_event\([^;]*p_amount_paise::integer,/i,
  );
});
