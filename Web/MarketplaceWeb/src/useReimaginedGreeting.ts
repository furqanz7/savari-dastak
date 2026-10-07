import { useEffect, useState } from "react";

// Device-local time; no location permission, profile or network request needed.
export function reimaginedGreeting(date: Date): string {
  const hour = date.getHours();
  return hour >= 5 && hour < 12 ? "Good morning" : hour >= 12 && hour < 18 ? "Good afternoon" : "Good evening";
}

export function useReimaginedGreeting(): string {
  const [greeting, setGreeting] = useState(() => reimaginedGreeting(new Date()));
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const refresh = () => {
      clearTimeout(timer);
      const now = new Date();
      setGreeting(reimaginedGreeting(now));
      if (document.visibilityState === "hidden") return;
      const hour = now.getHours();
      const next = new Date(now);
      next.setHours(hour < 5 ? 5 : hour < 12 ? 12 : hour < 18 ? 18 : 29, 0, 0, 0);
      timer = setTimeout(refresh, Math.max(1, next.getTime() - now.getTime()));
    };
    refresh();
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => { clearTimeout(timer); window.removeEventListener("focus", refresh); document.removeEventListener("visibilitychange", refresh); };
  }, []);
  return greeting;
}
