import { assertEquals } from "jsr:@std/assert@1";
import {
  createLiveActivityWorker,
  isTerminal,
  type LiveActivityJob,
  liveActivityPayload,
} from "../../process-v1-outbox/live-activities.ts";
import { exportPKCS8, generateKeyPair } from "npm:jose@5";
const job: LiveActivityJob = {
  id: "id",
  leaseId: "lease",
  tokenVersion: 2,
  token: "abc",
  environment: "sandbox",
  status: "PREPARING",
  version: 7,
  updatedAt: 100,
  timestamp: 200,
};
Deno.test("mission arrival stays active and survives the APNs wire payload", () => {
  const payload = liveActivityPayload({ ...job, status: "RIDER_ARRIVED" });
  assertEquals(payload.aps.event, "update");
  assertEquals(payload.aps["content-state"].status, "RIDER_ARRIVED");
  assertEquals(isTerminal("RIDER_ARRIVED"), false);
});
Deno.test("assigning rider is an active update without a call or payment payload", () => {
  const payload = liveActivityPayload({ ...job, status: "ASSIGNING_RIDER" });
  assertEquals(payload.aps.event, "update");
  assertEquals(payload.aps["content-state"], {
    status: "ASSIGNING_RIDER",
    version: 7,
    updatedAt: 100,
  });
  assertEquals(isTerminal("ASSIGNING_RIDER"), false);
});
Deno.test("ActivityKit updates contain only status and freshness, with no alert duplication or personal details", () => {
  assertEquals(liveActivityPayload(job), {
    aps: {
      timestamp: 200,
      event: "update",
      "content-state": { status: "PREPARING", version: 7, updatedAt: 100 },
      "stale-date": 380,
    },
  });
});
Deno.test("all cancellation and expiry outcomes end activity; session expiry dismisses immediately", () => {
  for (
    const status of [
      "DELIVERED",
      "UNAVAILABLE",
      "PAYMENT_EXPIRED",
      "CANCELLED_PREPAYMENT",
      "CANCELLED",
      "DASTAK_FULFILMENT_FAILURE",
      "ENDED",
    ]
  ) {
    assertEquals(isTerminal(status), true);
    assertEquals(liveActivityPayload({ ...job, status }).aps.event, "end");
  }
  const ended = liveActivityPayload({ ...job, status: "ENDED" }).aps;
  assertEquals("dismissal-date" in ended ? ended["dismissal-date"] : null, 200);
});
Deno.test("background push uses ActivityKit topic, environment, token generation and lease", async () => {
  const { privateKey } = await generateKeyPair("ES256", { extractable: true });
  const calls: Array<{ name: string; params: Record<string, unknown> }> = [];
  let captured: Request | undefined;
  const run = createLiveActivityWorker(
    {
      environment: "production",
      bundleId: "ignored",
      keyId: "key",
      teamId: "team",
      privateKey: await exportPKCS8(privateKey),
    },
    (name, params) => {
      calls.push({ name, params });
      return Promise.resolve(name.includes("claim") ? [job] : null);
    },
    ((url, init) => {
      captured = new Request(url, init);
      return Promise.resolve(new Response("{}", { status: 200 }));
    }) as typeof fetch,
  );
  await run();
  assertEquals(captured?.url, "https://api.sandbox.push.apple.com/3/device/abc");
  assertEquals(captured?.headers.get("apns-topic"), "com.dastak.app.push-type.liveactivity");
  assertEquals(captured?.headers.get("apns-push-type"), "liveactivity");
  assertEquals(calls[1].params.p_token_version, 2);
  assertEquals(calls[1].params.p_lease_id, "lease");
  assertEquals(calls[1].params.p_retire, false);
});
