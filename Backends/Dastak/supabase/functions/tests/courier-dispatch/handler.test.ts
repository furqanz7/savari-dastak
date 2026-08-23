import { assertEquals } from "jsr:@std/assert";
import {
  type CourierDispatchDependencies,
  handleCourierDispatch,
} from "../../courier-dispatch/handler.ts";

const accountId = "11111111-1111-4111-8111-111111111111";
const assignmentId = "22222222-2222-4222-8222-222222222222";
const offerId = "33333333-3333-4333-8333-333333333333";
const missionId = "44444444-4444-4444-8444-444444444444";
const stopId = "55555555-5555-4555-8555-555555555555";

Deno.test("courier dispatch serves browser preflight without authentication", async () => {
  const response = await handleCourierDispatch(
    new Request("http://localhost/functions/v1/courier-dispatch", { method: "OPTIONS" }),
    dependencies(),
  );

  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
});

Deno.test("courier dispatch rejects missing authorization", async () => {
  const response = await handleCourierDispatch(request({ authorization: null }), dependencies());
  await assertError(response, 401, "authentication_required");
});

Deno.test("courier dispatch authenticates before operation validation", async () => {
  let authenticated = false;
  const response = await handleCourierDispatch(
    request({ authorization: "Bearer invalid", body: {} }),
    dependencies({
      authenticateBearer: () => {
        authenticated = true;
        return Promise.reject(new Error("invalid token"));
      },
    }),
  );

  assertEquals(authenticated, true);
  await assertError(response, 401, "authentication_required");
});

Deno.test("partner snapshot uses only the authenticated account", async () => {
  let recordedAccountId: string | undefined;
  const response = await handleCourierDispatch(
    request({ body: { operation: "partnerSnapshot", accountId: assignmentId } }),
    dependencies({
      getPartnerSnapshot: (inputAccountId) => {
        recordedAccountId = inputAccountId;
        return Promise.resolve({ responseBody: snapshot(), responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recordedAccountId, accountId);
});

Deno.test("V1 partner snapshot and offer actions bind the authenticated rider", async () => {
  let snapshotAccount: string | undefined;
  let accepted: Record<string, unknown> | undefined;
  let declined: Record<string, unknown> | undefined;
  const deps = dependencies({
    getV1PartnerSnapshot: (inputAccountId) => {
      snapshotAccount = inputAccountId;
      return Promise.resolve({
        responseBody: { offer: null, currentMission: null },
        responseStatus: 200,
      });
    },
    acceptV1Offer: (input) => {
      accepted = input;
      return Promise.resolve({ responseBody: { offer: null }, responseStatus: 200 });
    },
    declineV1Offer: (input) => {
      declined = input;
      return Promise.resolve({ responseBody: { offer: null }, responseStatus: 200 });
    },
  });

  assertEquals(
    (await handleCourierDispatch(
      request({
        body: { operation: "v1PartnerSnapshot", accountId: assignmentId },
      }),
      deps,
    )).status,
    200,
  );
  assertEquals(
    (await handleCourierDispatch(
      request({
        body: { operation: "v1AcceptOffer", offerId, riderId: assignmentId },
      }),
      deps,
    )).status,
    200,
  );
  assertEquals(
    (await handleCourierDispatch(
      request({
        body: { operation: "v1DeclineOffer", offerId, reason: "  Too far  " },
      }),
      deps,
    )).status,
    200,
  );

  assertEquals(snapshotAccount, accountId);
  assertEquals(accepted?.accountId, accountId);
  assertEquals(accepted?.offerId, offerId);
  assertEquals("riderId" in (accepted ?? {}), false);
  assertEquals(declined?.accountId, accountId);
  assertEquals(declined?.reason, "Too far");
});

Deno.test("V1 heartbeat binds mission contact to the authenticated rider", async () => {
  let recorded: unknown;
  const response = await handleCourierDispatch(
    request({
      body: {
        operation: "v1Heartbeat",
        missionId,
        expectedVersion: 7,
        accountId: assignmentId,
      },
    }),
    dependencies({
      heartbeatV1Mission: (input) => {
        recorded = input;
        return Promise.resolve({ missionId, version: 8 });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, { accountId, missionId, expectedVersion: 7 });
});

Deno.test("V1 heartbeat rejects invalid mission/version before RPC", async () => {
  let calls = 0;
  const deps = dependencies({
    heartbeatV1Mission: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  assertEquals(
    (await handleCourierDispatch(
      request({ body: { operation: "v1Heartbeat", missionId: "bad", expectedVersion: 1 } }),
      deps,
    )).status,
    400,
  );
  assertEquals(
    (await handleCourierDispatch(
      request({ body: { operation: "v1Heartbeat", missionId, expectedVersion: 0 } }),
      deps,
    )).status,
    400,
  );
  assertEquals(calls, 0);
});

Deno.test("V1 pickup actions use server-owned actions and six-digit codes", async () => {
  const recorded: Record<string, unknown>[] = [];
  const deps = dependencies({
    advanceV1Mission: (input) => {
      recorded.push(input);
      return Promise.resolve({ responseBody: { currentMission: null }, responseStatus: 200 });
    },
  });
  const cases = [
    ["v1StartPickups", { missionId }],
    ["v1ArriveAtPickup", { missionId, stopId }],
    ["v1VerifyPickup", {
      missionId,
      stopId,
      accountedPackageCount: 2,
      verificationCode: "123456",
    }],
    ["v1CancelBeforePickup", { missionId, reason: "Cannot continue" }],
    ["v1ReportDeliveryProblem", { missionId, reason: "Custody problem" }],
    ["v1ReportCustomerUnreachable", { missionId, reason: "Recipient unreachable" }],
  ] as const;
  const actions = [
    "START_PICKUPS",
    "ARRIVE_PICKUP",
    "VERIFY_PICKUP",
    "CANCEL_BEFORE_PICKUP",
    "REPORT_DELIVERY_PROBLEM",
    "REPORT_CUSTOMER_UNREACHABLE",
  ];

  for (const [operation, payload] of cases) {
    const response = await handleCourierDispatch(
      request({
        body: { operation, action: "DELIVERED", riderId: assignmentId, ...payload },
      }),
      deps,
    );
    assertEquals(response.status, 200);
  }
  assertEquals(recorded.map((input) => input.action), actions);
  assertEquals(recorded[2].verificationCode, "123456");
  assertEquals(recorded[2].accountedPackageCount, 2);
  assertEquals(recorded.every((input) => input.accountId === accountId), true);
  assertEquals(recorded.every((input) => !("riderId" in input)), true);

  for (const code of [undefined, "1234", "12345a", "1234567"]) {
    const response = await handleCourierDispatch(
      request({
        body: {
          operation: "v1VerifyPickup",
          missionId,
          stopId,
          accountedPackageCount: 2,
          verificationCode: code,
        },
      }),
      deps,
    );
    await assertError(response, 400, "validation_failed");
  }
});

Deno.test("V1 final-delivery actions bind the rider, evidence path, and six-digit code", async () => {
  const recorded: Record<string, unknown>[] = [];
  const evidenceId = "66666666-6666-4666-8666-666666666666";
  const objectPath = `rider-delivery/${accountId}/${evidenceId}.jpg`;
  const deps = dependencies({
    advanceV1FinalDelivery: (input) => {
      recorded.push(input);
      return Promise.resolve({ responseBody: { currentMission: null }, responseStatus: 200 });
    },
  });
  const cases = [
    ["v1StartFinalDelivery", { missionId }],
    ["v1ArriveAtCustomer", { missionId }],
    ["v1AddDeliveryEvidence", { missionId, objectPath }],
    ["v1VerifyDelivery", { missionId, verificationCode: "654321" }],
  ] as const;
  const actions = [
    "START_FINAL_DELIVERY",
    "ARRIVE_CUSTOMER",
    "ADD_DELIVERY_EVIDENCE",
    "VERIFY_DELIVERY",
  ];

  for (const [operation, payload] of cases) {
    const response = await handleCourierDispatch(
      request({ body: { operation, accountId: assignmentId, action: "DELIVERED", ...payload } }),
      deps,
    );
    assertEquals(response.status, 200);
  }
  assertEquals(recorded.map((input) => input.action), actions);
  assertEquals(recorded.every((input) => input.accountId === accountId), true);
  assertEquals(recorded[2].objectPath, objectPath);
  assertEquals(recorded[3].verificationCode, "654321");
  assertEquals(recorded.every((input) => !("riderId" in input)), true);

  for (
    const invalidPath of [
      `rider-delivery/${assignmentId}/${evidenceId}.jpg`,
      `rider-delivery/${accountId}/nested/${evidenceId}.jpg`,
      `rider-delivery/${accountId}/not-a-uuid.jpg`,
    ]
  ) {
    const response = await handleCourierDispatch(
      request({ body: { operation: "v1AddDeliveryEvidence", missionId, objectPath: invalidPath } }),
      deps,
    );
    await assertError(response, 400, "validation_failed");
  }
  for (const verificationCode of [undefined, "12345", "12345a", "1234567"]) {
    const response = await handleCourierDispatch(
      request({ body: { operation: "v1VerifyDelivery", missionId, verificationCode } }),
      deps,
    );
    await assertError(response, 400, "validation_failed");
  }
});

Deno.test("V1 reverse-custody actions bind the rider, immutable evidence path, stops and codes", async () => {
  const recorded: Record<string, unknown>[] = [];
  const evidenceId = "66666666-6666-4666-8666-666666666666";
  const objectPath = `return-pickup/${accountId}/${evidenceId}.jpg`;
  const deps = dependencies({
    advanceV1ReturnMission: (input) => {
      recorded.push(input);
      return Promise.resolve({
        responseBody: { returnMission: { id: missionId, status: "RETURNING_TO_MERCHANTS" } },
        responseStatus: 200,
      });
    },
  });
  const cases = [
    ["v1ReturnArriveAtCustomer", { returnMissionId: missionId }],
    ["v1AddReturnEvidence", { returnMissionId: missionId, objectPath }],
    ["v1VerifyReturnPickup", { returnMissionId: missionId, verificationCode: "123456" }],
    ["v1ArriveAtReturnStop", { returnMissionId: missionId, returnStopId: stopId }],
    ["v1VerifyReturnReceipt", {
      returnMissionId: missionId,
      returnStopId: stopId,
      verificationCode: "654321",
    }],
  ] as const;
  for (const [operation, payload] of cases) {
    const response = await handleCourierDispatch(
      request({ body: { operation, ...payload } }),
      deps,
    );
    assertEquals(response.status, 200);
  }
  assertEquals(recorded.map((input) => input.action), [
    "ARRIVE_CUSTOMER",
    "ADD_RETURN_EVIDENCE",
    "VERIFY_RETURN_PICKUP",
    "ARRIVE_RETURN_STOP",
    "VERIFY_RETURN_RECEIPT",
  ]);
  assertEquals(recorded.every((input) => input.accountId === accountId), true);
  assertEquals(recorded[1].objectPath, objectPath);
  assertEquals(recorded[2].verificationCode, "123456");
  assertEquals(recorded[4].verificationCode, "654321");
  assertEquals(recorded[4].returnStopId, stopId);

  const wrongOwner = await handleCourierDispatch(
    request({
      body: {
        operation: "v1AddReturnEvidence",
        returnMissionId: missionId,
        objectPath: `return-pickup/${assignmentId}/${evidenceId}.jpg`,
      },
    }),
    deps,
  );
  await assertError(wrongOwner, 400, "validation_failed");
});

Deno.test("accept forwards only the authenticated partner and assignment", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleCourierDispatch(
    request({
      body: {
        operation: "acceptOffer",
        assignmentId: assignmentId.toUpperCase(),
        accountId: assignmentId,
        orderId: assignmentId,
        status: "accepted",
        respondBy: "2099-01-01T00:00:00Z",
      },
    }),
    dependencies({
      acceptOffer: (input) => {
        recorded = input;
        return Promise.resolve({
          responseBody: snapshot({ currentJob: offer() }),
          responseStatus: 200,
        });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.assignmentId, assignmentId);
  assertEquals(recorded?.idempotencyKey, "test-key");
  assertEquals(typeof recorded?.requestDigest, "string");
  assertEquals("orderId" in (recorded ?? {}), false);
  assertEquals("status" in (recorded ?? {}), false);
  assertEquals("respondBy" in (recorded ?? {}), false);
});

Deno.test("decline normalizes the optional partner reason", async () => {
  let recorded: Record<string, unknown> | undefined;
  const response = await handleCourierDispatch(
    request({
      body: {
        operation: "declineOffer",
        assignmentId,
        reason: "  Cannot reach   the store.  ",
      },
    }),
    dependencies({
      declineOffer: (input) => {
        recorded = input;
        return Promise.resolve({ responseBody: snapshot(), responseStatus: 200 });
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(recorded?.accountId, accountId);
  assertEquals(recorded?.assignmentId, assignmentId);
  assertEquals(recorded?.reason, "Cannot reach the store.");
});

Deno.test("job lifecycle operations map to server-owned actions", async () => {
  const cases = [
    ["startToStore", "start_to_store", null],
    ["arriveAtStore", "arrive_at_store", null],
    ["confirmPickup", "confirm_pickup", "1234"],
    ["startDelivery", "start_delivery", null],
    ["completeDelivery", "complete_delivery", "5678"],
  ] as const;

  for (const [operation, expectedAction, verificationCode] of cases) {
    let recorded: Record<string, unknown> | undefined;
    const response = await handleCourierDispatch(
      request({
        body: {
          operation,
          assignmentId,
          action: "complete_delivery",
          status: "delivered",
          orderId: assignmentId,
          verificationCode,
        },
      }),
      dependencies({
        advanceJob: (input) => {
          recorded = input;
          return Promise.resolve({ responseBody: snapshot(), responseStatus: 200 });
        },
      }),
    );

    assertEquals(response.status, 200);
    assertEquals(recorded?.accountId, accountId);
    assertEquals(recorded?.assignmentId, assignmentId);
    assertEquals(recorded?.action, expectedAction);
    assertEquals(recorded?.verificationCode, verificationCode);
    assertEquals("status" in (recorded ?? {}), false);
    assertEquals("orderId" in (recorded ?? {}), false);
  }
});

Deno.test("protected handoff transitions require a four-digit code", async () => {
  for (const operation of ["confirmPickup", "completeDelivery"]) {
    for (const verificationCode of [undefined, "123", "12a4", "12345"]) {
      const response = await handleCourierDispatch(
        request({ body: { operation, assignmentId, verificationCode } }),
        dependencies(),
      );
      await assertError(response, 400, "validation_failed");
    }
  }
});

Deno.test("ordinary completion rejects tobacco handoff", async () => {
  let advanceCalls = 0;
  const response = await handleCourierDispatch(
    request({
      body: { operation: "completeDelivery", assignmentId, verificationCode: "5678" },
    }),
    dependencies({
      getAssignmentControlledScope: () => Promise.resolve("tobacco"),
      advanceJob: () => {
        advanceCalls += 1;
        return Promise.resolve({ responseBody: snapshot(), responseStatus: 200 });
      },
    }),
  );

  assertEquals(advanceCalls, 0);
  await assertError(response, 409, "restricted_handoff_required");
});

Deno.test("offer mutations reject invalid ids, reasons, and missing idempotency", async () => {
  const invalidID = await handleCourierDispatch(
    request({ body: { operation: "acceptOffer", assignmentId: "not-a-uuid" } }),
    dependencies(),
  );
  await assertError(invalidID, 400, "validation_failed");

  const invalidReason = await handleCourierDispatch(
    request({
      body: { operation: "declineOffer", assignmentId, reason: "x".repeat(301) },
    }),
    dependencies(),
  );
  await assertError(invalidReason, 400, "validation_failed");

  const missingKey = await handleCourierDispatch(
    request({
      body: { operation: "acceptOffer", assignmentId },
      idempotencyKey: "",
    }),
    dependencies(),
  );
  await assertError(missingKey, 400, "validation_failed");
});

Deno.test("courier dispatch dependency failures do not leak details", async () => {
  const response = await handleCourierDispatch(
    request(),
    dependencies({
      getPartnerSnapshot: () => Promise.reject(new Error("private assignment row leaked")),
    }),
  );
  const body = await response.json();
  assertEquals(response.status, 500);
  assertEquals(body.error.code, "internal_error");
  assertEquals(JSON.stringify(body).includes("private assignment"), false);
});

function dependencies(
  overrides: Partial<CourierDispatchDependencies> = {},
): CourierDispatchDependencies {
  return {
    authenticateBearer: () => Promise.resolve({ accountId }),
    getPartnerSnapshot: () => Promise.resolve({ responseBody: snapshot(), responseStatus: 200 }),
    getAssignmentControlledScope: () => Promise.resolve("general"),
    acceptOffer: () =>
      Promise.resolve({ responseBody: snapshot({ currentJob: offer() }), responseStatus: 200 }),
    declineOffer: () => Promise.resolve({ responseBody: snapshot(), responseStatus: 200 }),
    advanceJob: () => Promise.resolve({ responseBody: snapshot(), responseStatus: 200 }),
    getV1PartnerSnapshot: () =>
      Promise.resolve({ responseBody: { offer: null, currentMission: null }, responseStatus: 200 }),
    acceptV1Offer: () =>
      Promise.resolve({ responseBody: { offer: null, currentMission: null }, responseStatus: 200 }),
    declineV1Offer: () =>
      Promise.resolve({ responseBody: { offer: null, currentMission: null }, responseStatus: 200 }),
    heartbeatV1Mission: () => Promise.resolve({ missionId, version: 2 }),
    advanceV1Mission: () =>
      Promise.resolve({ responseBody: { offer: null, currentMission: null }, responseStatus: 200 }),
    advanceV1FinalDelivery: () =>
      Promise.resolve({ responseBody: { offer: null, currentMission: null }, responseStatus: 200 }),
    advanceV1ReturnMission: () =>
      Promise.resolve({ responseBody: { returnStatus: "CUSTOMER_PICKUP" }, responseStatus: 200 }),
    ...overrides,
  };
}

function snapshot(overrides: Record<string, unknown> = {}) {
  return { offer: null, currentJob: null, ...overrides };
}

function offer() {
  return {
    assignmentId,
    orderId: "33333333-3333-4333-8333-333333333333",
    assignmentStatus: "offered",
    orderStatus: "ready",
    offeredAt: "2026-07-16T12:00:00Z",
    respondBy: "2026-07-16T12:01:00Z",
    acceptedAt: null,
    distanceMeters: 125,
    store: {
      storeId: "44444444-4444-4444-8444-444444444444",
      name: "Test Store",
      address: "1 Main Road",
      pickup: { latitude: 12.68, longitude: 78.62 },
    },
    dropoff: { latitude: 12.69, longitude: 78.63 },
    items: [],
  };
}

function request(
  options: {
    authorization?: string | null;
    body?: unknown;
    idempotencyKey?: string;
  } = {},
) {
  const headers = new Headers({ "content-type": "application/json" });
  if (options.authorization !== null) {
    headers.set("authorization", options.authorization ?? "Bearer valid");
  }
  headers.set("X-Idempotency-Key", options.idempotencyKey ?? "test-key");
  return new Request("http://localhost/functions/v1/courier-dispatch", {
    method: "POST",
    headers,
    body: JSON.stringify(options.body ?? { operation: "partnerSnapshot" }),
  });
}

async function assertError(response: Response, status: number, code: string) {
  assertEquals(response.status, status);
  assertEquals((await response.json()).error.code, code);
}
