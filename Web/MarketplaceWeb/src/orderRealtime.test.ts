import { describe, expect, it } from "vitest";
import { parseOrderChangeSignal, RefreshQueue } from "./orderRealtime";

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
    await queue.request(false, task);
    await queue.request(false, task);
    releaseFirst?.();
    await first;

    expect(runs).toBe(2);
  });
});
