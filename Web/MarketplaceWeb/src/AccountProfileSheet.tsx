import { useRef, useState, type FormEvent } from "react";
import { Check, UserRound, X } from "lucide-react";
import { accountProfileValidation, isValidAccountProfile, type AccountProfile } from "./accountProfile";
import { useModalDialog } from "./useModalDialog";

export function AccountProfileSheet({ profile, busy, error, contactMessage, onDismiss, onSave }: {
  profile: AccountProfile;
  busy: boolean;
  error?: string;
  contactMessage?: string;
  onDismiss: () => void;
  onSave: (profile: AccountProfile) => Promise<void>;
}) {
  const [displayName, setDisplayName] = useState(profile.displayName);
  const [nameTouched, setNameTouched] = useState(false);
  const nameInput = useRef<HTMLInputElement>(null);
  const draft = { displayName, phoneNumber: profile.phoneNumber };
  const validation = accountProfileValidation(draft);
  const dialog = useModalDialog<HTMLFormElement>({ busy, onDismiss, initialFocus: nameInput });

  const submit = (event: FormEvent) => {
    event.preventDefault();
    setNameTouched(true);
    if (isValidAccountProfile(draft)) void onSave(draft);
  };

  return (
    <div
      className="customer-sheet-backdrop"
      role="presentation"
      onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) onDismiss(); }}
    >
      <form ref={dialog} className="customer-sheet account-profile-sheet" aria-modal="true" aria-labelledby="profile-sheet-title" role="dialog" onSubmit={submit} tabIndex={-1}>
        <header className="account-sheet-heading">
          <span className="account-dialog-mark" aria-hidden="true"><UserRound size={21} /></span>
          <div><p className="eyebrow">Personal details</p><h2 id="profile-sheet-title">Edit profile</h2></div>
          <button className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close profile editor" title="Close"><X size={19} /></button>
        </header>
        <label><span>Full name</span><input ref={nameInput} autoComplete="name" maxLength={80} required value={displayName} aria-invalid={nameTouched && !!validation.displayName || undefined} aria-describedby={nameTouched && validation.displayName ? "account-name-error" : undefined} onChange={(event) => setDisplayName(event.target.value)} onBlur={() => setNameTouched(true)} /></label>
        {nameTouched && validation.displayName && <small id="account-name-error" className="field-error" role="alert">{validation.displayName}</small>}
        <div className="phone-field-group"><span>Verified phone number</span><output className="account-verified-phone" aria-label="Verified phone number">{profile.phoneNumber}</output></div>
        <small>{contactMessage ?? "Your verified number identifies your Dastak account. Contact Support if it must be changed."}</small>
        {error && <p className="order-error" role="alert">{error}</p>}
        <button className="primary-button customer-sheet-action" type="submit" disabled={busy}>
          <Check size={18} /> {busy ? "Saving..." : "Save changes"}
        </button>
      </form>
    </div>
  );
}
