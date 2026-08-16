import { useEffect, useRef } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

export type OrderChangeSignal = {
  entityKind: "merchant_order" | "parcel";
  entityId: string;
  stateVersion: number;
};

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

  async request(
    showProgress: boolean,
    task: (showProgress: boolean) => Promise<void>,
  ): Promise<void> {
    this.queued = true;
    this.pendingProgress ||= showProgress;
    if (this.running) return;

    this.running = true;
    try {
      while (this.queued) {
        const nextProgress = this.pendingProgress;
        this.queued = false;
        this.pendingProgress = false;
        await task(nextProgress);
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
}: {
  client: SupabaseClient;
  accountId: string;
  accessToken: string;
  onChange: (signal: OrderChangeSignal) => void;
}) {
  const callback = useRef(onChange);
  callback.current = onChange;

  useEffect(() => {
    let active = true;
    let channel: ReturnType<SupabaseClient["channel"]> | undefined;

    void client.realtime.setAuth(accessToken).then(() => {
      if (!active) return;
      channel = client
        .channel(`order-account:${accountId.toLowerCase()}`, { config: { private: true } })
        .on("broadcast", { event: "order_changed" }, (message) => {
          const signal = parseOrderChangeSignal(message);
          if (signal) callback.current(signal);
        })
        .subscribe();
    }).catch(() => {
      // Polling remains authoritative while realtime is unavailable.
    });

    return () => {
      active = false;
      if (channel) void client.removeChannel(channel);
    };
  }, [accessToken, accountId, client]);
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
