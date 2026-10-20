/** In-memory bulkhead only: no caller/IP tracking, no cross-instance guarantee. */
export function supportBulkhead(now: () => number = Date.now) {
  let active = 0;
  let tokens = 30;
  let updated = now();
  return () => {
    const time = now();
    tokens = Math.min(30, tokens + Math.max(0, time - updated) / 1000);
    updated = time;
    if (active >= 8 || tokens < 1) return undefined;
    tokens--;
    active++;
    let released = false;
    return () => {
      if (!released) {
        active--;
        released = true;
      }
    };
  };
}

export async function supportDeadline<T>(
  work: (signal: AbortSignal) => Promise<T>,
  milliseconds: number,
  parent: AbortSignal,
): Promise<T> {
  const controller = new AbortController();
  const abort = () => controller.abort();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let stop: (() => void) | undefined;
  try {
    if (parent.aborted) controller.abort();
    else parent.addEventListener("abort", abort, { once: true });
    return await Promise.race([
      new Promise<never>((_resolve, reject) => {
        stop = () => reject(Error("support_unavailable"));
        controller.signal.addEventListener("abort", stop, { once: true });
        if (controller.signal.aborted) stop();
        timer = setTimeout(abort, milliseconds);
      }),
      controller.signal.aborted
        ? Promise.reject(Error("support_unavailable"))
        : work(controller.signal),
    ]);
  } finally {
    clearTimeout(timer);
    parent.removeEventListener("abort", abort);
    if (stop) controller.signal.removeEventListener("abort", stop);
  }
}

/** PostgreSQL text cannot represent NUL or unpaired UTF-16 surrogates. */
export function supportText(value: unknown, min: number, max: number): value is string {
  if (typeof value !== "string" || value.trim().length < min || value.trim().length > max) {
    return false;
  }
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code === 0) return false;
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
    } else if (code >= 0xdc00 && code <= 0xdfff) return false;
  }
  return true;
}
