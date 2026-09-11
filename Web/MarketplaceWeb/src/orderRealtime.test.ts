import { describe, expect, it, vi } from "vitest";
import { parseOrderChangeSignal, realtimeRetryDelay, RefreshCoalescer, RefreshQueue } from "./orderRealtime";

describe("order realtime", () => {
  it("accepts only a minimal valid order invalidation", () => {
    expect(parseOrderChangeSignal({ payload: {
      entityKind: "merchant_order",
      entityId: "fc67d2b1-7d38-4e99-970e-c973049e4794",
      stateVersion: 7,
    } })).toEqual({
      entityKind: "merchant_order",
      entityId: "fc67d2b1-7d38-4e99-970e-c973049e4794",
      stateVersion: 7,
    });
    expect(parseOrderChangeSignal({ payload: {
      entityKind: "ride",
      entityId: "fc67d2b1-7d38-4e99-970e-c973049e4794",
      stateVersion: 7,
    } })).toBeUndefined();
    expect(parseOrderChangeSignal({ payload: {
      entityKind: "parcel",
      entityId: "not-a-uuid",
      stateVersion: 1,
    } })).toBeUndefined();
  });

  it("runs one trailing refresh when events arrive during a request", async () => {
    const queue = new RefreshQueue();
    let releaseFirst: (() => void) | undefined;
    let runs = 0;
    const task = async () => {
      runs += 1;
      if (runs === 1) await new Promise<void>((resolve) => { releaseFirst = resolve; });
    };

    const first = queue.request(false, task);
    await Promise.resolve();
    const second = queue.request(false, task);
    const third = queue.request(false, task);
    releaseFirst?.();
    await Promise.all([first, second, third]);

    expect(runs).toBe(2);
  });

  it("uses the latest task for the trailing refresh", async () => {
    const queue = new RefreshQueue();
    let releaseFirst: (() => void) | undefined;
    const runs: string[] = [];
    const first = queue.request(false, async () => {
      runs.push("first");
      await new Promise<void>((resolve) => { releaseFirst = resolve; });
    });
    await Promise.resolve();
    const trailing = queue.request(false, async () => { runs.push("latest"); });
    releaseFirst?.();
    await Promise.all([first, trailing]);
    expect(runs).toEqual(["first", "latest"]);
  });

  it("still runs the queued authoritative refresh after an in-flight failure", async () => {
    const queue = new RefreshQueue();
    let releaseFirst: (() => void) | undefined;
    const runs: string[] = [];
    const first = queue.request(false, async () => {
      runs.push("failed");
      await new Promise<void>((resolve) => { releaseFirst = resolve; });
      throw new Error("temporary");
    });
    await Promise.resolve();
    const trailing = queue.request(false, async () => { runs.push("authoritative"); });
    releaseFirst?.();
    await expect(Promise.all([first, trailing])).resolves.toEqual([undefined, undefined]);
    expect(runs).toEqual(["failed", "authoritative"]);
  });

  it("bounds realtime reconnect backoff", () => {
    expect([0, 1, 2, 3, 20].map(realtimeRetryDelay)).toEqual([
      1_000, 3_000, 10_000, 30_000, 30_000,
    ]);
  });

  it("coalesces an event burst into one trailing reconciliation", () => {
    vi.useFakeTimers();
    const values: number[] = [];
    const coalescer = new RefreshCoalescer<number>((value) => values.push(value ?? -1));
    coalescer.request(1);
    coalescer.request(2);
    coalescer.request(3);
    vi.advanceTimersByTime(150);
    expect(values).toEqual([3]);
    coalescer.cancel();
    vi.useRealTimers();
  });
});
