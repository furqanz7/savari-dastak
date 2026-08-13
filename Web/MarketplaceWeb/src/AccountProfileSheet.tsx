import { useState, type FormEvent } from "react";
import { Check, X } from "lucide-react";
import { isValidAccountProfile, type AccountProfile } from "./accountProfile";

export function AccountProfileSheet({ profile, busy, error, onDismiss, onSave }: {
  profile: AccountProfile;
  busy: boolean;
  error?: string;
  onDismiss: () => void;
  onSave: (profile: AccountProfile) => Promise<void>;
}) {
  const [displayName, setDisplayName] = useState(profile.displayName);
  const [phoneNumber, setPhoneNumber] = useState(profile.phoneNumber);
  const draft = { displayName, phoneNumber };

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (isValidAccountProfile(draft)) void onSave(draft);
  };

  return (
    <div className="customer-sheet-backdrop" role="presentation">
      <form className="customer-sheet account-profile-sheet" aria-modal="true" aria-labelledby="profile-sheet-title" role="dialog" onSubmit={submit}>
        <header>
          <div><p className="eyebrow">Personal details</p><h2 id="profile-sheet-title">Edit profile</h2></div>
          <button className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close profile editor" title="Close"><X size={19} /></button>
        </header>
        <label><span>Full name</span><input autoComplete="name" maxLength={80} value={displayName} onChange={(event) => setDisplayName(event.target.value)} /></label>
        <label><span>Phone number with country code</span><input type="tel" inputMode="tel" autoComplete="tel" value={phoneNumber} onChange={(event) => setPhoneNumber(event.target.value)} /></label>
        <small>Your number is shared only when needed for an active delivery.</small>
        {error && <p className="order-error" role="alert">{error}</p>}
        <button className="primary-button customer-sheet-action" type="submit" disabled={busy || !isValidAccountProfile(draft)}>
          <Check size={18} /> {busy ? "Saving..." : "Save changes"}
        </button>
      </form>
    </div>
  );
}
