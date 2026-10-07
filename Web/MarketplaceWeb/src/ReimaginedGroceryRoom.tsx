import { memo, useEffect, useRef, useState } from "react";
import type { GroceryScene } from "./reimaginedGroceryScene";
import type { OutdoorWeather } from "./reimaginedWeather";
import "./design/reimaginedGroceryRoom.css";

export const ReimaginedGroceryRoom = memo(function ReimaginedGroceryRoom({ atCounter = false, outside = false, weather = null, blinkRequest = 0, playStaff = false, eyesClosed = false }: { atCounter?: boolean; outside?: boolean; weather?: OutdoorWeather | null; blinkRequest?: number; playStaff?: boolean; eyesClosed?: boolean }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const runtime = useRef<GroceryScene | null>(null);
  const counter = useRef(atCounter);
  const exterior = useRef(outside);
  const playback = useRef(playStaff);
  const heldEyes = useRef(eyesClosed);
  const currentWeather = useRef(weather);
  const [status, setStatus] = useState("Preparing the store");
  useEffect(() => { counter.current = atCounter; runtime.current?.setCounter(atCounter); }, [atCounter]);
  useEffect(() => { exterior.current = outside; runtime.current?.setOutside(outside); }, [outside]);
  useEffect(() => { currentWeather.current = weather; runtime.current?.setWeather(weather); }, [weather]);
  useEffect(() => { if (blinkRequest > 0) runtime.current?.testBlink(); }, [blinkRequest]);
  useEffect(() => { playback.current = playStaff; runtime.current?.setStaffPlayback(playStaff); }, [playStaff]);
  useEffect(() => { heldEyes.current = eyesClosed; runtime.current?.setEyesClosed(eyesClosed); }, [eyesClosed]);
  useEffect(() => {
    let cancelled = false;
    const element = canvas.current;
    if (!element || !window.WebGLRenderingContext) { setStatus("3D unavailable · shopping remains available"); return; }
    const contextLost = (event: Event) => { event.preventDefault(); runtime.current?.dispose(); runtime.current = null; setStatus("3D paused · shopping remains available"); };
    element.addEventListener("webglcontextlost", contextLost);
    void import("./reimaginedGroceryScene").then(({ createGroceryScene }) => {
      if (cancelled) return;
      runtime.current = createGroceryScene(element, { weather: currentWeather.current, counter: counter.current, outside: exterior.current, playStaff: playback.current, eyesClosed: heldEyes.current, onStatus: value => { if (!cancelled) setStatus(value); } });
    }).catch(() => { if (!cancelled) setStatus("3D unavailable · shopping remains available"); });
    return () => { cancelled = true; element.removeEventListener("webglcontextlost", contextLost); runtime.current?.dispose(); runtime.current = null; };
  }, []);
  return <div className="grocery-room-3d" aria-hidden="true" data-environment-study="grocery-realtime-v1" data-status={status}>
    <canvas ref={canvas} className="grocery-room-canvas" />
    <div className="grocery-room-vignette" />
    <span className="grocery-room-status">{status}</span>
  </div>;
});
