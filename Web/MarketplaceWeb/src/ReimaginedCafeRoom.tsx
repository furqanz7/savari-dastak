import { memo, useEffect, useRef, useState } from "react";
import type { CafeScene } from "./reimaginedCafeScene";
import "./design/reimaginedGroceryRoom.css";

export const ReimaginedCafeRoom = memo(function ReimaginedCafeRoom({ atCounter = false }: { atCounter?: boolean }) {
  const canvas = useRef<HTMLCanvasElement>(null); const runtime = useRef<CafeScene | null>(null);
  const counter = useRef(atCounter); const [status, setStatus] = useState("Preparing the café");
  useEffect(() => { counter.current = atCounter; runtime.current?.setCounter(atCounter); }, [atCounter]);
  useEffect(() => {
    let cancelled = false; const element = canvas.current;
    if (!element || !window.WebGLRenderingContext) { setStatus("Café 3D preview unavailable"); return; }
    const lost = (event: Event) => { event.preventDefault(); runtime.current?.dispose(); runtime.current = null; setStatus("Café 3D paused · reload preview to retry"); };
    element.addEventListener("webglcontextlost", lost);
    void import("./reimaginedCafeScene").then(({ createCafeScene }) => {
      if (!cancelled) runtime.current = createCafeScene(element, counter.current, value => { if (!cancelled) setStatus(value); });
    }).catch(() => { if (!cancelled) setStatus("Café 3D preview unavailable"); });
    return () => { cancelled = true; element.removeEventListener("webglcontextlost", lost); runtime.current?.dispose(); runtime.current = null; };
  }, []);
  return <div className="grocery-room-3d" data-environment-study="cafe-interior-v1" data-status={status}>
    <canvas ref={canvas} className="grocery-room-canvas" aria-label="Three-dimensional café interior preview" role="img" />
    <div className="grocery-room-vignette" /><span className="grocery-room-status" role="status">{status}</span>
  </div>;
});
