import { useEffect, useRef, useState } from "react";
import { Crosshair, MapPin } from "lucide-react";
import type * as Leaflet from "leaflet";
import "leaflet/dist/leaflet.css";
import "./design/maps.css";

export type MapPoint = { latitude: number; longitude: number; label: string; kind?: "pickup" | "dropoff" | "courier" };
export function DastakMap({ points, editable = false, disabled = false, onPinChange, route = false, label = "Delivery map" }: {
  points: MapPoint[]; editable?: boolean; disabled?: boolean; route?: boolean; label?: string;
  onPinChange?: (point: { latitude: number; longitude: number }) => void;
}) {
  const container = useRef<HTMLDivElement>(null);
  const runtime = useRef<{ L: typeof Leaflet; map: Leaflet.Map; layer: Leaflet.LayerGroup } | undefined>(undefined);
  const latest = useRef({ points, editable, disabled, onPinChange, route });
  useEffect(() => { latest.current = { points, editable, disabled, onPinChange, route }; }, [points, editable, disabled, onPinChange, route]);
  const [ready, setReady] = useState(false), [failed, setFailed] = useState(false), [tileError, setTileError] = useState(false);
  const userMoved = useRef(false);
  const pointSignature = JSON.stringify(points);
  const recenter = () => {
    const state = runtime.current; if (!state) return;
    const valid = latest.current.points.filter(validPoint);
    if (valid.length > 1) state.map.fitBounds(state.L.latLngBounds(valid.map(p => [p.latitude, p.longitude])), { padding: [42, 42], maxZoom: 16, animate: false });
    else if (valid[0]) state.map.setView([valid[0].latitude, valid[0].longitude], editable ? 18 : 16, { animate: false });
  };
  useEffect(() => {
    let cancelled = false, observer: ResizeObserver | undefined;
    void import("leaflet").then(L => {
      if (cancelled || !container.current) return;
      const map = L.map(container.current, { center: [22.5, 79], zoom: 4, zoomControl: true, scrollWheelZoom: false });
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19, referrerPolicy: "strict-origin",
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a>',
      }).on("tileerror", () => { if (!cancelled) setTileError(true); }).addTo(map);
      L.control.scale({ imperial: false }).addTo(map);
      runtime.current = { L, map, layer: L.layerGroup().addTo(map) };
      map.on("dragstart", () => { userMoved.current = true; });
      map.on("click", (event: Leaflet.LeafletMouseEvent) => {
        const current = latest.current;
        if (current.editable && !current.disabled) current.onPinChange?.({ latitude: event.latlng.lat, longitude: event.latlng.wrap().lng });
      });
      if (typeof ResizeObserver !== "undefined") {
        observer = new ResizeObserver(() => map.invalidateSize({ pan: false })); observer.observe(container.current);
      }
      setReady(true);
    }).catch(() => { if (!cancelled) setFailed(true); });
    return () => { cancelled = true; observer?.disconnect(); runtime.current?.map.remove(); runtime.current = undefined; };
  }, []);
  useEffect(() => {
    const state = runtime.current; if (!state || !ready) return;
    const { L, map, layer } = state;
    const restoreFocus = editable && container.current?.contains(document.activeElement) && document.activeElement?.classList.contains("dastak-map-pin");
    layer.eachLayer(item => { if (item instanceof L.Marker) { item.closeTooltip(); item.unbindTooltip(); } });
    layer.clearLayers();
    const valid = latest.current.points.filter(validPoint);
    valid.forEach(point => {
      const icon = L.divIcon({ className: `dastak-map-pin ${point.kind ?? "dropoff"}`, iconSize: [34, 42], iconAnchor: [17, 40],
        html: '<span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg></span>' });
      const marker = L.marker([point.latitude, point.longitude], { icon, draggable: editable && !disabled, title: point.label, alt: point.label, keyboard: true }).addTo(layer);
      const text = document.createElement("span"); text.textContent = point.label;
      marker.bindTooltip(text, { direction: "top", offset: [0, -34] });
      if (restoreFocus) marker.getElement()?.focus();
      marker.on("dragend", () => {
        if (!latest.current.editable || latest.current.disabled) return;
        const pin = marker.getLatLng().wrap(); latest.current.onPinChange?.({ latitude: pin.lat, longitude: pin.lng });
      });
      marker.getElement()?.addEventListener("keydown", event => {
        if (!editable || disabled || !["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(event.key)) return;
        event.preventDefault(); event.stopPropagation();
        const pin = marker.getLatLng(); const step = event.shiftKey ? .0001 : .00001;
        const latitude = Math.max(-85, Math.min(85, pin.lat + (event.key === "ArrowUp" ? step : event.key === "ArrowDown" ? -step : 0)));
        const longitude = pin.lng + (event.key === "ArrowRight" ? step : event.key === "ArrowLeft" ? -step : 0);
        latest.current.onPinChange?.({ latitude, longitude: L.latLng(latitude, longitude).wrap().lng });
      });
    });
    if (route && valid.length > 1) L.polyline(valid.map(p => [p.latitude, p.longitude]), { color: "#35644c", weight: 4, dashArray: "8 10", opacity: .8 }).addTo(layer);
    if (!userMoved.current || editable) {
      if (valid.length > 1) map.fitBounds(L.latLngBounds(valid.map(p => [p.latitude, p.longitude])), { padding: [42, 42], maxZoom: 16, animate: false });
      else if (valid[0]) map.setView([valid[0].latitude, valid[0].longitude], editable ? Math.max(map.getZoom(), 18) : 16, { animate: false });
    }
  }, [ready, pointSignature, editable, disabled, route]);
  return <div className="dastak-map" data-editable={editable}>
    <div ref={container} className="dastak-map-canvas" title={label} aria-label={label} />
    {!ready || failed ? <div className="dastak-map-status" role="status"><MapPin size={22} /><span>{failed ? "Map could not load. Search or use your current location instead." : "Loading map…"}</span></div> : null}
    {ready ? <button className="dastak-map-recenter" type="button" onClick={() => { userMoved.current = false; recenter(); }} aria-label="Recenter map"><Crosshair size={19} /></button> : null}
    <p className="dastak-map-hint">{tileError ? "Map tiles are unavailable. Your selected coordinates are kept." : editable ? "Drag the pin or tap the map to set your exact location." : route ? "Locations shown · dashed line is not a road route." : "Drag to explore · use + / − to zoom."}</p>
  </div>;
}
function validPoint(point: MapPoint) { return Number.isFinite(point.latitude) && Math.abs(point.latitude) <= 90 && Number.isFinite(point.longitude) && Math.abs(point.longitude) <= 180; }
