import { describe, expect, it, vi } from "vitest";
import { requestDeadline } from "./requestDeadline";

describe("request deadline", () => {
  it("propagates an explicit caller abort without reporting a timeout", () => {
    const caller = new AbortController();
    const deadline = requestDeadline(caller.signal, 1_000);
    caller.abort();
    expect(deadline.signal.aborted).toBe(true);
    expect(deadline.timedOut()).toBe(false);
    deadline.dispose();
  });

  it("aborts a request after the bounded deadline", () => {
    vi.useFakeTimers();
    const deadline = requestDeadline(undefined, 25);
    vi.advanceTimersByTime(25);
    expect(deadline.signal.aborted).toBe(true);
    expect(deadline.timedOut()).toBe(true);
    deadline.dispose();
    vi.useRealTimers();
  });
});
