import { assertEquals } from "jsr:@std/assert";
import { safeRPCError, V1RequestError } from "../../_shared/v1-rpc.ts";

Deno.test("shared V1 RPC errors expose rider conflicts without SQL details", () => {
  const error = safeRPCError({
    code: "P0001",
    message: "RIDER_ACTIVE_WORK_CONFLICT",
  });

  assertEquals(error instanceof V1RequestError, true);
  assertEquals(error.status, 409);
  assertEquals(error.code, "rider_active_work_conflict");
  assertEquals(
    error.message,
    "This delivery partner must complete the active job before another can be assigned.",
  );
});

Deno.test("shared V1 RPC errors keep unknown database failures private", () => {
  const error = safeRPCError({
    code: "P0001",
    message: "duplicate key value violates private assignment index",
  });

  assertEquals(error.status, 500);
  assertEquals(error.code, "internal_error");
  assertEquals(error.message, "The Dastak request could not be processed.");
});

Deno.test("shared V1 RPC errors expose reviewed Merchant governance conflicts safely", () => {
  const activeWork = safeRPCError({
    code: "55000",
    message: "ACTIVE_FULFILMENTS_REQUIRE_RESOLUTION",
  });
  const activeRoute = safeRPCError({
    code: "55000",
    message: "ACTIVE_PICKUP_OR_RETURN_WORK",
  });

  assertEquals({ status: activeWork.status, code: activeWork.code }, {
    status: 409,
    code: "active_fulfilments_require_resolution",
  });
  assertEquals({ status: activeRoute.status, code: activeRoute.code }, {
    status: 409,
    code: "active_pickup_or_return_work",
  });
});

Deno.test("shared V1 RPC errors expose reviewed rider governance conflicts safely", () => {
  const suspended = safeRPCError({ code: "P0001", message: "RIDER_GOVERNANCE_SUSPENDED" });
  const activeWork = safeRPCError({ code: "55000", message: "RIDER_ACTIVE_WORK_REQUIRES_RELEASE" });
  assertEquals({ status: suspended.status, code: suspended.code }, {
    status: 409,
    code: "rider_governance_suspended",
  });
  assertEquals({ status: activeWork.status, code: activeWork.code }, {
    status: 409,
    code: "rider_active_work_requires_release",
  });
});

Deno.test("shared V1 RPC errors expose a claimed Customer phone without database detail", () => {
  const claimed = safeRPCError({ code: "23505", message: "PHONE_NUMBER_ALREADY_CLAIMED" });
  assertEquals({ status: claimed.status, code: claimed.code, message: claimed.message }, {
    status: 409,
    code: "phone_number_in_use",
    message: "That phone number is already claimed by another Dastak identity.",
  });
});
