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
