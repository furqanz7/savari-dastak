import { useRef, useState, type FormEvent } from "react";
import { Check, X } from "lucide-react";
import { accountProfileValidation, isValidAccountProfile, type AccountProfile } from "./accountProfile";
import { PhoneNumberField } from "./PhoneNumberField";
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
  const [phoneNumber, setPhoneNumber] = useState(profile.phoneNumber);
  const [nameTouched, setNameTouched] = useState(false);
  const [phoneTouched, setPhoneTouched] = useState(false);
  const nameInput = useRef<HTMLInputElement>(null);
  const draft = { displayName, phoneNumber };
  const validation = accountProfileValidation(draft);
  const dialog = useModalDialog<HTMLFormElement>({ busy, onDismiss, initialFocus: nameInput });

  const submit = (event: FormEvent) => {
    event.preventDefault();
    setNameTouched(true);
    setPhoneTouched(true);
    if (isValidAccountProfile(draft)) void onSave(draft);
  };

  return (
    <div
      className="customer-sheet-backdrop"
      role="presentation"
      onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) onDismiss(); }}
    >
      <form ref={dialog} className="customer-sheet account-profile-sheet" aria-modal="true" aria-labelledby="profile-sheet-title" role="dialog" onSubmit={submit} tabIndex={-1}>
        <header>
          <div><p className="eyebrow">Personal details</p><h2 id="profile-sheet-title">Edit profile</h2></div>
          <button className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close profile editor" title="Close"><X size={19} /></button>
        </header>
        <label><span>Full name</span><input ref={nameInput} autoComplete="name" maxLength={80} required value={displayName} aria-invalid={nameTouched && !!validation.displayName || undefined} aria-describedby={nameTouched && validation.displayName ? "account-name-error" : undefined} onChange={(event) => setDisplayName(event.target.value)} onBlur={() => setNameTouched(true)} /></label>
        {nameTouched && validation.displayName && <small id="account-name-error" className="field-error" role="alert">{validation.displayName}</small>}
        <div className="phone-field-group"><label htmlFor="account-phone">Phone number</label><PhoneNumberField value={phoneNumber} onChange={setPhoneNumber} id="account-phone" required invalid={phoneTouched && !!validation.phoneNumber} describedBy={phoneTouched && validation.phoneNumber ? "account-phone-error" : undefined} onBlur={() => setPhoneTouched(true)} /></div>
        {phoneTouched && validation.phoneNumber && <small id="account-phone-error" className="field-error" role="alert">{validation.phoneNumber}</small>}
        <small>{contactMessage ?? "Your number is shared only when an active delivery requires contact. It is not used to sign in."}</small>
        {error && <p className="order-error" role="alert">{error}</p>}
        <button className="primary-button customer-sheet-action" type="submit" disabled={busy}>
          <Check size={18} /> {busy ? "Saving..." : "Save changes"}
        </button>
      </form>
    </div>
  );
}
