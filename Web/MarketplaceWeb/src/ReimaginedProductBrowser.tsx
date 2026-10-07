import { useRef, useState, type CSSProperties, type PointerEvent, type ReactNode } from "react";
import { ArrowLeft, ArrowRight, Package, X } from "lucide-react";
import { catalogueImageUrl } from "./catalogue";
import type { V1CatalogueSku } from "./dastakV1";
import { productPickerPose, productSwipeStep } from "./productDetail";

/** Panel-native navigation: one page per product family, never one per pack. */
export function ReimaginedProductBrowser({ groups, selectedId, onSelect, onClose, supabaseUrl, children }: {
  groups: V1CatalogueSku[][]; selectedId: string; onSelect: (id: string) => void;
  onClose?: () => void; supabaseUrl: string; children: (select: (id: string) => void) => ReactNode;
}) {
  const index = groups.findIndex(packs => packs.some(sku => sku.id === selectedId));
  const [remembered, setRemembered] = useState<Record<string, string>>({});
  const drag = useRef<{ x: number; y: number; pointerId: number } | null>(null);
  const ignoreClick = useRef(false);
  const packFor = (packs: V1CatalogueSku[]) => packs.find(sku => sku.id === selectedId)
    ?? packs.find(sku => sku.id === remembered[packs[0].id]) ?? packs[0];
  const select = (id: string) => {
    const target = groups.find(packs => packs.some(sku => sku.id === id));
    const current = groups[index];
    setRemembered(previous => ({ ...previous, ...(current ? { [current[0].id]: selectedId } : {}), ...(target ? { [target[0].id]: id } : {}) }));
    onSelect(id);
  };
  const move = (step: number) => { const packs = index >= 0 ? groups[index + step] : undefined; if (packs) select(packFor(packs).id); };
  const start = (event: PointerEvent<HTMLElement>, orbit = false) => {
    ignoreClick.current = false;
    drag.current = null;
    if (event.button !== 0 || (!orbit && (event.target as Element).closest("button, a, input, select, textarea, [data-product-swipe-ignore]"))) return;
    drag.current = { x: event.clientX, y: event.clientY, pointerId: event.pointerId };
  };
  const track = (event: PointerEvent<HTMLElement>) => {
    const origin = drag.current;
    if (!origin || origin.pointerId !== event.pointerId) return;
    if (productSwipeStep(event.clientX - origin.x, event.clientY - origin.y)) {
      ignoreClick.current = true;
      event.currentTarget.setPointerCapture?.(event.pointerId);
    }
  };
  const end = (event: PointerEvent<HTMLElement>) => {
    const origin = drag.current; drag.current = null;
    if (!origin || origin.pointerId !== event.pointerId) return;
    const step = productSwipeStep(event.clientX - origin.x, event.clientY - origin.y);
    if (step) { ignoreClick.current = true; move(step); }
  };
  const cancel = () => { drag.current = null; ignoreClick.current = false; };
  return <div className="reimagined-product-browser" onKeyDown={event => {
    if ((event.target as Element).closest("input, select, textarea, [data-product-swipe-ignore]")) return;
    const step = event.key === "ArrowLeft" ? -1 : event.key === "ArrowRight" ? 1 : 0;
    if (step) { event.preventDefault(); move(step); }
  }}>
    <nav className="reimagined-product-paging" aria-label="Product navigation">
      <button type="button" aria-label="Previous product" disabled={index <= 0} onClick={() => move(-1)}><ArrowLeft size={20} /></button>
      <output aria-live="polite">Product {index + 1} of {groups.length}</output>
      <button type="button" aria-label="Next product" disabled={index < 0 || index >= groups.length - 1} onClick={() => move(1)}><ArrowRight size={20} /></button>
      {onClose ? <button type="button" className="reimagined-detail-close" aria-label="Close product details" title="Close product details" onClick={onClose}><X size={18} /></button> : null}
    </nav>
    {groups.length > 1 ? <nav className="reimagined-product-orbit" aria-label="Circular product picker"
      onPointerDown={event => start(event, true)} onPointerMove={track} onPointerUp={end} onPointerCancel={cancel}
      onClickCapture={event => { if (ignoreClick.current) { event.preventDefault(); event.stopPropagation(); ignoreClick.current = false; } }}>
      {groups.slice(Math.max(0, index - 2), index + 3).map(packs => {
        const position = groups.indexOf(packs), distance = position - index;
        const pose = productPickerPose(distance), sku = packFor(packs);
        const url = sku.imageKey && (sku.imageKey.startsWith("local/") || supabaseUrl) ? catalogueImageUrl(supabaseUrl, sku.imageKey) : undefined;
        return <button type="button" key={`${packs[0].id}:${sku.id}:${url ?? "missing"}`} aria-label={`Browse ${sku.name}, ${sku.packSize}`} aria-current={distance === 0 ? "true" : undefined}
          title={`${sku.name} · ${sku.packSize}`} onClick={() => select(sku.id)}
          style={{ "--orbit-distance": distance, "--orbit-scale": pose.scale, "--orbit-drop": `${pose.drop}px`, "--orbit-rotation": `${pose.rotation}deg` } as CSSProperties}>
          {url ? <img key={url} src={url} alt="" loading="lazy" draggable={false} onError={event => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.setAttribute("data-image-unavailable", "true"); }} /> : null}
          <span className="reimagined-orbit-fallback" data-fallback={!url}><Package size={24} aria-hidden="true" /></span><span className="reimagined-orbit-label">{sku.name}</span>
        </button>;
      })}
    </nav> : null}
    <div className="reimagined-product-page" key={selectedId} role="region" aria-label="Swipe between products" tabIndex={0}
      onPointerDown={event => start(event)} onPointerMove={track} onPointerUp={end} onPointerCancel={cancel}>
      {children(select)}
    </div>
  </div>;
}
