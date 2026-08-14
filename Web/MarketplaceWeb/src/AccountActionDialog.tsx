import { useEffect, useId, useRef } from "react";

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

  useEffect(() => {
    cancelButton.current?.focus();
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !busy) onDismiss();
    };
    document.addEventListener("keydown", dismissOnEscape);
    return () => document.removeEventListener("keydown", dismissOnEscape);
  }, [busy, onDismiss]);

  return <div
    className="customer-sheet-backdrop"
    role="presentation"
    onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) onDismiss(); }}
  >
    <section
      className="customer-sheet delete-account-sheet"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby={titleId}
      aria-describedby={messageId}
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
