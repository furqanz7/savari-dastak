import { useId, useMemo, useRef, useState } from "react";
import { AppleLogo, GoogleLogo } from "./IdentityProviderLogos";
import type { CustomerIdentity, CustomerOAuthProvider } from "./accountProfile";
import { useModalDialog } from "./useModalDialog";

export function DeleteAccountDialog({
  busy,
  error,
  identities,
  notice,
  reauthenticationRequired,
  warning,
  onConfirm,
  onDismiss,
  onReauthenticate,
}: {
  busy: boolean;
  error?: string;
  identities: CustomerIdentity[];
  notice?: string;
  reauthenticationRequired: boolean;
  warning: string;
  onConfirm: () => void;
  onDismiss: () => void;
  onReauthenticate: (provider: CustomerOAuthProvider) => void;
}) {
  const titleId = useId();
  const messageId = useId();
  const [confirmation, setConfirmation] = useState("");
  const cancelButton = useRef<HTMLButtonElement>(null);
  const dialog = useModalDialog<HTMLElement>({ busy, onDismiss, initialFocus: cancelButton });
  const providers = useMemo(
    () => [...new Set(identities.map((identity) => identity.provider))],
    [identities],
  );
  const confirmed = confirmation.trim().toUpperCase() === "DELETE";

  return <div className="customer-sheet-backdrop" role="presentation" onMouseDown={(event) => {
    if (event.target === event.currentTarget && !busy) onDismiss();
  }}>
    <section ref={dialog} className="customer-sheet delete-account-sheet" role="alertdialog" aria-modal="true" aria-labelledby={titleId} aria-describedby={messageId} tabIndex={-1}>
      <header><div><p className="eyebrow">Permanent action</p><h2 id={titleId}>Delete your account?</h2></div></header>
      <p id={messageId}>{warning}</p>
      {!reauthenticationRequired && <label className="delete-account-confirmation">
        <span>Type <strong>DELETE</strong> to confirm</span>
        <input autoComplete="off" value={confirmation} disabled={busy} onChange={(event) => setConfirmation(event.target.value)} aria-label="Type DELETE to confirm account deletion" />
      </label>}
      {reauthenticationRequired && <div className="delete-account-reauthentication">
        <strong>Verify it’s you</strong>
        <p>For your security, sign in again with a method already linked to this account.</p>
        <div>
          {providers.map((provider) => <button key={provider} className={`provider-button ${provider}`} type="button" disabled={busy} onClick={() => onReauthenticate(provider)}>
            {provider === "apple" ? <AppleLogo /> : <GoogleLogo />}
            Continue with {provider === "apple" ? "Apple" : "Google"}
          </button>)}
        </div>
      </div>}
      {error && <p className="order-error" role="alert">{error}</p>}
      {notice && <p className="success-text" role="status">{notice}</p>}
      {!reauthenticationRequired && <button className="danger-button" type="button" disabled={busy || !confirmed} onClick={onConfirm}>{busy ? "Please wait…" : "Delete account"}</button>}
      <button ref={cancelButton} className="secondary-button" type="button" disabled={busy} onClick={onDismiss}>Keep account</button>
    </section>
  </div>;
}
