import { useId, useRef } from "react";
import { useModalDialog } from "./useModalDialog";

type Props = {
  action: "sign-out" | "delete-account";
  busy?: boolean;
  message: string;
  onConfirm: () => void;
  onDismiss: () => void;
};

export function AccountActionDialog({ action, busy = false, message, onConfirm, onDismiss }: Props) {
  const titleId = useId();
  const messageId = useId();
  const cancelButton = useRef<HTMLButtonElement>(null);
  const deleting = action === "delete-account";

  const dialog = useModalDialog<HTMLElement>({ busy, onDismiss, initialFocus: cancelButton });

  return <div
    className="customer-sheet-backdrop"
    role="presentation"
    onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) onDismiss(); }}
  >
    <section
      ref={dialog}
      className="customer-sheet delete-account-sheet"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby={titleId}
      aria-describedby={messageId}
      tabIndex={-1}
    >
      <header><div><p className="eyebrow">{deleting ? "Permanent action" : "Account"}</p><h2 id={titleId}>{deleting ? "Delete your account?" : "Sign out of Dastak?"}</h2></div></header>
      <p id={messageId}>{message}</p>
      <button
        className={deleting ? "danger-button" : "primary-button"}
        type="button"
        disabled={busy}
        onClick={onConfirm}
      >
        {busy ? "Please wait..." : deleting ? "Delete account" : "Sign out"}
      </button>
      <button ref={cancelButton} className="secondary-button" type="button" disabled={busy} onClick={onDismiss}>
        {deleting ? "Keep account" : "Cancel"}
      </button>
    </section>
  </div>;
}
