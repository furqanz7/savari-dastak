import type { ReactNode } from "react";
import { createPortal } from "react-dom";

/** Keep fixed dialogs outside the containing block created by glass panels. */
export function ReimaginedModalLayer({ children, enabled = true }: { children: ReactNode; enabled?: boolean }) {
  if (!enabled || typeof document === "undefined") return <>{children}</>;
  return createPortal(<div className="reimagined-address-modal variant-dastak-customer customer-experience">{children}</div>, document.body);
}
