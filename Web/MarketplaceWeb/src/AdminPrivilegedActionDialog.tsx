import { useId, useMemo, useRef, useState } from "react";
import { AlertTriangle, Check, X } from "lucide-react";
import { useModalDialog } from "./useModalDialog";

export type AdminPrivilegedActionIntent = {
  eyebrow?: string;
  title: string;
  entityLabel: string;
  entityValue: string;
  currentState: string;
  resultingState: string;
  consequence: string;
  confirmLabel: string;
  tone?: "primary" | "danger";
  reason?: string;
  reasonOptions?: readonly string[];
  reasonMinimumLength?: number;
  confirmationValue?: string;
  confirmationLabel?: string;
};

type Props = {
  intent: AdminPrivilegedActionIntent;
  busy?: boolean;
  error?: string;
  notice?: string;
  reconciliationBlocked?: boolean;
  onReconcile?: () => Promise<void>;
  onConfirm: (reason: string) => Promise<void> | void;
  onDismiss: () => void;
};

export function AdminPrivilegedActionDialog({
  intent,
  busy = false,
  error,
  notice,
  reconciliationBlocked = false,
  onReconcile,
  onConfirm,
  onDismiss,
}: Props) {
  const titleId = useId();
  const consequenceId = useId();
  const cancelButton = useRef<HTMLButtonElement>(null);
  const options = intent.reasonOptions ?? [];
  const [reasonChoice, setReasonChoice] = useState(options[0] ?? "");
  const [reasonDetail, setReasonDetail] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const reason = useMemo(() => intent.reason ?? [reasonChoice, reasonDetail.trim()]
    .filter(Boolean).join(" — "), [intent.reason, reasonChoice, reasonDetail]);
  const requiredLength = intent.reasonMinimumLength ?? (options.length ? 3 : 0);
  const otherDetailRequired = reasonChoice.trim().toLowerCase() === "other";
  const reasonValid = (requiredLength === 0 || reason.trim().length >= requiredLength) &&
    (!otherDetailRequired || reasonDetail.trim().length >= 3);
  const expectedConfirmation = intent.confirmationValue?.trim().toLowerCase();
  const confirmationValid = !expectedConfirmation || confirmation.trim().toLowerCase() === expectedConfirmation;
  const dialog = useModalDialog<HTMLElement>({ busy, onDismiss, initialFocus: cancelButton, layered: true });

  return <div className="admin-confirmation-backdrop" role="presentation" onMouseDown={(event) => {
    if (event.target === event.currentTarget && !busy) onDismiss();
  }}>
    <section
      ref={dialog}
      className="admin-confirmation-dialog"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby={titleId}
      aria-describedby={consequenceId}
      aria-busy={busy}
      tabIndex={-1}
    >
      <header>
        <span aria-hidden="true"><AlertTriangle size={21} /></span>
        <div><p className="eyebrow">{intent.eyebrow ?? "Privileged action"}</p><h2 id={titleId}>{intent.title}</h2></div>
        <button type="button" className="icon-button" disabled={busy} onClick={onDismiss} aria-label="Close confirmation"><X size={18} /></button>
      </header>

      <div className="admin-confirmation-body">
      <dl className="admin-confirmation-summary">
        <div><dt>{intent.entityLabel}</dt><dd>{intent.entityValue}</dd></div>
        <div><dt>Current state</dt><dd>{intent.currentState}</dd></div>
        <div><dt>Resulting state</dt><dd>{intent.resultingState}</dd></div>
      </dl>
      <p id={consequenceId} className="admin-confirmation-consequence">{intent.consequence}</p>

      {options.length > 0 ? <fieldset>
        <legend>Operator reason</legend>
        {options.map((option) => <label key={option}><input type="radio" name={`${titleId}-reason`} value={option} checked={reasonChoice === option} disabled={busy} onChange={() => setReasonChoice(option)} /><span>{option}</span></label>)}
      </fieldset> : intent.reason ? <div className="admin-confirmation-recorded-reason"><strong>Recorded reason</strong><p>{intent.reason}</p></div> : null}

      {options.length > 0 ? <label className="admin-confirmation-detail">{otherDetailRequired ? "Detail (required for Other)" : "Optional detail"}<textarea value={reasonDetail} disabled={busy} required={otherDetailRequired} maxLength={400} rows={3} onChange={(event) => setReasonDetail(event.target.value)} placeholder="Add context for the audit record" /></label> : null}

      {expectedConfirmation ? <label className="admin-confirmation-match">
        {intent.confirmationLabel ?? <>Type <strong>{intent.confirmationValue}</strong> to confirm</>}
        <input autoComplete="off" spellCheck={false} value={confirmation} disabled={busy} onChange={(event) => setConfirmation(event.target.value)} />
      </label> : null}

      {notice ? <p className="admin-confirmation-notice" role="status">{notice}</p> : null}
      {error ? <p className="order-error" role="alert">{error}</p> : null}
      </div>
      <footer>
        <small className="admin-confirmation-safety">Review carefully. This action is governed and recorded.</small>
        <button ref={cancelButton} className="secondary-button" type="button" disabled={busy} onClick={onDismiss}>Cancel</button>
        {reconciliationBlocked && onReconcile
          ? <button className="primary-button" type="button" disabled={busy} onClick={() => void onReconcile()}>Reconcile state</button>
          : <button className={intent.tone === "danger" ? "danger-button" : "primary-button"} type="button" disabled={busy || !reasonValid || !confirmationValid || reconciliationBlocked} onClick={() => void onConfirm(reason.trim())}>
            {busy ? "Working…" : <><Check size={17} /> {intent.confirmLabel}</>}
          </button>}
      </footer>
    </section>
  </div>;
}
