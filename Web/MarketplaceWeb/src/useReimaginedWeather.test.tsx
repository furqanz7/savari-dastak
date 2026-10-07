// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it, vi } from "vitest";
import { useReimaginedWeather } from "./useReimaginedWeather";

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

function setup() {
  let current!: ReturnType<typeof useReimaginedWeather>;
  function Probe() { current = useReimaginedWeather(); return null; }
  const root = createRoot(document.createElement("div"));
  act(() => root.render(<Probe />));
  return { get current() { return current; }, cleanup: () => act(() => root.unmount()) };
}

it("does not request location or weather without the explicit action and handles denial", async () => {
  const locate = vi.fn((_success, failure) => failure({ code: 1 }));
  const fetcher = vi.fn();
  vi.stubGlobal("navigator", { geolocation: { getCurrentPosition: locate } }); vi.stubGlobal("fetch", fetcher);
  const probe = setup();
  try {
    expect(locate).not.toHaveBeenCalled(); expect(fetcher).not.toHaveBeenCalled();
    await act(async () => probe.current.locate());
    expect(probe.current.status).toContain("Location denied");
    expect(probe.current.weather).toBeNull(); expect(probe.current.pending).toBe(false);
    expect(fetcher).not.toHaveBeenCalled();
  } finally { probe.cleanup(); }
});

it("loads rounded nearby weather, expires stale data and stops polling on unmount", async () => {
  vi.useFakeTimers(); const now = Date.parse("2026-10-03T12:00:00Z"); vi.setSystemTime(now);
  vi.stubGlobal("navigator", { geolocation: { getCurrentPosition: (success: PositionCallback) => success({ coords: { latitude: 12.9715987, longitude: 77.5945627 } } as GeolocationPosition) } });
  const fetcher = vi.fn().mockResolvedValueOnce({ ok: true, json: async () => ({ timezone: "UTC", current: { time: now / 1000, temperature_2m: 24, cloud_cover: 80, precipitation: 1, weather_code: 61, wind_speed_10m: 22, wind_gusts_10m: 35, wind_direction_10m: 180, is_day: 1 }, daily: { sunrise: [now/1000 - 21600], sunset: [now/1000 + 21600] } }) }).mockRejectedValue(new Error("offline"));
  vi.stubGlobal("fetch", fetcher);
  const probe = setup();
  await act(async () => probe.current.locate());
  expect(probe.current.weather?.wind).toBe(22);
  expect(fetcher.mock.calls[0][0]).toContain("latitude=12.97&longitude=77.59");
  expect(probe.current.pending).toBe(false);
  await act(async () => { await vi.advanceTimersByTimeAsync(46 * 60_000); });
  expect(probe.current.weather).toBeNull(); expect(probe.current.status).toContain("expired");
  probe.cleanup(); const calls = fetcher.mock.calls.length;
  await act(async () => { await vi.advanceTimersByTimeAsync(30 * 60_000); });
  expect(fetcher).toHaveBeenCalledTimes(calls);
});
