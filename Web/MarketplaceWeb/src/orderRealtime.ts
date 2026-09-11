import { useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

export type OrderChangeSignal = {
  entityKind: "merchant_order" | "parcel";
  entityId: string;
  stateVersion: number;
};

export type OrderRealtimeHealth = "connecting" | "subscribed" | "degraded";

export function realtimeRetryDelay(attempt: number) {
  return [1_000, 3_000, 10_000, 30_000][Math.min(Math.max(attempt, 0), 3)];
}

export class RefreshCoalescer<T> {
  private timer: ReturnType<typeof setTimeout> | undefined;
  private latest: T | undefined;

  constructor(private readonly callback: (value?: T) => void, private readonly delayMs = 150) {}

  request(value?: T) {
    this.latest = value ?? this.latest;
    if (this.timer !== undefined) return;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      const latest = this.latest;
      this.latest = undefined;
      this.callback(latest);
    }, this.delayMs);
  }

  cancel() {
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = undefined;
    this.latest = undefined;
  }
}

export function parseOrderChangeSignal(value: unknown): OrderChangeSignal | undefined {
  const envelope = record(value);
  const candidate = record(envelope?.payload) ?? envelope;
  if (!candidate) return undefined;
  const { entityKind, entityId, stateVersion } = candidate;
  if (entityKind !== "merchant_order" && entityKind !== "parcel") return undefined;
  if (typeof entityId !== "string" || !uuidPattern.test(entityId)) return undefined;
  if (typeof stateVersion !== "number" || !Number.isSafeInteger(stateVersion) || stateVersion < 0) return undefined;
  return { entityKind, entityId, stateVersion };
}

export class RefreshQueue {
  private running = false;
  private queued = false;
  private pendingProgress = false;
  private nextTask: ((showProgress: boolean) => Promise<void>) | undefined;

  async request(
    showProgress: boolean,
    task: (showProgress: boolean) => Promise<void>,
  ): Promise<void> {
    this.queued = true;
    this.pendingProgress ||= showProgress;
    this.nextTask = task;
    if (this.running) return;

    this.running = true;
    try {
      while (this.queued) {
        const nextProgress = this.pendingProgress;
        const nextTask = this.nextTask;
        this.queued = false;
        this.pendingProgress = false;
        this.nextTask = undefined;
        if (nextTask) await nextTask(nextProgress);
      }
    } finally {
      this.running = false;
    }
  }
}

export function useOrderRealtime({
  client,
  accountId,
  accessToken,
  onChange,
  onVisibilityChange,
}: {
  client: SupabaseClient;
  accountId: string;
  accessToken: string;
  onChange: (signal?: OrderChangeSignal) => void;
  onVisibilityChange?: (visible: boolean) => void;
}) {
  const callback = useRef(onChange);
  callback.current = onChange;
  const visibilityCallback = useRef(onVisibilityChange);
  visibilityCallback.current = onVisibilityChange;
  const [health, setHealth] = useState<OrderRealtimeHealth>("connecting");

  useEffect(() => {
    let active = true;
    let channel: ReturnType<SupabaseClient["channel"]> | undefined;
    let reconnectTimer: number | undefined;
    let generation = 0;
    let retryAttempt = 0;
    const invalidations = new RefreshCoalescer<OrderChangeSignal>((signal) => {
      if (active) callback.current(signal);
    });

    const publishHealth = (next: OrderRealtimeHealth) => {
      if (active) setHealth(next);
    };
    const clearReconnect = () => {
      if (reconnectTimer !== undefined) window.clearTimeout(reconnectTimer);
      reconnectTimer = undefined;
    };
    const connect = async (connectGeneration: number) => {
      clearReconnect();
      if (typeof navigator !== "undefined" && navigator.onLine === false) {
        publishHealth("degraded");
        return;
      }
      publishHealth("connecting");
      try {
        const previous = channel;
        channel = undefined;
        if (previous) await client.removeChannel(previous);
        if (!active || connectGeneration !== generation) return;
        await client.realtime.setAuth(accessToken);
        if (!active || connectGeneration !== generation) return;
        const next = client
          .channel(`order-account:${accountId.toLowerCase()}`, { config: { private: true } })
          .on("broadcast", { event: "order_changed" }, (message) => {
            const signal = parseOrderChangeSignal(message);
            if (signal) invalidations.request(signal);
          });
        channel = next;
        next.subscribe((status) => {
          if (!active || connectGeneration !== generation) return;
          if (status === "SUBSCRIBED") {
            retryAttempt = 0;
            publishHealth("subscribed");
            invalidations.request();
            return;
          }
          if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
            publishHealth("degraded");
            clearReconnect();
            reconnectTimer = window.setTimeout(() => {
              generation += 1;
              void connect(generation);
            }, realtimeRetryDelay(retryAttempt));
            retryAttempt += 1;
          }
        });
      } catch {
        if (!active || connectGeneration !== generation) return;
        publishHealth("degraded");
        reconnectTimer = window.setTimeout(() => {
          generation += 1;
          void connect(generation);
        }, realtimeRetryDelay(retryAttempt));
        retryAttempt += 1;
      }
    };
    const reconcile = () => {
      if (!active || document.visibilityState !== "visible") return;
      invalidations.request();
      generation += 1;
      void connect(generation);
    };
    const onVisible = () => {
      const visible = document.visibilityState === "visible";
      visibilityCallback.current?.(visible);
      if (visible) reconcile();
    };
    const onOnline = () => reconcile();
    const onOffline = () => {
      clearReconnect();
      publishHealth("degraded");
    };

    void connect(generation);
    visibilityCallback.current?.(document.visibilityState === "visible");
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);

    return () => {
      active = false;
      generation += 1;
      clearReconnect();
      invalidations.cancel();
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
      if (channel) void client.removeChannel(channel);
    };
  }, [accessToken, accountId, client]);

  return health;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
