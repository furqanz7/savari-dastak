export const defaultRequestTimeoutMs = 15_000;

export type RequestDeadline = {
  signal: AbortSignal;
  timedOut: () => boolean;
  dispose: () => void;
};

export function requestDeadline(
  externalSignal?: AbortSignal,
  timeoutMs = defaultRequestTimeoutMs,
): RequestDeadline {
  const controller = new AbortController();
  let didTimeOut = false;
  const abortFromCaller = () => controller.abort(externalSignal?.reason);

  if (externalSignal?.aborted) abortFromCaller();
  else externalSignal?.addEventListener("abort", abortFromCaller, { once: true });

  const timer = setTimeout(() => {
    didTimeOut = true;
    controller.abort(new DOMException("The request timed out.", "TimeoutError"));
  }, Math.max(1, timeoutMs));

  return {
    signal: controller.signal,
    timedOut: () => didTimeOut,
    dispose: () => {
      clearTimeout(timer);
      externalSignal?.removeEventListener("abort", abortFromCaller);
    },
  };
}

export function isAbortError(error: unknown) {
  return error instanceof DOMException && error.name === "AbortError";
}
