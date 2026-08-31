import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await read("../../migrations/20260824070000_customer_onboarding_completion.sql");
const config = await read("../../config.toml");
const profileIndex = await read("../../functions/account-profile/index.ts");
const workerIndex = await read("../../functions/process-v1-outbox/index.ts");
const webPush = await read("../../functions/process-v1-outbox/web-push.ts");
const serviceWorker = await read(
  "../../../../../Web/MarketplaceWeb/public/dastak-sw.js",
);

Deno.test("customer onboarding completion remains additive and history safe", () => {
  assertMatch(migration, /create or replace function public\.bootstrap_account/i);
  assertMatch(migration, /claim_customer_account_deletions/i);
  assertMatch(migration, /for update skip locked/i);
  assertMatch(migration, /platform in \('ios', 'web', 'all'\)/i);
  assertMatch(migration, /notification_intents_event_recipient_type_platform_key/i);
  assertNotMatch(migration, /truncate\s+table|drop\s+table|delete\s+from\s+dastak_v1\.orders/i);
  assertNotMatch(migration, /delete\s+from\s+public\.accounts/i);
});

Deno.test("persona deletion is server-owned and does not delete the canonical Auth user", () => {
  assertMatch(profileIndex, /prepare_dastak_persona_deletion/);
  assertNotMatch(profileIndex, /auth\.admin\.deleteUser/);
  assertMatch(workerIndex, /auth\.admin\.deleteUser/);
  assertMatch(workerIndex, /complete_customer_account_deletion/);
});

Deno.test("Customer Web push is server delivered and does not weaken worker authentication", () => {
  const workerConfig = config.match(
    /\[functions\.process-v1-outbox\][\s\S]*?(?=\n\[|$)/,
  )?.[0];
  assert(workerConfig);
  assertMatch(workerConfig, /verify_jwt\s*=\s*false/);
  assertMatch(workerIndex, /expectedSecret:\s*requiredEnv\("DASTAK_NOTIFICATION_SECRET"\)/);
  assertMatch(workerIndex, /WEB_PUSH_VAPID_SUBJECT/);
  assertMatch(workerIndex, /WEB_PUSH_VAPID_PUBLIC_KEY/);
  assertMatch(workerIndex, /WEB_PUSH_VAPID_PRIVATE_KEY/);
  assertMatch(webPush, /setVapidDetails/);
  assertMatch(webPush, /eventId/);
  assertMatch(serviceWorker, /showNotification/);
  assertNotMatch(serviceWorker, /verificationCode|paymentCredential|merchantDisplayName/i);
});

async function read(relativePath: string) {
  return await Deno.readTextFile(new URL(relativePath, import.meta.url));
}
