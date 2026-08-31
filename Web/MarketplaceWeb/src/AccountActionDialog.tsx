import { useId, useRef } from "react";
import { LogOut, ShieldAlert } from "lucide-react";
import { useModalDialog } from "./useModalDialog";

type Props = {
  action: "sign-out" | "delete-account";
  busy?: boolean;
  deleteLabel?: string;
  message: string;
  onConfirm: () => void;
  onDismiss: () => void;
};

export function AccountActionDialog({ action, busy = false, deleteLabel = "profile", message, onConfirm, onDismiss }: Props) {
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
      <header className="account-sheet-heading">
        <span className={`account-dialog-mark ${deleting ? "destructive" : ""}`} aria-hidden="true">
          {deleting ? <ShieldAlert size={21} /> : <LogOut size={21} />}
        </span>
        <div><p className="eyebrow">{deleting ? "Profile access" : "Account"}</p><h2 id={titleId}>{deleting ? `Delete ${deleteLabel}?` : "Sign out of Dastak?"}</h2></div>
      </header>
      <p id={messageId}>{message}</p>
      <button
        className={deleting ? "danger-button" : "primary-button"}
        type="button"
        disabled={busy}
        onClick={onConfirm}
      >
        {busy ? "Please wait..." : deleting ? `Delete ${deleteLabel}` : "Sign out"}
      </button>
      <button ref={cancelButton} className="secondary-button" type="button" disabled={busy} onClick={onDismiss}>
        {deleting ? `Keep ${deleteLabel}` : "Cancel"}
      </button>
    </section>
  </div>;
}
