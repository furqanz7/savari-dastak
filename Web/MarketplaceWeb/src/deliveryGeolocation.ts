import { useCallback, useEffect, useRef, useState } from "react";
import type { OrderLocation } from "./orders";

export type DeliveryGeolocationMode =
  | { kind: "idle" }
  | { kind: "availability" }
  | { kind: "mission"; missionId: string };

export type DeliveryGeolocationStatus =
  | "idle"
  | "starting"
  | "tracking"
  | "background_limited"
  | "unavailable"
  | "permission_denied"
  | "inaccurate"
  | "stale"
  | "interrupted";

export type WakeLockStatus = "inactive" | "active" | "unsupported" | "failed";

type PositionFix = {
  latitude: number;
  longitude: number;
  accuracyMeters: number;
  recordedAt: string;
  timestamp: number;
};

type ControllerInput = {
  mode: DeliveryGeolocationMode;
  publishMission: (missionId: string, fix: Omit<PositionFix, "timestamp">) => Promise<void>;
  publishAvailability: (location: OrderLocation) => Promise<void>;
  onForegroundReconcile: () => void;
};

export type DeliveryGeolocationController = {
  status: DeliveryGeolocationStatus;
  wakeLockStatus: WakeLockStatus;
  handleVisibilityChange: (visible: boolean) => void;
  currentLocation: () => Promise<OrderLocation>;
};

const missionPublishIntervalMs = 8_000;
const availabilityPublishIntervalMs = 15_000;
const maximumFixAgeMs = 25_000;
const maximumAccuracyMeters = 200;

export function useDeliveryGeolocationController({
  mode,
  publishMission,
  publishAvailability,
  onForegroundReconcile,
}: ControllerInput): DeliveryGeolocationController {
  const [status, setStatus] = useState<DeliveryGeolocationStatus>(
    mode.kind === "idle" ? "idle" : "starting",
  );
  const [wakeLockStatus, setWakeLockStatus] = useState<WakeLockStatus>("inactive");
  const modeRef = useRef(mode);
  const missionPublisher = useRef(publishMission);
  const availabilityPublisher = useRef(publishAvailability);
  const reconcile = useRef(onForegroundReconcile);
  const latestFix = useRef<PositionFix | undefined>(undefined);
  const lastPublishedAt = useRef(0);
  const publishing = useRef(false);
  const active = useRef(true);
  const wakeLock = useRef<{ release: () => Promise<void>; released?: boolean } | undefined>(undefined);
  const visible = useRef(
    typeof document === "undefined" || document.visibilityState === "visible",
  );
  const missionModeId = mode.kind === "mission" ? mode.missionId : "";

  modeRef.current = mode;
  missionPublisher.current = publishMission;
  availabilityPublisher.current = publishAvailability;
  reconcile.current = onForegroundReconcile;

  const publishStatus = useCallback((next: DeliveryGeolocationStatus) => {
    setStatus((current) => current === next ? current : next);
  }, []);

  const releaseWakeLock = useCallback(() => {
    const current = wakeLock.current;
    wakeLock.current = undefined;
    if (current && !current.released) void current.release().catch(() => undefined);
    setWakeLockStatus((state) => state === "inactive" ? state : "inactive");
  }, []);

  const acquireWakeLock = useCallback(async () => {
    if (modeRef.current.kind !== "mission" || !visible.current) {
      releaseWakeLock();
      return;
    }
    const manager = (navigator as Navigator & {
      wakeLock?: { request: (type: "screen") => Promise<{ release: () => Promise<void>; released?: boolean; addEventListener?: (type: "release", listener: () => void) => void }> };
    }).wakeLock;
    if (!manager) {
      setWakeLockStatus("unsupported");
      return;
    }
    if (wakeLock.current && !wakeLock.current.released) return;
    try {
      const sentinel = await manager.request("screen");
      if (!active.current || modeRef.current.kind !== "mission" || !visible.current) {
        await sentinel.release().catch(() => undefined);
        return;
      }
      wakeLock.current = sentinel;
      sentinel.addEventListener?.("release", () => {
        if (wakeLock.current === sentinel) wakeLock.current = undefined;
        setWakeLockStatus("inactive");
      });
      setWakeLockStatus("active");
    } catch {
      setWakeLockStatus("failed");
    }
  }, [releaseWakeLock]);

  const publishFix = useCallback(async (fix: PositionFix, force = false) => {
    const currentMode = modeRef.current;
    if (currentMode.kind === "idle" || !visible.current || publishing.current) return;
    const now = Date.now();
    const freshness = classifyPositionFix(fix, now);
    if (freshness !== "tracking") {
      publishStatus(freshness);
      return;
    }
    const interval = currentMode.kind === "mission"
      ? missionPublishIntervalMs
      : availabilityPublishIntervalMs;
    if (!force && now - lastPublishedAt.current < interval) return;
    publishing.current = true;
    lastPublishedAt.current = now;
    try {
      if (currentMode.kind === "mission") {
        await missionPublisher.current(currentMode.missionId, {
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyMeters: fix.accuracyMeters,
          recordedAt: fix.recordedAt,
        });
      } else {
        await availabilityPublisher.current({
          latitude: fix.latitude,
          longitude: fix.longitude,
        });
      }
      if (active.current && visible.current && modeRef.current.kind !== "idle") {
        publishStatus("tracking");
      }
    } catch {
      if (active.current) publishStatus("interrupted");
    } finally {
      publishing.current = false;
    }
  }, [publishStatus]);

  const acceptPosition = useCallback((position: GeolocationPosition, force = false) => {
    const fix = positionFix(position);
    latestFix.current = fix;
    void publishFix(fix, force);
  }, [publishFix]);

  const requestPosition = useCallback((force: boolean) => {
    if (!navigator.geolocation || modeRef.current.kind === "idle") return;
    navigator.geolocation.getCurrentPosition(
      (position) => acceptPosition(position, force),
      (positionError) => publishStatus(
        positionError.code === positionError.PERMISSION_DENIED ? "permission_denied" : "interrupted",
      ),
      { enableHighAccuracy: true, maximumAge: force ? 0 : 10_000, timeout: 15_000 },
    );
  }, [acceptPosition, publishStatus]);

  const handleVisibilityChange = useCallback((isVisible: boolean) => {
    visible.current = isVisible;
    if (!isVisible) {
      releaseWakeLock();
      if (modeRef.current.kind !== "idle") publishStatus("background_limited");
      return;
    }
    reconcile.current();
    lastPublishedAt.current = 0;
    publishStatus(modeRef.current.kind === "idle" ? "idle" : "starting");
    void acquireWakeLock();
    const fix = latestFix.current;
    if (fix && classifyPositionFix(fix) === "tracking") void publishFix(fix, true);
    else requestPosition(true);
  }, [acquireWakeLock, publishFix, publishStatus, releaseWakeLock, requestPosition]);

  useEffect(() => {
    if (mode.kind === "idle") {
      publishStatus("idle");
      latestFix.current = undefined;
      releaseWakeLock();
      return;
    }
    if (!navigator.geolocation) {
      publishStatus("unavailable");
      return;
    }
    lastPublishedAt.current = 0;
    publishStatus(visible.current ? "starting" : "background_limited");
    if (mode.kind === "mission") void acquireWakeLock();
    else releaseWakeLock();
    const watch = navigator.geolocation.watchPosition(
      (position) => acceptPosition(position),
      (positionError) => publishStatus(
        positionError.code === positionError.PERMISSION_DENIED ? "permission_denied" : "interrupted",
      ),
      { enableHighAccuracy: true, maximumAge: mode.kind === "mission" ? 0 : 10_000, timeout: 15_000 },
    );
    return () => navigator.geolocation.clearWatch(watch);
  }, [acceptPosition, acquireWakeLock, missionModeId, mode.kind, publishStatus, releaseWakeLock]);

  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
      releaseWakeLock();
    };
  }, [releaseWakeLock]);

  const currentLocation = useCallback(async () => {
    const fix = latestFix.current;
    if (fix && classifyPositionFix(fix) === "tracking") {
      return { latitude: fix.latitude, longitude: fix.longitude };
    }
    if (!navigator.geolocation) throw new Error("Location is unavailable in this browser.");
    return await new Promise<OrderLocation>((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const next = positionFix(position);
          latestFix.current = next;
          if (classifyPositionFix(next) !== "tracking") {
            reject(new Error("A fresh, accurate location is required."));
            return;
          }
          resolve({ latitude: next.latitude, longitude: next.longitude });
        },
        () => reject(new Error("Allow precise location access to go online.")),
        { enableHighAccuracy: true, timeout: 12_000, maximumAge: 30_000 },
      );
    });
  }, []);

  return { status, wakeLockStatus, handleVisibilityChange, currentLocation };
}

export function classifyPositionFix(
  fix: Pick<PositionFix, "accuracyMeters" | "timestamp">,
  now = Date.now(),
): Extract<DeliveryGeolocationStatus, "tracking" | "stale" | "inaccurate"> {
  if (Math.abs(now - fix.timestamp) > maximumFixAgeMs) return "stale";
  if (fix.accuracyMeters > maximumAccuracyMeters) return "inaccurate";
  return "tracking";
}

function positionFix(position: GeolocationPosition): PositionFix {
  return {
    latitude: position.coords.latitude,
    longitude: position.coords.longitude,
    accuracyMeters: position.coords.accuracy,
    recordedAt: new Date(position.timestamp).toISOString(),
    timestamp: position.timestamp,
  };
}
