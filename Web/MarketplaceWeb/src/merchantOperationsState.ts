import { customerDataIssue, type CustomerDataIssue } from "./customerDataState";

export type MerchantFeedKey =
  | "retail"
  | "restaurant"
  | "fulfilments"
  | "recovery"
  | "returns"
  | "settlements"
  | "legacy";

export type MerchantFeedState = {
  loaded: boolean;
  loading: boolean;
  issue?: CustomerDataIssue;
};

export type MerchantFeedStates = Record<MerchantFeedKey, MerchantFeedState>;

export const merchantFeedLabels: Record<MerchantFeedKey, string> = {
  retail: "Incoming retail requests",
  restaurant: "Restaurant requests",
  fulfilments: "Preparation and pickup",
  recovery: "History and recovery",
  returns: "Returns",
  settlements: "Settlements",
  legacy: "Earlier orders",
};

export function initialMerchantFeedStates(): MerchantFeedStates {
  return {
    retail: { loaded: false, loading: true },
    restaurant: { loaded: false, loading: true },
    fulfilments: { loaded: false, loading: true },
    recovery: { loaded: false, loading: true },
    returns: { loaded: false, loading: true },
    settlements: { loaded: false, loading: true },
    legacy: { loaded: false, loading: true },
  };
}

export function merchantFeedStarted(
  states: MerchantFeedStates,
  keys: MerchantFeedKey[],
): MerchantFeedStates {
  return updateMerchantFeeds(states, keys, (state) => ({ ...state, loading: !state.loaded }));
}

export function merchantFeedSucceeded(
  states: MerchantFeedStates,
  key: MerchantFeedKey,
): MerchantFeedStates {
  return {
    ...states,
    [key]: { loaded: true, loading: false },
  };
}

export function merchantFeedFailed(
  states: MerchantFeedStates,
  key: MerchantFeedKey,
  error: unknown,
): MerchantFeedStates {
  return {
    ...states,
    [key]: { loaded: true, loading: false, issue: merchantDataIssue(error) },
  };
}

export function merchantDataIssue(error: unknown): CustomerDataIssue {
  const issue = customerDataIssue(error);
  if (issue.kind === "session") return issue;
  if (issue.kind === "offline") {
    return {
      ...issue,
      message: "Reconnect to receive the latest requests, preparation, pickup, and settlement updates.",
    };
  }
  if (issue.kind === "access") {
    return {
      ...issue,
      title: "Merchant access unavailable",
      message: "This account cannot load merchant operations right now. Sign in again if the issue continues.",
    };
  }
  return {
    ...issue,
    title: "Merchant updates are unavailable",
    message: "Dastak could not refresh this part of your order desk. Please try again.",
  };
}

export function merchantFeedFailures(states: MerchantFeedStates) {
  return (Object.keys(states) as MerchantFeedKey[])
    .filter((key) => states[key].issue)
    .map((key) => ({ key, label: merchantFeedLabels[key], issue: states[key].issue! }));
}

export function merchantFeedsInitiallyLoading(states: MerchantFeedStates) {
  return (Object.values(states) as MerchantFeedState[]).every((state) => !state.loaded);
}

export function merchantFeedsLoading(states: MerchantFeedStates) {
  return (Object.values(states) as MerchantFeedState[]).some((state) => state.loading);
}

export function merchantFeedsSettledWithoutErrors(states: MerchantFeedStates) {
  return (Object.values(states) as MerchantFeedState[]).every((state) => state.loaded && !state.issue);
}

export function isMerchantConcurrencyReconciliation(error: unknown) {
  const code = errorCode(error).trim().toLowerCase().replaceAll("-", "_");
  return code === "invalid_state" || code === "stale_version" || code === "not_found";
}

export function shouldRunMerchantFallback(visibility: DocumentVisibilityState, online: boolean) {
  return visibility === "visible" && online;
}

export function merchantFallbackCadence(health: "connecting" | "subscribed" | "degraded") {
  return health === "subscribed" ? 60_000 : 30_000;
}

function updateMerchantFeeds(
  states: MerchantFeedStates,
  keys: MerchantFeedKey[],
  update: (state: MerchantFeedState) => MerchantFeedState,
) {
  const next = { ...states };
  keys.forEach((key) => { next[key] = update(states[key]); });
  return next;
}

function errorCode(error: unknown): string {
  if (!error || typeof error !== "object") return "";
  const value = error as { code?: unknown; error?: unknown };
  if (typeof value.code === "string") return value.code;
  if (value.error && typeof value.error === "object" && !Array.isArray(value.error)) {
    const nested = (value.error as { code?: unknown }).code;
    if (typeof nested === "string") return nested;
  }
  return "";
}
