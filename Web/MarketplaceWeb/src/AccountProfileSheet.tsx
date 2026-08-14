import { useEffect, useState, type FormEvent } from "react";
import { Check, X } from "lucide-react";
import { isValidAccountProfile, type AccountProfile } from "./accountProfile";
import { PhoneNumberField } from "./PhoneNumberField";

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
  const draft = { displayName, phoneNumber };

  useEffect(() => {
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !busy) onDismiss();
    };
    document.addEventListener("keydown", dismissOnEscape);
    return () => document.removeEventListener("keydown", dismissOnEscape);
  }, [busy, onDismiss]);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (isValidAccountProfile(draft)) void onSave(draft);
  };

  return (
    <div
      className="customer-sheet-backdrop"
      role="presentation"
      onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) onDismiss(); }}
    >
      <form className="customer-sheet account-profile-sheet" aria-modal="true" aria-labelledby="profile-sheet-title" role="dialog" onSubmit={submit}>
        <header>
          <div><p className="eyebrow">Personal details</p><h2 id="profile-sheet-title">Edit profile</h2></div>
          <button className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close profile editor" title="Close"><X size={19} /></button>
        </header>
        <label><span>Full name</span><input autoComplete="name" maxLength={80} value={displayName} onChange={(event) => setDisplayName(event.target.value)} /></label>
        <div className="phone-field-group"><label htmlFor="account-phone">Phone number</label><PhoneNumberField value={phoneNumber} onChange={setPhoneNumber} id="account-phone" /></div>
        <small>{contactMessage ?? "Your number is shared only when an active delivery requires contact. It is not used to sign in."}</small>
        {error && <p className="order-error" role="alert">{error}</p>}
        <button className="primary-button customer-sheet-action" type="submit" disabled={busy || !isValidAccountProfile(draft)}>
          <Check size={18} /> {busy ? "Saving..." : "Save changes"}
        </button>
      </form>
    </div>
  );
}
