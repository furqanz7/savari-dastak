import { useRef, useState, type FormEvent } from "react";
import { Check, LoaderCircle, LockKeyhole, Phone, UserRound, X } from "lucide-react";
import { accountProfileValidation, isValidAccountProfile, type AccountProfile } from "./accountProfile";
import { useModalDialog } from "./useModalDialog";

export function AccountProfileSheet({ profile, busy, error, contactMessage, presentation, onDismiss, onSave }: {
  profile: AccountProfile;
  busy: boolean;
  error?: string;
  contactMessage?: string;
  presentation?: "customer";
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

  if (presentation === "customer") return (
    <div className="customer-sheet-backdrop customer-profile-backdrop" role="presentation"
      onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) onDismiss(); }}>
      <form ref={dialog} className="customer-sheet customer-profile-editor" role="dialog" aria-modal="true"
        aria-labelledby="profile-sheet-title" aria-describedby="profile-sheet-description" aria-busy={busy} onSubmit={submit} tabIndex={-1}>
        <header className="customer-profile-editor-heading">
          <div><p className="customer-eyebrow">YOUR ACCOUNT</p><h2 id="profile-sheet-title">Personal details</h2></div>
          <button className="customer-profile-close" type="button" onClick={onDismiss} disabled={busy} aria-label="Close profile editor" title="Close"><X size={20} /></button>
        </header>
        <div className="customer-profile-editor-body">
          <p id="profile-sheet-description">A few details that make Dastak yours.</p>
          <div className="customer-profile-field">
            <label htmlFor="customer-profile-name">Full name</label>
            <div className="customer-profile-name-control"><UserRound size={20} aria-hidden="true" /><input id="customer-profile-name" ref={nameInput}
              autoComplete="name" maxLength={80} required value={displayName} disabled={busy}
              aria-invalid={nameTouched && !!validation.displayName || undefined}
              aria-describedby={nameTouched && validation.displayName ? "account-name-error" : "customer-profile-name-hint"}
              onChange={(event) => setDisplayName(event.target.value)} onBlur={() => setNameTouched(true)} /></div>
            {nameTouched && validation.displayName
              ? <small id="account-name-error" className="customer-profile-field-error" role="alert">{validation.displayName}</small>
              : <small id="customer-profile-name-hint">The name you’d like us to use.</small>}
          </div>
          <section className="customer-profile-contact" aria-labelledby="customer-profile-contact-title">
            <div className="customer-profile-contact-heading"><h3 id="customer-profile-contact-title">Phone number</h3><span><LockKeyhole size={13} aria-hidden="true" />Read only</span></div>
            <div className="customer-profile-phone"><Phone size={19} aria-hidden="true" /><output aria-label="Phone number" aria-describedby="customer-profile-contact-hint">{profile.phoneNumber}</output></div>
            <p id="customer-profile-contact-hint">{contactMessage ?? "This is the contact number on your Dastak profile. Contact Support if you need to change it."}</p>
          </section>
          {error && <div className="customer-profile-save-error" role="alert"><strong>Changes couldn’t be saved</strong><p>{error}</p></div>}
        </div>
        <footer className="customer-profile-editor-actions">
          <button className="secondary-button" type="button" onClick={onDismiss} disabled={busy}>Cancel</button>
          <button className="primary-button" type="submit" disabled={busy}>{busy ? <LoaderCircle className="customer-profile-saving" size={18} aria-hidden="true" /> : <Check size={18} aria-hidden="true" />}<span role="status">{busy ? "Saving changes…" : "Save changes"}</span></button>
        </footer>
      </form>
    </div>
  );

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
        <div className="phone-field-group"><span>Phone number</span><output className="account-verified-phone" aria-label="Phone number">{profile.phoneNumber}</output></div>
        <small>{contactMessage ?? "This required contact number is recorded on your Dastak profile. Contact Support if it must be changed."}</small>
        {error && <p className="order-error" role="alert">{error}</p>}
        <button className="primary-button customer-sheet-action" type="submit" disabled={busy}>
          <Check size={18} /> {busy ? "Saving..." : "Save changes"}
        </button>
      </form>
    </div>
  );
}
