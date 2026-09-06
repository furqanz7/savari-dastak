import { useEffect, useLayoutEffect, useRef, useState, type ReactNode, type PointerEvent } from "react";
import { catalogueImageUrl } from "./catalogue";
import { DetailImage } from "./ProductDetailCard";
import { productPickerPose, type DetailProduct } from "./productDetail";

/** Full-screen, scroll-snapping pages. A SKU's entire card is a page, including
 * its fixed action bar. The circular picker is a sibling, never a sheet panel. */
export function ProductDetailOverlay({ selectedId, products, supabaseUrl, onSelect, onClose, disabled = false, renderProduct }: {
  selectedId: string; products: DetailProduct[]; supabaseUrl: string;
  onSelect: (id: string) => void; onClose: () => void; disabled?: boolean;
  renderProduct: (product: DetailProduct, select: (id: string) => void) => ReactNode;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const deck = useRef<HTMLDivElement>(null);
  const initialIndex = Math.max(0, products.findIndex((item) => item.id === selectedId));
  const [width, setWidth] = useState(() => Math.min(window.innerWidth, 580));
  const [progress, setProgress] = useState(initialIndex);
  const [targetIndex, setTargetIndex] = useState(initialIndex);
  const settleTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const onSelectRef = useRef(onSelect);
  onSelectRef.current = onSelect;
  const drag = useRef<{ x: number; y: number; scroll: number; ratio: number; moved: boolean; cancelled: boolean } | null>(null);
  const ignoreClick = useRef(false);
  const selectedIndex = Math.max(0, products.findIndex((item) => item.id === selectedId));
  const reduceMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

  useLayoutEffect(() => {
    const element = dialog.current;
    const previousFocus = document.activeElement as HTMLElement | null;
    const previousOverflow = document.body.style.overflow;
    element?.showModal();
    document.body.style.overflow = "hidden";
    if (deck.current) {
      deck.current.scrollLeft = initialIndex * deck.current.clientWidth;
      deck.current.focus({ preventScroll: true });
    }
    return () => {
      clearTimeout(settleTimer.current);
      element?.close();
      document.body.style.overflow = previousOverflow;
      previousFocus?.focus({ preventScroll: true });
    };
    // Opening a new overlay is the only time we acquire focus/scroll ownership.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const element = deck.current;
    if (!element) return;
    const observer = new ResizeObserver(() => setWidth(element.clientWidth));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  useLayoutEffect(() => {
    if (deck.current) deck.current.scrollLeft = selectedIndex * width;
    // Only viewport resizing recentres instantly; selection uses smooth paging.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [width]);

  const navigate = (id: string) => {
    if (disabled) return;
    const index = products.findIndex((item) => item.id === id);
    if (index < 0) return;
    setTargetIndex(index);
    // Mount a distant destination before letting CSS snap to it.
    requestAnimationFrame(() => deck.current?.scrollTo({ left: index * width, behavior: reduceMotion() ? "instant" : "smooth" }));
  };
  const settle = () => {
    if (!deck.current || drag.current?.moved) return;
    const index = Math.min(products.length - 1, Math.max(0, Math.round(deck.current.scrollLeft / width)));
    if (products[index]) { setTargetIndex(index); onSelectRef.current(products[index].id); }
  };
  const scroll = () => {
    if (!deck.current) return;
    setProgress(Math.max(0, Math.min(products.length - 1, deck.current.scrollLeft / width)));
    clearTimeout(settleTimer.current);
    settleTimer.current = setTimeout(settle, 120);
  };

  // Touch card paging is native scrolling. Pointer dragging adds the same
  // interaction for mice and lets the bottom orbit drive the very same pages.
  const startDrag = (event: PointerEvent<HTMLElement>, orbit: boolean) => {
    if (disabled || event.button !== 0 || (!orbit && event.pointerType !== "mouse")) return;
    if (!orbit && (event.target as Element).closest("button, input, a, textarea, [data-product-swipe-ignore]")) return;
    drag.current = { x: event.clientX, y: event.clientY, scroll: deck.current?.scrollLeft ?? 0,
      ratio: orbit ? width / 86 : 1, moved: false, cancelled: false };
    ignoreClick.current = false;
  };
  const moveDrag = (event: PointerEvent<HTMLElement>) => {
    const value = drag.current;
    if (!value || value.cancelled || !deck.current) return;
    const x = event.clientX - value.x; const y = event.clientY - value.y;
    if (!value.moved) {
      if (Math.abs(y) > 8 && Math.abs(y) > Math.abs(x)) { value.cancelled = true; return; }
      if (Math.abs(x) < 8 || Math.abs(x) < Math.abs(y) * 1.5) return;
      value.moved = true;
      ignoreClick.current = true;
      event.currentTarget.setPointerCapture(event.pointerId);
      deck.current.classList.add("is-dragging");
    }
    deck.current.scrollLeft = value.scroll - x * value.ratio;
  };
  const endDrag = () => {
    const value = drag.current;
    drag.current = null;
    deck.current?.classList.remove("is-dragging");
    if (!value?.moved || !deck.current) return;
    const index = Math.min(products.length - 1, Math.max(0, Math.round(deck.current.scrollLeft / width)));
    if (products[index]) navigate(products[index].id);
    settleTimer.current = setTimeout(settle, 180);
  };
  const visible = products.map((item, index) => ({ item, index })).filter(({ index }) =>
    Math.abs(index - progress) < 2.5 || index === targetIndex || index === selectedIndex);

  return <dialog ref={dialog} className="product-detail-dialog" aria-label="Product browser"
    onCancel={(event) => { event.preventDefault(); if (!disabled) onClose(); }}
    onKeyDown={(event) => {
      if ((event.target as Element).closest("input, textarea, [data-product-swipe-ignore]")) return;
      const step = event.key === "ArrowLeft" ? -1 : event.key === "ArrowRight" ? 1 : 0;
      if (step) { event.preventDefault(); const item = products[Math.round(progress) + step]; if (item) navigate(item.id); }
    }}>
    <div className="product-detail-stage">
      <div ref={deck} className={`product-card-deck${disabled ? " is-busy" : ""}`} tabIndex={0} aria-label="Swipe between products"
        onScroll={scroll} onPointerDown={(event) => startDrag(event, false)} onPointerMove={moveDrag}
        onPointerUp={endDrag} onPointerCancel={endDrag}
        onClickCapture={(event) => { if (ignoreClick.current) { event.preventDefault(); event.stopPropagation(); ignoreClick.current = false; } }}>
        <div className="product-card-track" style={{ width: products.length * width }}>
          {visible.map(({ item, index }) => <div key={item.id} className="product-card-page"
            style={{ width, left: index * width }} inert={index !== Math.round(progress)} aria-hidden={index !== Math.round(progress)}>
            {renderProduct(item, navigate)}
          </div>)}
        </div>
      </div>
      <nav className="product-orbit-picker" aria-label="Browse related products"
        onPointerDown={(event) => startDrag(event, true)} onPointerMove={moveDrag} onPointerUp={endDrag} onPointerCancel={endDrag}
        onClickCapture={(event) => { if (ignoreClick.current) { event.preventDefault(); event.stopPropagation(); ignoreClick.current = false; } }}>
        {visible.filter(({ index }) => Math.abs(index - progress) < 3.4).map(({ item, index }) => {
          const distance = index - progress;
          const pose = productPickerPose(distance);
          return <button key={item.id} type="button" disabled={disabled} aria-label={`View ${item.name}, ${item.packSize}`}
            aria-current={index === Math.round(progress)} onClick={() => navigate(item.id)}
            style={{ left: `calc(50% + ${distance * 86}px)`, top: 6 + pose.drop, opacity: pose.opacity,
              transform: `translateX(-50%) scale(${pose.scale}) rotate(${reduceMotion() ? 0 : pose.rotation}deg)` }}>
            <DetailImage source={catalogueImageUrl(supabaseUrl, item.imageKey ?? null)} name="" />
          </button>;
        })}
      </nav>
      <span className="product-detail-sr-only" role="status" aria-live="polite">Product {selectedIndex + 1} of {products.length}</span>
    </div>
  </dialog>;
}
