import { useEffect, useRef, useState } from "react";
import { parseWeather, weatherUrl, WEATHER_MAX_AGE, weatherDescription, type OutdoorWeather } from "./reimaginedWeather";

export function useReimaginedWeather() {
  const [weather, setWeather] = useState<OutdoorWeather | null>(null);
  const [status, setStatus] = useState("Time-only sky · weather not connected");
  const [pending, setPending] = useState(false);
  const [coordinates, setCoordinates] = useState<{ latitude: number; longitude: number } | null>(null);
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  function locate() {
    if (pending) return;
    if (!navigator.geolocation) { setStatus("Location unavailable · time-only sky"); return; }
    setCoordinates(null); setWeather(null);
    setPending(true); setStatus("Waiting for location permission…");
    navigator.geolocation.getCurrentPosition(position => {
      if (!mounted.current) return;
      setCoordinates({ latitude: Math.round(position.coords.latitude * 100) / 100, longitude: Math.round(position.coords.longitude * 100) / 100 });
    }, error => {
      if (!mounted.current) return;
      setPending(false);
      setStatus(error.code === 1 ? "Location denied · time-only sky" : "Location unavailable · time-only sky");
      setWeather(null);
    }, { enableHighAccuracy: false, timeout: 15_000, maximumAge: 5 * 60_000 });
  }
  useEffect(() => {
    if (!coordinates) return;
    let disposed = false; let active: AbortController | null = null;
    let lastAttempt = 0; let lastWeather: OutdoorWeather | null = null;
    async function refresh() {
      if (document.hidden || active || disposed) return;
      lastAttempt = Date.now(); active = new AbortController();
      const controller = active;
      const timeout = window.setTimeout(() => controller.abort(), 12_000);
      setStatus("Fetching nearby-area weather…");
      try {
        const response = await fetch(weatherUrl(coordinates!.latitude, coordinates!.longitude), { signal: active.signal, credentials: "omit", referrerPolicy: "no-referrer" });
        if (!response.ok) throw new Error("Weather unavailable");
        const next = parseWeather(await response.json());
        if (!disposed) {
          lastWeather = next; setWeather(next);
          setStatus(`${weatherDescription(next.code)} · ${Math.round(next.temperature)}°C · wind ${Math.round(next.wind)} km/h · updated ${new Date(next.observedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", timeZone: next.timezone })}`);
        }
      } catch {
        if (!disposed) {
          setStatus(lastWeather ? "Weather refresh failed · last reading shown" : "Weather unavailable · time-only sky");
        }
      } finally { clearTimeout(timeout); active = null; if (!disposed) setPending(false); }
    }
    const tick = () => {
      if (lastWeather && Date.now() - lastWeather.observedAt > WEATHER_MAX_AGE) {
        lastWeather = null; setWeather(null); setStatus("Weather expired · time-only sky");
      }
      if (Date.now() - lastAttempt >= 15 * 60_000) void refresh();
    };
    void refresh();
    const interval = window.setInterval(tick, 60_000);
    document.addEventListener("visibilitychange", tick);
    return () => { disposed = true; active?.abort(); clearInterval(interval); document.removeEventListener("visibilitychange", tick); };
  }, [coordinates]);
  return { weather, status, pending, locate };
}
