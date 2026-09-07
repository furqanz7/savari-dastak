import { assertEquals } from "jsr:@std/assert";
import { V1RequestError } from "../../_shared/v1-rpc.ts";
import { handleV1Orders, type V1OrderDependencies } from "../../dastak-v1-orders/handler.ts";

Deno.test("admin cancellation binds authenticated identity and forwards audited intent", async () => {
  let recorded: unknown;
  const response = await handleV1Orders(request({
    operation: "adminCancelOrder", orderId, reason: "  Owner requested cancellation  ",
    expectedVersion: 5, actorId: "untrusted", status: "DELIVERED", stockQuantity: 999,
  }, "admin-cancel-once"), dependencies({
    adminCancelOrder: (input) => {
      recorded = input;
      return Promise.resolve({ orderId, status: "CANCELLED", version: 6 });
    },
  }));
  assertEquals(response.status, 200);
  assertEquals(recorded, { accessToken: actor.accessToken, orderId,
    reason: "Owner requested cancellation", expectedVersion: 5, idempotencyKey: "admin-cancel-once" });
});

Deno.test("admin cancellation rejects invalid identity reason version and missing retry key", async () => {
  let calls = 0;
  const deps = dependencies({ adminCancelOrder: () => { calls += 1; return Promise.resolve({}); } });
  const valid = { operation: "adminCancelOrder", orderId, reason: "Owner requested cancellation", expectedVersion: 5 };
  for (const body of [
    { ...valid, orderId: "bad" }, { ...valid, reason: "short" },
    { ...valid, reason: "x".repeat(501) }, { ...valid, expectedVersion: 0 },
    { ...valid, expectedVersion: 1.5 }, { ...valid, expectedVersion: null },
  ]) {
    assertEquals((await handleV1Orders(request(body, "cancel-key"), deps)).status, 400);
  }
  assertEquals((await handleV1Orders(request(valid), deps)).status, 400);
  assertEquals(calls, 0);
});

Deno.test("legacy customer builds can read cancelled orders without changing canonical data", async () => {
  const cancelled = { id: orderId, status: "CANCELLED", version: 6, launchPayment: { state: "NOT_APPLICABLE" } };
  const deps = dependencies({ getOrder: () => Promise.resolve(cancelled),
    listOrders: () => Promise.resolve({ orders: [cancelled, orderSnapshot], nextCursor: null }) });
  const single = await body(await handleV1Orders(request({ operation: "get", orderId }), deps));
  assertEquals(single, { ...cancelled, status: "CANCELLED_PREPAYMENT", canonicalStatus: "CANCELLED" });
  const list = await body(await handleV1Orders(request({ operation: "list" }), deps));
  assertEquals(list, { orders: [single, orderSnapshot], nextCursor: null });
  assertEquals(cancelled.status, "CANCELLED");
});

Deno.test("updated customer builds receive canonical cancellation status", async () => {
  const cancelled = { id: orderId, status: "CANCELLED", version: 6 };
  const deps = dependencies({ getOrder: () => Promise.resolve(cancelled),
    listOrders: () => Promise.resolve({ orders: [cancelled], nextCursor: null }) });
  assertEquals(await body(await handleV1Orders(request({ operation: "get", orderId, supportsConfirmedCancellation: true }), deps)), cancelled);
  assertEquals(await body(await handleV1Orders(request({ operation: "list", supportsConfirmedCancellation: true }), deps)),
    { orders: [cancelled], nextCursor: null });
});

Deno.test("V1 orders serves CORS preflight before authentication", async () => {
  let authCalls = 0;
  const response = await handleV1Orders(
    new Request(url, { method: "OPTIONS" }),
    dependencies({
      authenticateBearer: () => {
        authCalls += 1;
        return Promise.resolve(actor);
      },
    }),
  );
  assertEquals(response.status, 204);
  assertEquals(authCalls, 0);
});

Deno.test("V1 submit forwards no client price or merchant identity", async () => {
  let recorded: unknown;
  const order = {
    deliveryAddress: { line1: "1 Launch Road", countryCode: "IN" },
    lines: [{ lineType: "RETAIL_SKU", skuId, quantity: 2 }],
  };
  const response = await handleV1Orders(
    request({ operation: "submit", expectedVersion: 0, order }, "submit-1"),
    dependencies({
      submitOrder: (input) => {
        recorded = input;
        return Promise.resolve(orderSnapshot);
      },
    }),
  );
  assertEquals(response.status, 201);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    idempotencyKey: "submit-1",
    expectedVersion: 0,
    order,
  });
});

Deno.test("V1 submit requires expected version zero and idempotency", async () => {
  let calls = 0;
  const deps = dependencies({
    submitOrder: () => {
      calls += 1;
      return Promise.resolve(orderSnapshot);
    },
  });
  const missingKey = await handleV1Orders(
    request({ operation: "submit", expectedVersion: 0, order: {} }),
    deps,
  );
  const wrongVersion = await handleV1Orders(
    request({ operation: "submit", expectedVersion: 1, order: {} }, "submit-2"),
    deps,
  );
  assertEquals(missingKey.status, 400);
  assertEquals(wrongVersion.status, 400);
  assertEquals(calls, 0);
});

Deno.test("V1 Restaurant confirmation forwards exact soft-capacity decision data", async () => {
  let recorded: unknown;
  const response = await handleV1Orders(
    request({
      operation: "respondRestaurantRequest",
      requestId: orderId,
      response: "CONFIRM",
      promisedPrepMinutes: 25,
      expectedVersion: 2,
    }, "restaurant-confirm-1"),
    dependencies({
      respondRestaurantRequest: (input) => {
        recorded = input;
        return Promise.resolve({ id: orderId, status: "CONFIRMED" });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    requestId: orderId,
    response: "CONFIRM",
    promisedPrepMinutes: 25,
    reason: null,
    expectedVersion: 2,
    idempotencyKey: "restaurant-confirm-1",
  });
});

Deno.test("V1 Restaurant decline requires an audited reason", async () => {
  let calls = 0;
  const response = await handleV1Orders(
    request({
      operation: "respondRestaurantRequest",
      requestId: orderId,
      response: "DECLINE",
      reason: "x",
      expectedVersion: 1,
    }, "restaurant-decline-1"),
    dependencies({
      respondRestaurantRequest: () => {
        calls += 1;
        return Promise.resolve({});
      },
    }),
  );
  assertEquals(response.status, 400);
  assertEquals(calls, 0);
});

Deno.test("V1 customer order list forwards a complete keyset cursor", async () => {
  let recorded: unknown;
  const response = await handleV1Orders(
    request({
      operation: "list",
      limit: 30,
      cursor: { createdAt: "2026-08-22T10:00:00Z", orderId },
    }),
    dependencies({
      listOrders: (input) => {
        recorded = input;
        return Promise.resolve({ orders: [], nextCursor: null });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    limit: 30,
    beforeCreatedAt: "2026-08-22T10:00:00Z",
    beforeOrderId: orderId,
  });
});

Deno.test("V1 customer order list rejects malformed cursors and limits", async () => {
  let calls = 0;
  const deps = dependencies({
    listOrders: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  const cursor = await handleV1Orders(
    request({
      operation: "list",
      cursor: { createdAt: "not-a-date", orderId },
    }),
    deps,
  );
  const limit = await handleV1Orders(
    request({ operation: "list", limit: 101 }),
    deps,
  );
  assertEquals(cursor.status, 400);
  assertEquals(limit.status, 400);
  assertEquals(calls, 0);
});

Deno.test("V1 get and cancel accept only validated order identity", async () => {
  let getInput: unknown;
  let cancelInput: unknown;
  const deps = dependencies({
    getOrder: (input) => {
      getInput = input;
      return Promise.resolve(orderSnapshot);
    },
    cancelOrder: (input) => {
      cancelInput = input;
      return Promise.resolve({
        ...orderSnapshot,
        status: "CANCELLED_PREPAYMENT",
      });
    },
  });
  const getResponse = await handleV1Orders(
    request({ operation: "get", orderId }),
    deps,
  );
  const cancelResponse = await handleV1Orders(
    request({ operation: "cancel", orderId, expectedVersion: 2 }, "cancel-1"),
    deps,
  );
  assertEquals(getResponse.status, 200);
  assertEquals(cancelResponse.status, 200);
  assertEquals(getInput, { accessToken: actor.accessToken, orderId });
  assertEquals(cancelInput, {
    accessToken: actor.accessToken,
    orderId,
    idempotencyKey: "cancel-1",
    expectedVersion: 2,
  });
});

Deno.test("V1 launch payment commitment sends only order authority and optimistic state", async () => {
  let recorded: unknown;
  const response = await handleV1Orders(
    request({
      operation: "commitLaunchPayment",
      orderId,
      expectedVersion: 7,
      amountPaise: 1,
      currencyCode: "USD",
      optionCode: "CLIENT_CONTROLLED",
    }, "launch-commit-1"),
    dependencies({
      commitLaunchPayment: (input) => {
        recorded = input;
        return Promise.resolve({
          ...orderSnapshot,
          status: "PREPARING",
          launchPayment: { state: "PAYMENT_DUE_AT_DELIVERY" },
        });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    orderId,
    idempotencyKey: "launch-commit-1",
    expectedVersion: 7,
  });
});

Deno.test("V1 launch payment commitment rejects missing idempotency and stale-shaped input", async () => {
  let calls = 0;
  const deps = dependencies({
    commitLaunchPayment: () => {
      calls += 1;
      return Promise.resolve(orderSnapshot);
    },
  });
  const missingKey = await handleV1Orders(
    request({ operation: "commitLaunchPayment", orderId, expectedVersion: 2 }),
    deps,
  );
  const invalidVersion = await handleV1Orders(
    request(
      { operation: "commitLaunchPayment", orderId, expectedVersion: 0 },
      "launch-bad",
    ),
    deps,
  );
  assertEquals([missingKey.status, invalidVersion.status], [400, 400]);
  assertEquals(calls, 0);
});

Deno.test("V1 Admin access snapshot and Executive assignment forward only validated authority", async () => {
  const recorded: Record<string, unknown> = {};
  const deps = dependencies({
    getAdminAccess: (input) => {
      recorded.snapshot = input;
      return Promise.resolve({
        role: "SUPERADMIN",
        canManageAdmins: true,
        slots: [],
      });
    },
    setExecutiveAdmin: (input) => {
      recorded.assignment = input;
      return Promise.resolve({ slot: 1, role: "EXECUTIVE_ADMIN", version: 2 });
    },
  });
  const snapshot = await handleV1Orders(
    request({ operation: "adminAccess" }),
    deps,
  );
  const assignment = await handleV1Orders(
    request({
      operation: "setExecutiveAdmin",
      slot: 1,
      email: "  executive@example.com  ",
      expectedVersion: 1,
      reason: "  Assign Executive Admin from the protected workspace.  ",
      accountId: "client-cannot-select-account",
    }),
    deps,
  );
  assertEquals([snapshot.status, assignment.status], [200, 200]);
  assertEquals(recorded.snapshot, { accessToken: actor.accessToken });
  assertEquals(recorded.assignment, {
    accessToken: actor.accessToken,
    slot: 1,
    email: "executive@example.com",
    expectedVersion: 1,
    reason: "Assign Executive Admin from the protected workspace.",
  });
});

Deno.test("V1 Admin command center and connected network preserve authenticated filters and cursors", async () => {
  const recorded: Record<string, unknown> = {};
  const deps = dependencies({
    getAdminCommandCenter: (input) => {
      recorded.commandCenter = input;
      return Promise.resolve({ actionQueue: {}, commerce: {} });
    },
    getAdminNetworkPage: (input) => {
      recorded.network = input;
      return Promise.resolve({ people: [], hasMore: false, nextCursor: null });
    },
  });
  const commandCenter = await handleV1Orders(
    request({
      operation: "adminCommandCenter",
      accountId: "client-cannot-select-account",
    }),
    deps,
  );
  const network = await handleV1Orders(
    request({
      operation: "adminNetworkPage",
      query: "  Furqan   Khan  ",
      persona: "MERCHANT",
      state: "ACTIVE",
      limit: 40,
      cursor: { updatedAt: "2026-08-31T12:34:56.000Z", accountId: orderId },
      rawEvidence: true,
    }),
    deps,
  );

  assertEquals([commandCenter.status, network.status], [200, 200]);
  assertEquals(recorded.commandCenter, { accessToken: actor.accessToken });
  assertEquals(recorded.network, {
    accessToken: actor.accessToken,
    query: "Furqan Khan",
    persona: "MERCHANT",
    state: "ACTIVE",
    limit: 40,
    afterUpdatedAt: "2026-08-31T12:34:56.000Z",
    afterAccountId: orderId,
  });
});

Deno.test("V1 Admin connected network rejects unsupported filters and incomplete cursors", async () => {
  let calls = 0;
  const deps = dependencies({
    getAdminNetworkPage: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  const persona = await handleV1Orders(
    request({ operation: "adminNetworkPage", persona: "OWNER" }),
    deps,
  );
  const state = await handleV1Orders(
    request({ operation: "adminNetworkPage", state: "SUSPENDED" }),
    deps,
  );
  const cursor = await handleV1Orders(
    request({
      operation: "adminNetworkPage",
      cursor: { updatedAt: "2026-08-31T12:34:56.000Z" },
    }),
    deps,
  );
  const limit = await handleV1Orders(
    request({ operation: "adminNetworkPage", limit: 101 }),
    deps,
  );
  assertEquals([
    persona.status,
    state.status,
    cursor.status,
    limit.status,
    calls,
  ], [
    400,
    400,
    400,
    400,
    0,
  ]);
});

Deno.test("V1 Executive assignment rejects extra slots and malformed email shape", async () => {
  let calls = 0;
  const deps = dependencies({
    setExecutiveAdmin: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  const extraSlot = await handleV1Orders(
    request({
      operation: "setExecutiveAdmin",
      slot: 3,
      email: "third@example.com",
      expectedVersion: 1,
      reason: "Invalid third slot",
    }),
    deps,
  );
  const malformed = await handleV1Orders(
    request({
      operation: "setExecutiveAdmin",
      slot: 1,
      email: { address: "not-client-authority" },
      expectedVersion: 1,
      reason: "Invalid email shape",
    }),
    deps,
  );
  assertEquals([extraSlot.status, malformed.status, calls], [400, 400, 0]);
});

Deno.test("V1 merchant opportunities preserve scope, quantity, and optimistic state", async () => {
  let acceptInput: unknown;
  let declineInput: unknown;
  const deps = dependencies({
    acceptMerchantOpportunity: (input) => {
      acceptInput = input;
      return Promise.resolve({ id: orderId, status: "PROVISIONALLY_ACCEPTED" });
    },
    declineMerchantOpportunity: (input) => {
      declineInput = input;
      return Promise.resolve({ id: orderId, status: "DECLINED" });
    },
  });
  const accepted = await handleV1Orders(
    request({
      operation: "acceptMerchantOpportunity",
      opportunityId: orderId,
      requestScope: "REQUESTED_SUBSET",
      expectedVersion: 1,
      promisedPrepMinutes: 15,
    }, "merchant-accept"),
    deps,
  );
  const declined = await handleV1Orders(
    request({
      operation: "declineMerchantOpportunity",
      opportunityId: orderId,
      requestScope: "FULL_BASKET",
      expectedVersion: 2,
    }, "merchant-decline"),
    deps,
  );
  assertEquals(accepted.status, 200);
  assertEquals(declined.status, 200);
  assertEquals(acceptInput, {
    accessToken: actor.accessToken,
    opportunityId: orderId,
    requestScope: "REQUESTED_SUBSET",
    expectedVersion: 1,
    promisedPrepMinutes: 15,
    idempotencyKey: "merchant-accept",
  });
  assertEquals(declineInput, {
    accessToken: actor.accessToken,
    opportunityId: orderId,
    requestScope: "FULL_BASKET",
    expectedVersion: 2,
    idempotencyKey: "merchant-decline",
  });
});

Deno.test("V1 execution trace is a permission-checked authenticated RPC surface", async () => {
  let listInput: unknown;
  let traceInput: unknown;
  let healthInput: unknown;
  const deps = dependencies({
    listAdminExecutionOrders: (input) => {
      listInput = input;
      return Promise.resolve({ orders: [] });
    },
    getAdminExecutionTrace: (input) => {
      traceInput = input;
      return Promise.resolve({ order: { id: orderId } });
    },
    getAdminSystemHealth: (input) => {
      healthInput = input;
      return Promise.resolve({ healthy: true });
    },
  });
  const list = await handleV1Orders(
    request({ operation: "adminExecutionOrders", limit: 25 }),
    deps,
  );
  const trace = await handleV1Orders(
    request({ operation: "adminExecutionTrace", orderId }),
    deps,
  );
  const health = await handleV1Orders(
    request({ operation: "adminSystemHealth" }),
    deps,
  );
  assertEquals(list.status, 200);
  assertEquals(trace.status, 200);
  assertEquals(health.status, 200);
  assertEquals(listInput, { accessToken: actor.accessToken, limit: 25 });
  assertEquals(traceInput, { accessToken: actor.accessToken, orderId });
  assertEquals(healthInput, { accessToken: actor.accessToken });
});

Deno.test("V1 operational safety commands validate and preserve authenticated authority", async () => {
  let snapshotInput: unknown;
  let escalationInput: unknown;
  let pauseInput: unknown;
  const deps = dependencies({
    getAdminOperationalSafety: (input) => {
      snapshotInput = input;
      return Promise.resolve({ pauses: [], riderEscalations: [] });
    },
    manageRiderEscalation: (input) => {
      escalationInput = input;
      return Promise.resolve({ missionId: orderId });
    },
    setOperationalPause: (input) => {
      pauseInput = input;
      return Promise.resolve({ targetId: orderId });
    },
  });
  assertEquals(
    (await handleV1Orders(
      request({ operation: "adminOperationalSafety" }),
      deps,
    )).status,
    200,
  );
  assertEquals(
    (await handleV1Orders(
      request({
        operation: "manageRiderEscalation",
        missionId: orderId,
        action: "RELEASE_REMATCH",
        reason: "Rider is unresponsive before pickup",
        expectedVersion: 4,
      }, "escalation-1"),
      deps,
    )).status,
    200,
  );
  assertEquals(
    (await handleV1Orders(
      request({
        operation: "setOperationalPause",
        scope: "ZONE_RETAIL",
        targetId: orderId,
        active: true,
        reason: "Safety pause",
        expectedVersion: 0,
      }, "pause-1"),
      deps,
    )).status,
    200,
  );
  assertEquals(snapshotInput, { accessToken: actor.accessToken });
  assertEquals(escalationInput, {
    accessToken: actor.accessToken,
    missionId: orderId,
    action: "RELEASE_REMATCH",
    reason: "Rider is unresponsive before pickup",
    expectedVersion: 4,
    idempotencyKey: "escalation-1",
  });
  assertEquals(pauseInput, {
    accessToken: actor.accessToken,
    scope: "ZONE_RETAIL",
    targetId: orderId,
    active: true,
    reason: "Safety pause",
    expectedVersion: 0,
    idempotencyKey: "pause-1",
  });
});

Deno.test("V1 operational safety rejects generic state edits and weak reasons", async () => {
  let calls = 0;
  const deps = dependencies({
    manageRiderEscalation: () => {
      calls += 1;
      return Promise.resolve({});
    },
    setOperationalPause: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  assertEquals(
    (await handleV1Orders(
      request({
        operation: "manageRiderEscalation",
        missionId: orderId,
        action: "FORCE_STATE",
        reason: "invalid",
        expectedVersion: 1,
      }, "bad-1"),
      deps,
    )).status,
    400,
  );
  assertEquals(
    (await handleV1Orders(
      request({
        operation: "setOperationalPause",
        scope: "EVERYTHING",
        targetId: orderId,
        active: true,
        reason: "no",
        expectedVersion: 0,
      }, "bad-2"),
      deps,
    )).status,
    400,
  );
  assertEquals(calls, 0);
});

Deno.test("V1 exceptional handoff preserves evidence, reason, version and authenticated boundary", async () => {
  const evidenceId = "44444444-4444-4444-8444-444444444444";
  let recorded: unknown;
  const response = await handleV1Orders(
    request({
      operation: "authorizeExceptionalDeliveryHandoff",
      missionId: orderId,
      deliveryEvidenceId: evidenceId,
      reason: "  Operations reviewed immutable rider evidence.  ",
      expectedMissionVersion: 9,
      actorId: skuId,
    }, "override-1"),
    dependencies({
      authorizeExceptionalDeliveryHandoff: (input) => {
        recorded = input;
        return Promise.resolve({ verificationStatus: "OVERRIDDEN" });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(recorded, {
    accessToken: actor.accessToken,
    missionId: orderId,
    deliveryEvidenceId: evidenceId,
    reason: "Operations reviewed immutable rider evidence.",
    expectedMissionVersion: 9,
    idempotencyKey: "override-1",
  });

  const invalid = await handleV1Orders(
    request({
      operation: "authorizeExceptionalDeliveryHandoff",
      missionId: orderId,
      deliveryEvidenceId: evidenceId,
      reason: "too short",
      expectedMissionVersion: 9,
    }, "override-invalid"),
    dependencies(),
  );
  assertEquals(invalid.status, 400);
});

Deno.test("V1 merchant preparation commands preserve package, evidence, version, and idempotency", async () => {
  const recorded: Record<string, unknown> = {};
  const deps = dependencies({
    listMerchantFulfilments: (input) => {
      recorded.list = input;
      return Promise.resolve({ fulfilments: [] });
    },
    declareFulfilmentPackages: (input) => {
      recorded.packages = input;
      return Promise.resolve({ id: orderId, version: 4 });
    },
    addFulfilmentReadyEvidence: (input) => {
      recorded.evidence = input;
      return Promise.resolve({ id: orderId, version: 5 });
    },
    markFulfilmentReady: (input) => {
      recorded.ready = input;
      return Promise.resolve({ id: orderId, status: "READY", version: 6 });
    },
    reportFulfilmentProblem: (input) => {
      recorded.problem = input;
      return Promise.resolve({ id: orderId, status: "READY", version: 7 });
    },
  });
  const list = await handleV1Orders(
    request({ operation: "merchantFulfilments", limit: 30 }),
    deps,
  );
  const packages = await handleV1Orders(
    request({
      operation: "declareFulfilmentPackages",
      fulfilmentId: orderId,
      packageCount: 3,
      expectedVersion: 3,
    }, "packages-1"),
    deps,
  );
  const evidence = await handleV1Orders(
    request({
      operation: "addFulfilmentReadyEvidence",
      fulfilmentId: orderId,
      packageId: null,
      objectPath: `merchant-ready/${actor.accountId}/${skuId}.jpg`,
      expectedVersion: 4,
    }, "evidence-1"),
    deps,
  );
  const ready = await handleV1Orders(
    request({
      operation: "markFulfilmentReady",
      fulfilmentId: orderId,
      expectedVersion: 5,
    }, "ready-1"),
    deps,
  );
  const problem = await handleV1Orders(
    request({
      operation: "reportFulfilmentProblem",
      fulfilmentId: orderId,
      reason: "Package label needs operator review",
      expectedVersion: 6,
    }, "problem-1"),
    deps,
  );

  assertEquals([
    list.status,
    packages.status,
    evidence.status,
    ready.status,
    problem.status,
  ], [
    200,
    200,
    200,
    200,
    200,
  ]);
  assertEquals(recorded.list, { accessToken: actor.accessToken, limit: 30 });
  assertEquals(recorded.packages, {
    accessToken: actor.accessToken,
    fulfilmentId: orderId,
    packageCount: 3,
    expectedVersion: 3,
    idempotencyKey: "packages-1",
  });
  assertEquals(recorded.evidence, {
    accessToken: actor.accessToken,
    fulfilmentId: orderId,
    packageId: null,
    objectPath: `merchant-ready/${actor.accountId}/${skuId}.jpg`,
    expectedVersion: 4,
    idempotencyKey: "evidence-1",
  });
  assertEquals(recorded.ready, {
    accessToken: actor.accessToken,
    fulfilmentId: orderId,
    expectedVersion: 5,
    idempotencyKey: "ready-1",
  });
  assertEquals(recorded.problem, {
    accessToken: actor.accessToken,
    fulfilmentId: orderId,
    reason: "Package label needs operator review",
    expectedVersion: 6,
    idempotencyKey: "problem-1",
  });
});

Deno.test("V1 merchant preparation rejects invalid package, evidence, and problem payloads", async () => {
  let calls = 0;
  const deps = dependencies({
    declareFulfilmentPackages: () => {
      calls += 1;
      return Promise.resolve({});
    },
    addFulfilmentReadyEvidence: () => {
      calls += 1;
      return Promise.resolve({});
    },
    reportFulfilmentProblem: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  const packages = await handleV1Orders(
    request({
      operation: "declareFulfilmentPackages",
      fulfilmentId: orderId,
      packageCount: 0,
      expectedVersion: 1,
    }, "bad-packages"),
    deps,
  );
  const evidence = await handleV1Orders(
    request({
      operation: "addFulfilmentReadyEvidence",
      fulfilmentId: orderId,
      packageId: "invalid",
      objectPath: "x",
      expectedVersion: 1,
    }, "bad-evidence"),
    deps,
  );
  const problem = await handleV1Orders(
    request({
      operation: "reportFulfilmentProblem",
      fulfilmentId: orderId,
      reason: "x",
      expectedVersion: 1,
    }, "bad-problem"),
    deps,
  );
  assertEquals([packages.status, evidence.status, problem.status], [
    400,
    400,
    400,
  ]);
  assertEquals(calls, 0);
});

Deno.test("V1 launch-failure commands preserve exact identity, evidence and optimistic versions", async () => {
  const recorded: Record<string, unknown> = {};
  const evidencePath = `customer-issue/${actor.accountId}/${skuId}.jpg`;
  const deps = dependencies({
    reportExactSkuFailure: (input) => {
      recorded.recovery = input;
      return Promise.resolve({ status: "SEARCHING_EXACT_SKU" });
    },
    reportCustomerIssue: (input) => {
      recorded.issue = input;
      return Promise.resolve({ status: "OPEN" });
    },
    decideCustomerIssue: (input) => {
      recorded.decision = input;
      return Promise.resolve({ returnStatus: "RIDER_SEARCH" });
    },
    manageDeliveryRecovery: (input) => {
      recorded.deliveryRecovery = input;
      return Promise.resolve({ recoveryStatus: "RESOLVED" });
    },
  });

  const recovery = await handleV1Orders(
    request({
      operation: "reportExactSkuFailure",
      fulfilmentId: orderId,
      orderLineId: skuId,
      reason: "  Exact item failed physical confirmation.  ",
      expectedVersion: 7,
    }, "recovery-once"),
    deps,
  );
  const issue = await handleV1Orders(
    request({
      operation: "reportCustomerIssue",
      orderId,
      orderLineId: skuId,
      category: "DAMAGED",
      description: "  Seal was damaged at handoff.  ",
      objectPath: evidencePath,
      contentType: "image/jpeg",
    }, "issue-once"),
    deps,
  );
  const decision = await handleV1Orders(
    request({
      operation: "decideCustomerIssue",
      issueId: orderId,
      decision: "PHYSICAL_RETURN",
      refundAmountPaise: 900,
      faultSource: "MERCHANT",
      returnPackageCount: 1,
      reason: "  Physical return approved after evidence review.  ",
      expectedVersion: 2,
    }, "decision-once"),
    deps,
  );
  const deliveryRecovery = await handleV1Orders(
    request({
      operation: "manageDeliveryRecovery",
      recoveryCaseId: orderId,
      action: "RESUME_DELIVERY",
      faultSource: "CUSTOMER",
      refundAmountPaise: null,
      correctedAddress: { line1: "10 Corrected Road" },
      reason: "  Customer confirmed a minor address correction.  ",
      expectedVersion: 3,
    }, "delivery-recovery-once"),
    deps,
  );

  assertEquals([
    recovery.status,
    issue.status,
    decision.status,
    deliveryRecovery.status,
  ], [
    200,
    201,
    200,
    200,
  ]);
  assertEquals(recorded.recovery, {
    accessToken: actor.accessToken,
    fulfilmentId: orderId,
    orderLineId: skuId,
    reason: "Exact item failed physical confirmation.",
    expectedVersion: 7,
    idempotencyKey: "recovery-once",
  });
  assertEquals(recorded.issue, {
    accessToken: actor.accessToken,
    orderId,
    orderLineId: skuId,
    category: "DAMAGED",
    description: "Seal was damaged at handoff.",
    objectPath: evidencePath,
    contentType: "image/jpeg",
    idempotencyKey: "issue-once",
  });
  assertEquals(recorded.decision, {
    accessToken: actor.accessToken,
    issueId: orderId,
    decision: "PHYSICAL_RETURN",
    refundAmountPaise: 900,
    faultSource: "MERCHANT",
    returnPackageCount: 1,
    reason: "Physical return approved after evidence review.",
    expectedVersion: 2,
    idempotencyKey: "decision-once",
  });
  assertEquals(recorded.deliveryRecovery, {
    accessToken: actor.accessToken,
    recoveryCaseId: orderId,
    action: "RESUME_DELIVERY",
    faultSource: "CUSTOMER",
    refundAmountPaise: null,
    correctedAddress: { line1: "10 Corrected Road" },
    reason: "Customer confirmed a minor address correction.",
    expectedVersion: 3,
    idempotencyKey: "delivery-recovery-once",
  });
});

Deno.test("V1 refund and settlement controls reject malformed financial input before RPC", async () => {
  let calls = 0;
  const deps = dependencies({
    decideCustomerIssue: () => {
      calls += 1;
      return Promise.resolve({});
    },
    settleEntry: () => {
      calls += 1;
      return Promise.resolve({});
    },
    manageDeliveryRecovery: () => {
      calls += 1;
      return Promise.resolve({});
    },
  });
  const badRefund = await handleV1Orders(
    request({
      operation: "decideCustomerIssue",
      issueId: orderId,
      decision: "PHYSICAL_RETURN",
      refundAmountPaise: -1,
      faultSource: "MERCHANT",
      returnPackageCount: 0,
      reason: "Invalid financial decision",
      expectedVersion: 1,
    }, "bad-refund"),
    deps,
  );
  const badSettlement = await handleV1Orders(
    request({
      operation: "settleEntry",
      settlementEntryId: orderId,
      settlementReference: "",
      expectedVersion: 1,
    }, "bad-settlement"),
    deps,
  );
  const badRecovery = await handleV1Orders(
    request({
      operation: "manageDeliveryRecovery",
      recoveryCaseId: orderId,
      action: "RESUME_DELIVERY",
      faultSource: "CUSTOMER",
      reason: "too short",
      expectedVersion: 1,
    }, "bad-recovery"),
    deps,
  );
  assertEquals([badRefund.status, badSettlement.status, badRecovery.status], [
    400,
    400,
    400,
  ]);
  assertEquals(calls, 0);
});

Deno.test("V1 orders maps stale state without leaking database details", async () => {
  const response = await handleV1Orders(
    request({ operation: "get", orderId }),
    dependencies({
      getOrder: () =>
        Promise.reject(
          new V1RequestError(
            409,
            "stale_version",
            "This information changed. Refresh and try again.",
          ),
        ),
    }),
  );
  assertEquals(response.status, 409);
  assertEquals((await body(response)).error.code, "stale_version");
});

Deno.test("V1 orders rejects missing bearer authorization", async () => {
  const response = await handleV1Orders(
    request({ operation: "list" }, undefined, ""),
    dependencies(),
  );
  assertEquals(response.status, 401);
});

const url = "http://localhost/functions/v1/dastak-v1-orders";
const skuId = "11111111-1111-4111-8111-111111111111";
const orderId = "22222222-2222-4222-8222-222222222222";
const actor = {
  accountId: "33333333-3333-4333-8333-333333333333",
  accessToken: "verified-access-token",
};
const orderSnapshot = { id: orderId, status: "MATCHING", version: 2 };

function dependencies(
  overrides: Partial<V1OrderDependencies> = {},
): V1OrderDependencies {
  return {
    authenticateBearer: overrides.authenticateBearer ??
      (() => Promise.resolve(actor)),
    submitOrder: overrides.submitOrder ??
      (() => Promise.resolve(orderSnapshot)),
    listOrders: overrides.listOrders ??
      (() => Promise.resolve({ orders: [], nextCursor: null })),
    getOrder: overrides.getOrder ?? (() => Promise.resolve(orderSnapshot)),
    cancelOrder: overrides.cancelOrder ??
      (() => Promise.resolve(orderSnapshot)),
    adminCancelOrder: overrides.adminCancelOrder ??
      (() => Promise.resolve({ orderId, status: "CANCELLED", version: 6 })),
    commitLaunchPayment: overrides.commitLaunchPayment ??
      (() => Promise.resolve(orderSnapshot)),
    listMerchantOpportunities: overrides.listMerchantOpportunities ??
      (() => Promise.resolve({ opportunities: [] })),
    listRestaurantRequests: overrides.listRestaurantRequests ??
      (() => Promise.resolve({ requests: [] })),
    respondRestaurantRequest: overrides.respondRestaurantRequest ??
      (() => Promise.resolve({})),
    acceptMerchantOpportunity: overrides.acceptMerchantOpportunity ??
      (() => Promise.resolve({})),
    declineMerchantOpportunity: overrides.declineMerchantOpportunity ??
      (() => Promise.resolve({})),
    listMerchantFulfilments: overrides.listMerchantFulfilments ??
      (() => Promise.resolve({ fulfilments: [] })),
    declareFulfilmentPackages: overrides.declareFulfilmentPackages ??
      (() => Promise.resolve({})),
    addFulfilmentReadyEvidence: overrides.addFulfilmentReadyEvidence ??
      (() => Promise.resolve({})),
    markFulfilmentReady: overrides.markFulfilmentReady ??
      (() => Promise.resolve({})),
    reportFulfilmentProblem: overrides.reportFulfilmentProblem ??
      (() => Promise.resolve({})),
    listAdminExecutionOrders: overrides.listAdminExecutionOrders ??
      (() => Promise.resolve({ orders: [] })),
    getAdminExecutionTrace: overrides.getAdminExecutionTrace ??
      (() => Promise.resolve({})),
    getAdminAccess: overrides.getAdminAccess ?? (() => Promise.resolve({})),
    getAdminCommandCenter: overrides.getAdminCommandCenter ??
      (() => Promise.resolve({})),
    getAdminNetworkPage: overrides.getAdminNetworkPage ??
      (() => Promise.resolve({})),
    setExecutiveAdmin: overrides.setExecutiveAdmin ??
      (() => Promise.resolve({})),
    getAdminSystemHealth: overrides.getAdminSystemHealth ??
      (() => Promise.resolve({})),
    getAdminOperationalSafety: overrides.getAdminOperationalSafety ??
      (() => Promise.resolve({})),
    manageRiderEscalation: overrides.manageRiderEscalation ??
      (() => Promise.resolve({})),
    setOperationalPause: overrides.setOperationalPause ??
      (() => Promise.resolve({})),
    authorizeExceptionalDeliveryHandoff: overrides.authorizeExceptionalDeliveryHandoff ??
      (() => Promise.resolve({})),
    reportExactSkuFailure: overrides.reportExactSkuFailure ??
      (() => Promise.resolve({})),
    createExactSkuRecoveryOffer: overrides.createExactSkuRecoveryOffer ??
      (() => Promise.resolve({})),
    respondExactSkuRecoveryOffer: overrides.respondExactSkuRecoveryOffer ??
      (() => Promise.resolve({})),
    failExactSkuRecovery: overrides.failExactSkuRecovery ??
      (() => Promise.resolve({})),
    reportCustomerIssue: overrides.reportCustomerIssue ??
      (() => Promise.resolve({})),
    decideCustomerIssue: overrides.decideCustomerIssue ??
      (() => Promise.resolve({})),
    assignReturnRider: overrides.assignReturnRider ??
      (() => Promise.resolve({})),
    manageDeliveryRecovery: overrides.manageDeliveryRecovery ??
      (() => Promise.resolve({})),
    finalizeSettlementCalculation: overrides.finalizeSettlementCalculation ??
      (() => Promise.resolve({})),
    settleEntry: overrides.settleEntry ?? (() => Promise.resolve({})),
  };
}

function request(
  payload: unknown,
  idempotencyKey?: string,
  authorization = "Bearer session",
) {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  if (idempotencyKey) headers.set("X-Idempotency-Key", idempotencyKey);
  return new Request(url, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });
}

async function body(response: Response) {
  return await response.json();
}
