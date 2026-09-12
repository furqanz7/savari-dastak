import { useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { RefreshCoalescer, realtimeRetryDelay, type OrderRealtimeHealth } from "./orderRealtime";

export type AdminWorkspace =
  | "operations"
  | "liveOrders"
  | "adminAccess"
  | "commandCenter"
  | "merchantApprovals"
  | "deliveryApprovals"
  | "systemHealth"
  | "operationalSafety"
  | "royaltyPayouts"
  | "network"
  | "auditHistory"
  | "merchantGovernance"
  | "deliveryPartnerGovernance"
  | "customerRecovery"
  | "catalogue";

export type AdminRefreshWorkspace = AdminWorkspace | "legacyHistory";

export type AdminChangeSignal = {
  workspaces: AdminWorkspace[];
  entityId?: string;
};

export type AdminFeedPhase =
  | "loading"
  | "ready"
  | "refreshing"
  | "stale"
  | "failed-with-content"
  | "failed-without-content";

export type AdminFeedState = {
  phase: AdminFeedPhase;
  updatedAt?: number;
  error?: unknown;
};

export const adminWorkspaces: readonly AdminWorkspace[] = [
  "operations",
  "liveOrders",
  "adminAccess",
  "commandCenter",
  "merchantApprovals",
  "deliveryApprovals",
  "systemHealth",
  "operationalSafety",
  "royaltyPayouts",
  "network",
  "auditHistory",
  "merchantGovernance",
  "deliveryPartnerGovernance",
  "customerRecovery",
  "catalogue",
];

const adminWorkspaceSet = new Set<string>(adminWorkspaces);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function initialAdminFeedState(): AdminFeedState {
  return { phase: "loading" };
}

export function adminFeedStarted(state: AdminFeedState): AdminFeedState {
  return {
    ...state,
    phase: adminFeedHasContent(state) ? "refreshing" : "loading",
    error: undefined,
  };
}

export function adminFeedSucceeded(state: AdminFeedState, updatedAt = Date.now()): AdminFeedState {
  return { ...state, phase: "ready", updatedAt, error: undefined };
}

export function adminFeedFailed(state: AdminFeedState, error: unknown): AdminFeedState {
  return {
    ...state,
    phase: adminFeedHasContent(state) ? "failed-with-content" : "failed-without-content",
    error,
  };
}

export function adminFeedStale(state: AdminFeedState): AdminFeedState {
  if (!adminFeedHasContent(state) || state.phase === "failed-with-content") return state;
  return { ...state, phase: "stale" };
}

export function adminFeedHasContent(state: AdminFeedState) {
  return state.updatedAt !== undefined;
}

export function adminFeedIsInitialLoading(state: AdminFeedState) {
  return state.phase === "loading";
}

export function parseAdminChangeSignal(value: unknown): AdminChangeSignal | undefined {
  const envelope = record(value);
  const payload = record(envelope?.payload) ?? envelope;
  if (!payload || !Array.isArray(payload.workspaces)) return undefined;
  const workspaces = [...new Set(payload.workspaces.filter((workspace): workspace is AdminWorkspace =>
    typeof workspace === "string" && adminWorkspaceSet.has(workspace)))];
  if (workspaces.length === 0) return undefined;
  const entityId = typeof payload.entityId === "string" && uuidPattern.test(payload.entityId)
    ? payload.entityId
    : undefined;
  return { workspaces, entityId };
}

export function isAdminSessionExpired(error: unknown) {
  const details = requestDetails(error);
  return details.status === 401 || [
    "authentication_required",
    "jwt_expired",
    "refresh_token_not_found",
    "invalid_refresh_token",
  ].includes(details.code);
}

export function shouldRunAdminFallback(visibility: DocumentVisibilityState, online: boolean) {
  return visibility === "visible" && online;
}

export function adminFallbackCadence(health: OrderRealtimeHealth) {
  return health === "subscribed" ? 60_000 : 30_000;
}

export function useAdminRealtime({
  client,
  accessToken,
  onChange,
  onVisibilityChange,
  onSessionExpired,
}: {
  client: SupabaseClient;
  accessToken: string;
  onChange: (signal?: AdminChangeSignal) => void;
  onVisibilityChange?: (visible: boolean) => void;
  onSessionExpired?: () => void;
}) {
  const callback = useRef(onChange);
  callback.current = onChange;
  const visibilityCallback = useRef(onVisibilityChange);
  visibilityCallback.current = onVisibilityChange;
  const sessionCallback = useRef(onSessionExpired);
  sessionCallback.current = onSessionExpired;
  const [health, setHealth] = useState<OrderRealtimeHealth>("connecting");

  useEffect(() => {
    let active = true;
    let channel: ReturnType<SupabaseClient["channel"]> | undefined;
    let reconnectTimer: number | undefined;
    let generation = 0;
    let retryAttempt = 0;
    let fullInvalidation = false;
    const pendingWorkspaces = new Set<AdminWorkspace>();
    let pendingEntityId: string | undefined;
    const invalidations = new RefreshCoalescer<void>(() => {
      if (!active) return;
      if (fullInvalidation) callback.current();
      else if (pendingWorkspaces.size > 0) callback.current({
        workspaces: [...pendingWorkspaces],
        entityId: pendingEntityId,
      });
      fullInvalidation = false;
      pendingWorkspaces.clear();
      pendingEntityId = undefined;
    });

    const requestInvalidation = (signal?: AdminChangeSignal) => {
      if (!signal) fullInvalidation = true;
      else {
        signal.workspaces.forEach((workspace) => pendingWorkspaces.add(workspace));
        pendingEntityId = signal.entityId ?? pendingEntityId;
      }
      invalidations.request();
    };
    const publishHealth = (next: OrderRealtimeHealth) => {
      if (active) setHealth(next);
    };
    const clearReconnect = () => {
      if (reconnectTimer !== undefined) window.clearTimeout(reconnectTimer);
      reconnectTimer = undefined;
    };
    const scheduleReconnect = (connectGeneration: number) => {
      clearReconnect();
      reconnectTimer = window.setTimeout(() => {
        if (!active || connectGeneration !== generation) return;
        generation += 1;
        void connect(generation);
      }, realtimeRetryDelay(retryAttempt));
      retryAttempt += 1;
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
          .channel("admin-control", { config: { private: true } })
          .on("broadcast", { event: "admin_changed" }, (message) => {
            const signal = parseAdminChangeSignal(message);
            if (signal) requestInvalidation(signal);
          });
        channel = next;
        next.subscribe((status, error) => {
          if (!active || connectGeneration !== generation) return;
          if (status === "SUBSCRIBED") {
            retryAttempt = 0;
            publishHealth("subscribed");
            requestInvalidation();
            return;
          }
          if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
            publishHealth("degraded");
            if (isAdminSessionExpired(error)) sessionCallback.current?.();
            else scheduleReconnect(connectGeneration);
          }
        });
      } catch (error) {
        if (!active || connectGeneration !== generation) return;
        publishHealth("degraded");
        if (isAdminSessionExpired(error)) sessionCallback.current?.();
        else scheduleReconnect(connectGeneration);
      }
    };
    const reconcile = () => {
      if (!active || document.visibilityState !== "visible") return;
      requestInvalidation();
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
  }, [accessToken, client]);

  return health;
}

function requestDetails(error: unknown): { code: string; status?: number } {
  if (!error || typeof error !== "object") return { code: "" };
  const value = error as { code?: unknown; status?: unknown; error?: unknown };
  const nested = record(value.error);
  const code = typeof nested?.code === "string" ? nested.code :
    typeof value.code === "string" ? value.code : "";
  const status = typeof nested?.status === "number" ? nested.status :
    typeof value.status === "number" ? value.status : undefined;
  return { code: code.trim().toLowerCase().replaceAll("-", "_"), status };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}
