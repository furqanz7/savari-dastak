import { useCallback, useEffect, useRef, useState } from "react";

const threshold = 68;

export function usePullToRefresh(refresh: () => Promise<unknown> | unknown, enabled = true) {
  const [distance, setDistance] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const gesture = useRef<{ pointerId: number; startY: number; distance: number } | undefined>(undefined);

  const finish = useCallback(async () => {
    const shouldRefresh = enabled && (gesture.current?.distance ?? 0) >= threshold;
    gesture.current = undefined;
    if (!shouldRefresh || refreshing) {
      setDistance(0);
      return;
    }
    setRefreshing(true);
    setDistance(threshold);
    try { await refresh(); }
    finally {
      setRefreshing(false);
      setDistance(0);
    }
  }, [enabled, refresh, refreshing]);

  useEffect(() => {
    if (!enabled) return;
    const start = (event: PointerEvent) => {
      if (!event.isPrimary || event.button !== 0 || window.scrollY > 1 || refreshing) return;
      gesture.current = { pointerId: event.pointerId, startY: event.clientY, distance: 0 };
    };
    const move = (event: PointerEvent) => {
      const current = gesture.current;
      if (!current || current.pointerId !== event.pointerId) return;
      if (window.scrollY > 1 || event.clientY < current.startY) {
        gesture.current = undefined;
        setDistance(0);
        return;
      }
      const next = Math.min(92, Math.max(0, (event.clientY - current.startY) * 0.48));
      current.distance = next;
      setDistance(next);
    };
    const end = (event: PointerEvent) => {
      if (gesture.current?.pointerId === event.pointerId) void finish();
    };
    window.addEventListener("pointerdown", start, { passive: true });
    window.addEventListener("pointermove", move, { passive: true });
    window.addEventListener("pointerup", end, { passive: true });
    window.addEventListener("pointercancel", end, { passive: true });
    return () => {
      window.removeEventListener("pointerdown", start);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", end);
      window.removeEventListener("pointercancel", end);
    };
  }, [enabled, finish, refreshing]);

  return {
    distance,
    progress: Math.min(1, distance / threshold),
    refreshing,
  };
}
