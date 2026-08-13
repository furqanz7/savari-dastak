export type CustomerDataIssue = {
  kind: "offline" | "session" | "access" | "unavailable";
  title: string;
  message: string;
  action: "retry" | "sign_in";
};

export function customerDataIssue(error: unknown): CustomerDataIssue {
  const request = requestDetails(error);

  if (request.status === 401) {
    return {
      kind: "session",
      title: "Your session expired",
      message: "Sign in again to view your latest orders and deliveries.",
      action: "sign_in",
    };
  }

  if (request.status === 403) {
    return {
      kind: "access",
      title: "Customer access unavailable",
      message: "This account cannot load customer updates right now. Sign in again if the issue continues.",
      action: "sign_in",
    };
  }

  if (request.code === "network_error" || (typeof navigator !== "undefined" && !navigator.onLine)) {
    return {
      kind: "offline",
      title: "You are offline",
      message: "Reconnect to refresh your latest orders and deliveries.",
      action: "retry",
    };
  }

  return {
    kind: "unavailable",
    title: "Updates are unavailable",
    message: "Dastak could not refresh this information. Please try again.",
    action: "retry",
  };
}

function requestDetails(error: unknown): { code?: string; status?: number } {
  if (!error || typeof error !== "object") return {};
  const value = error as { code?: unknown; status?: unknown };
  return {
    code: typeof value.code === "string" ? value.code : undefined,
    status: typeof value.status === "number" ? value.status : undefined,
  };
}
