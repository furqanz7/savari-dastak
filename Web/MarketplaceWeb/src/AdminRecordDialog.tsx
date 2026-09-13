import { useRef, type ReactNode } from "react";
import { X } from "lucide-react";
import { useModalDialog } from "./useModalDialog";

export function AdminRecordDialog({ title, busy, children, onDismiss }: { title: string; busy: boolean; children: ReactNode; onDismiss: () => void }) {
  const close = useRef<HTMLButtonElement>(null);
  const dialog = useModalDialog<HTMLElement>({ onDismiss, busy, initialFocus: close, layered: true });
  return <div className="v1-overlay admin-sku-overlay" role="presentation"><section ref={dialog} className="v1-sheet admin-sku-sheet" role="dialog" aria-modal="true" aria-label={`Edit ${title}`} tabIndex={-1}>
    <header><div><p>EXACT SKU</p><h2>{title}</h2></div><button ref={close} type="button" disabled={busy} onClick={onDismiss} aria-label="Close product editor"><X size={19} /></button></header>
    {children}
  </section></div>;
}
