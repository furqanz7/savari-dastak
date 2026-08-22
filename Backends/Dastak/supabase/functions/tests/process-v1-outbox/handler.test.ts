import { assertEquals } from "jsr:@std/assert";
import {
  handleV1OutboxWorker,
  type V1NotificationJob,
  type V1OutboxWorkerDependencies,
} from "../../process-v1-outbox/handler.ts";

const job: V1NotificationJob = {
  deliveryId: "94000000-0000-4000-8000-000000000001",
  eventId: "94000000-0000-4000-8000-000000000002",
  notificationType: "customer.out_for_delivery",
  recipientAccountId: "94000000-0000-4000-8000-000000000003",
  deviceToken: "device-token",
  platform: "ios",
  title: "Your order is on the way",
  body: "Keep your in-app delivery code ready for handoff.",
  payload: {
    entityType: "dastakV1Order",
    orderId: "94000000-0000-4000-8000-000000000004",
  },
  attempt: 1,
};

Deno.test("V1 outbox worker rejects callers without its internal secret", async () => {
  const response = await handleV1OutboxWorker(request("wrong"), dependencies());
  assertEquals(response.status, 403);
});

Deno.test("V1 outbox worker fans out, claims, completes and monitors", async () => {
  const calls: string[] = [];
  const response = await handleV1OutboxWorker(
    request("secret"),
    dependencies({
      fanout: () => {
        calls.push("fanout");
        return Promise.resolve({ eventsPublished: 1, deliveriesCreated: 1 });
      },
      claim: () => {
        calls.push("claim");
        return Promise.resolve([job]);
      },
      deliver: () => {
        calls.push("deliver");
        return Promise.resolve({
          succeeded: true,
          permanentTokenFailure: false,
          providerStatus: 200,
          providerResponse: "",
        });
      },
      complete: () => {
        calls.push("complete");
        return Promise.resolve();
      },
      runInvariantMonitors: () => {
        calls.push("monitor");
        return Promise.resolve({ healthy: true, findingCount: 0 });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(calls, ["fanout", "claim", "deliver", "complete", "monitor"]);
  assertEquals((await response.json()).sent, 1);
});

Deno.test("provider exceptions become durable retry completions", async () => {
  let completion:
    | { succeeded: boolean; permanentTokenFailure: boolean; providerResponse: string }
    | undefined;
  const response = await handleV1OutboxWorker(
    request("secret"),
    dependencies({
      claim: () => Promise.resolve([job]),
      deliver: () => Promise.reject(new Error("network unavailable")),
      complete: (_job, result) => {
        completion = result;
        return Promise.resolve();
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(completion?.succeeded, false);
  assertEquals(completion?.permanentTokenFailure, false);
  assertEquals(completion?.providerResponse, "network unavailable");
});

Deno.test("V1 worker bounds provider concurrency while completing every claim", async () => {
  let active = 0;
  let maximumActive = 0;
  let completed = 0;
  const response = await handleV1OutboxWorker(
    request("secret"),
    dependencies({
      claim: () =>
        Promise.resolve(
          Array.from({ length: 12 }, (_, index) => ({
            ...job,
            deliveryId: `94000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
          })),
        ),
      deliver: async () => {
        active += 1;
        maximumActive = Math.max(maximumActive, active);
        await new Promise((resolve) => setTimeout(resolve, 5));
        active -= 1;
        return {
          succeeded: true,
          permanentTokenFailure: false,
          providerStatus: 200,
          providerResponse: "",
        };
      },
      complete: () => {
        completed += 1;
        return Promise.resolve();
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(maximumActive, 10);
  assertEquals(completed, 12);
  assertEquals((await response.json()).sent, 12);
});

function request(secret: string) {
  return new Request("http://localhost/functions/v1/process-v1-outbox", {
    method: "POST",
    headers: { "x-dastak-internal-secret": secret },
    body: "{}",
  });
}

function dependencies(
  overrides: Partial<V1OutboxWorkerDependencies> = {},
): V1OutboxWorkerDependencies {
  return {
    expectedSecret: "secret",
    workerId: "test-worker",
    fanout: () => Promise.resolve({ eventsPublished: 0, deliveriesCreated: 0 }),
    claim: () => Promise.resolve([]),
    deliver: () =>
      Promise.resolve({
        succeeded: true,
        permanentTokenFailure: false,
        providerStatus: 200,
        providerResponse: "",
      }),
    complete: () => Promise.resolve(),
    runInvariantMonitors: () => Promise.resolve({ healthy: true, findingCount: 0 }),
    ...overrides,
  };
}
