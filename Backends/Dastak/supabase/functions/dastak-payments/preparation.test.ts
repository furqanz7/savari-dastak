import { assertEquals, assertFalse } from "jsr:@std/assert@1";
import { checkoutPreparationDiagnostic, checkoutPreparationError } from "./preparation.ts";

Deno.test("checkout preparation maps known database failures without leaking details", () => {
  const cases = [
    ["42501", 403, "payment_checkout_forbidden"],
    ["P0002", 404, "payment_attempt_not_found"],
    ["22023", 409, "payment_checkout_conflict"],
    ["23505", 409, "payment_checkout_conflict"],
    ["55000", 409, "payment_checkout_conflict"],
  ] as const;

  for (const [code, status, responseCode] of cases) {
    const result = checkoutPreparationError(
      { code, message: "sensitive database detail", details: "private row" },
      true,
    );
    assertEquals(result.responseStatus, status);
    const serialized = JSON.stringify(result.responseBody);
    assertEquals(
      (result.responseBody as { error: { code: string } }).error.code,
      responseCode,
    );
    assertFalse(serialized.includes("sensitive database detail"));
    assertFalse(serialized.includes("private row"));
    assertEquals(
      (result.responseBody as { error: { testDiagnostic: { databaseCode: string } } }).error
        .testDiagnostic.databaseCode,
      code,
    );
  }
});

Deno.test("checkout preparation collapses unknown errors to a safe diagnostic", () => {
  assertEquals(
    checkoutPreparationDiagnostic({ code: "XX999", message: "secret" }),
    { category: "CHECKOUT_PREPARATION_FAILED", databaseCode: "UNKNOWN" },
  );
  const result = checkoutPreparationError(new Error("sensitive failure"), true);
  assertEquals(result.responseStatus, 503);
  assertFalse(JSON.stringify(result.responseBody).includes("sensitive failure"));
});

Deno.test("checkout preparation diagnostics are omitted outside authorized Test owner paths", () => {
  const result = checkoutPreparationError({ code: "55000" });
  assertFalse(JSON.stringify(result.responseBody).includes("testDiagnostic"));
});
