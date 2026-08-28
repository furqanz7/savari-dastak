type RpcResult = { responseBody: unknown; responseStatus: number };

type PreparationDiagnostic = {
  category: "CHECKOUT_PREPARATION_FAILED";
  databaseCode: "22023" | "23505" | "42501" | "55000" | "P0002" | "UNKNOWN";
};

export function checkoutPreparationError(
  error: unknown,
  includeTestDiagnostic = false,
): RpcResult {
  const diagnostic = checkoutPreparationDiagnostic(error);
  const response = responseFor(diagnostic.databaseCode);
  return {
    responseBody: {
      error: {
        code: response.code,
        message: response.message,
        ...(includeTestDiagnostic ? { testDiagnostic: diagnostic } : {}),
      },
    },
    responseStatus: response.status,
  };
}

export function checkoutPreparationDiagnostic(error: unknown): PreparationDiagnostic {
  const value = record(error)?.code;
  const databaseCode = value === "22023" || value === "23505" || value === "42501" ||
      value === "55000" || value === "P0002"
    ? value
    : "UNKNOWN";
  return { category: "CHECKOUT_PREPARATION_FAILED", databaseCode };
}

function responseFor(databaseCode: PreparationDiagnostic["databaseCode"]) {
  if (databaseCode === "42501") {
    return {
      status: 403,
      code: "payment_checkout_forbidden",
      message: "This payment cannot be prepared by this account.",
    };
  }
  if (databaseCode === "P0002") {
    return {
      status: 404,
      code: "payment_attempt_not_found",
      message: "The active payment reservation was not found.",
    };
  }
  if (databaseCode === "22023" || databaseCode === "23505" || databaseCode === "55000") {
    return {
      status: 409,
      code: "payment_checkout_conflict",
      message: "The payment request conflicts with the active reservation.",
    };
  }
  return {
    status: 503,
    code: "payment_checkout_preparation_failed",
    message: "Dastak could not prepare this payment right now.",
  };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}
