import { useState, type ReactNode } from "react";
import { Globe2, LogOut, ShieldCheck, Trash2, UserRound } from "lucide-react";
import { AccountProfileSheet } from "./AccountProfileSheet";
import { deleteAccount, updateAccountProfile, type AccountProfile } from "./accountProfile";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  roleName: string;
  accessLabel?: string;
  supabaseUrl: string;
  publishableKey: string;
  allowsAccountDeletion?: boolean;
  onSignOut: () => void;
  children?: ReactNode;
};

export function RoleAccountView({
  accessToken, displayName, email, phoneNumber, roleName, accessLabel = "Active",
  supabaseUrl, publishableKey, allowsAccountDeletion = true, onSignOut, children,
}: Props) {
  const auth = { accessToken, supabaseUrl, publishableKey };
  const [profile, setProfile] = useState<AccountProfile>({ displayName: displayName ?? "", phoneNumber: phoneNumber ?? "" });
  const [editing, setEditing] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  const save = async (draft: AccountProfile) => {
    setBusy(true); setError(undefined);
    try {
      setProfile(await updateAccountProfile({ ...auth, ...draft }));
      setEditing(false);
    } catch (saveError) {
      setError(message(saveError, "Your profile could not be updated."));
    } finally { setBusy(false); }
  };

  const remove = async () => {
    setBusy(true); setError(undefined);
    try {
      await deleteAccount(auth);
      onSignOut();
    } catch (deleteError) {
      setError(message(deleteError, "Your account could not be deleted."));
      setConfirmingDelete(false); setBusy(false);
    }
  };

  return <section className="role-account">
    <header className="merchant-orders-heading"><div><p className="eyebrow">Dastak {roleName}</p><h1>Account</h1><p>Your identity, access and account controls.</p></div></header>
    <button className="role-profile" type="button" onClick={() => setEditing(true)}>
      <span><UserRound size={24} /></span>
      <div><strong>{profile.displayName || `${roleName} account`}</strong><small>{roleName}</small><small>{profile.phoneNumber}</small>{email && <small>{email}</small>}</div>
      <b>Edit</b>
    </button>
    <dl className="role-account-list">
      <div><dt><ShieldCheck size={18} /> Access</dt><dd>{accessLabel}</dd></div>
      <div><dt><Globe2 size={18} /> Language</dt><dd>Follows browser</dd></div>
    </dl>
    <div className="role-privacy"><strong>Privacy and data</strong><p>Your phone number is unverified and is shared only when an active order requires contact. You can edit your identity or remove your account here.</p></div>
    {children}
    {error && <p className="order-error" role="alert">{error}</p>}
    <div className="role-account-actions">
      <button className="secondary-button" type="button" onClick={onSignOut}><LogOut size={18} /> Sign out</button>
      {allowsAccountDeletion && <button className="danger-button" type="button" onClick={() => setConfirmingDelete(true)}><Trash2 size={18} /> Delete account</button>}
    </div>
    {editing && <AccountProfileSheet profile={profile} busy={busy} error={error} onDismiss={() => { setEditing(false); setError(undefined); }} onSave={save} />}
    {confirmingDelete && <div className="customer-sheet-backdrop" role="presentation"><section className="customer-sheet delete-account-sheet" role="alertdialog" aria-modal="true" aria-labelledby="role-delete-account-title">
      <header><div><p className="eyebrow">Permanent action</p><h2 id="role-delete-account-title">Delete your account?</h2></div></header>
      <p>Your role access is removed and retained records are detached from your identity. This cannot be undone.</p>
      <button className="danger-button" type="button" disabled={busy} onClick={() => void remove()}>{busy ? "Deleting..." : "Delete account"}</button>
      <button className="secondary-button" type="button" disabled={busy} onClick={() => setConfirmingDelete(false)}>Keep account</button>
    </section></div>}
  </section>;
}

function message(error: unknown, fallback: string) { return error instanceof Error ? error.message : fallback; }
