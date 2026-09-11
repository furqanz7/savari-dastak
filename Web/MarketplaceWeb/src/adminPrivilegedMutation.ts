export type AdminMutationResult =
  | { kind: "completed" }
  | { kind: "reconciled"; message: string }
  | { kind: "uncertain_reconciled"; message: string }
  | { kind: "uncertain_blocked"; message: string; reconciliationError: unknown }
  | { kind: "failed"; error: unknown };

const retainedKeys = new Map<string, string>();
const activeOperations = new Set<string>();

export function retainedAdminMutationKey(operationIdentity: string) {
  const existing = retainedKeys.get(operationIdentity);
  if (existing) return existing;
  const key = crypto.randomUUID();
  retainedKeys.set(operationIdentity, key);
  return key;
}

export function forgetAdminMutationKey(operationIdentity: string) {
  retainedKeys.delete(operationIdentity);
}

export function adminMutationErrorCode(error: unknown) {
  if (!error || typeof error !== "object") return "";
  const value = (error as { code?: unknown }).code;
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

export function isAdminConcurrencyResult(error: unknown) {
  const code = adminMutationErrorCode(error);
  return ["invalid_state", "stale_version", "not_found"].includes(code);
}

export function isAdminMutationOutcomeUncertain(error: unknown) {
  if (!error || typeof error !== "object") return false;
  const code = adminMutationErrorCode(error);
  const status = (error as { status?: unknown }).status;
  return code === "request_timeout" || code === "network_error" ||
    code === "invalid_response" || status === 0 ||
    typeof status === "number" && status >= 500;
}

export async function runAdminPrivilegedMutation(options: {
  operationIdentity: string;
  mutate: (idempotencyKey: string) => Promise<unknown>;
  reconcile: () => Promise<unknown>;
}): Promise<AdminMutationResult> {
  if (activeOperations.has(options.operationIdentity)) {
    return { kind: "failed", error: new Error("This Admin action is already being processed.") };
  }
  activeOperations.add(options.operationIdentity);
  const key = retainedAdminMutationKey(options.operationIdentity);
  try {
    await options.mutate(key);
    try {
      await options.reconcile();
    } catch (reconciliationError) {
      return {
        kind: "uncertain_blocked",
        message: "The action was accepted, but authoritative state could not be reloaded. The action remains locked until reconciliation succeeds.",
        reconciliationError,
      };
    }
    forgetAdminMutationKey(options.operationIdentity);
    return { kind: "completed" };
  } catch (error) {
    if (isAdminConcurrencyResult(error)) {
      try {
        await options.reconcile();
        forgetAdminMutationKey(options.operationIdentity);
        return {
          kind: "reconciled",
          message: "This record changed elsewhere. Dastak loaded the authoritative state; review it before acting again.",
        };
      } catch (reconciliationError) {
        return {
          kind: "uncertain_blocked",
          message: "This record changed, but Dastak could not reload its authoritative state. Try reconciliation before acting again.",
          reconciliationError,
        };
      }
    }
    if (isAdminMutationOutcomeUncertain(error)) {
      try {
        await options.reconcile();
        return {
          kind: "uncertain_reconciled",
          message: "The result could not be confirmed from the response. Dastak refreshed the authoritative state. If the action is still available, retry uses the same operation key.",
        };
      } catch (reconciliationError) {
        return {
          kind: "uncertain_blocked",
          message: "The result is unknown and authoritative state could not be reloaded. This action remains locked until reconciliation succeeds.",
          reconciliationError,
        };
      }
    }
    forgetAdminMutationKey(options.operationIdentity);
    return { kind: "failed", error };
  } finally {
    activeOperations.delete(options.operationIdentity);
  }
}

export function resetAdminMutationStateForTests() {
  retainedKeys.clear();
  activeOperations.clear();
}
