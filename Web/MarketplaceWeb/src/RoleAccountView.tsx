import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Bell, LogOut, ShieldCheck, Trash2, UserRound } from "lucide-react";
import { AccountProfileSheet } from "./AccountProfileSheet";
import { AccountActionDialog } from "./AccountActionDialog";
import {
  AccountProfileRequestError,
  deleteAccount,
  snapshotAccountProfile,
  updateAccountProfile,
  type AccountProfile,
} from "./accountProfile";

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
  const auth = useMemo(
    () => ({ accessToken, supabaseUrl, publishableKey }),
    [accessToken, publishableKey, supabaseUrl],
  );
  const copy = roleAccountCopy(roleName);
  const [profile, setProfile] = useState<AccountProfile>({ displayName: displayName ?? "", phoneNumber: phoneNumber ?? "" });
  const [editing, setEditing] = useState(false);
  const [confirmingSignOut, setConfirmingSignOut] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>();

  useEffect(() => {
    let active = true;
    setLoading(true);
    void snapshotAccountProfile(auth).then((snapshot) => {
      if (active) setProfile(snapshot);
    }).catch((loadError) => {
      if (!active) return;
      if (loadError instanceof AccountProfileRequestError && loadError.status === 401) {
        onSignOut();
        return;
      }
      setError(message(loadError, "Your account details could not be loaded."));
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => { active = false; };
  }, [auth, onSignOut]);

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
    <header className="role-account-heading"><p className="eyebrow">Dastak {roleName}</p><h1>Account</h1><p>{copy.introduction}</p></header>
    <button className="role-profile" type="button" onClick={() => setEditing(true)} disabled={loading}>
      <span><UserRound size={24} /></span>
      <div><strong>{loading ? "Loading account" : profile.displayName || `${roleName} account`}</strong><small>{roleName}</small>{profile.phoneNumber && <small>{profile.phoneNumber}</small>}{email && <small>{email}</small>}</div>
      <b>{loading ? "" : "Edit"}</b>
    </button>

    <section className="role-account-section" aria-labelledby="role-workspace-title">
      <h2 id="role-workspace-title">Workspace</h2>
      <dl className="role-account-list">
        <div><dt><ShieldCheck size={18} /> Access</dt><dd>{accessLabel}</dd></div>
        <div><dt><Bell size={18} /> Updates</dt><dd>In app</dd></div>
      </dl>
    </section>

    <section className="role-account-section" aria-labelledby="role-privacy-title">
      <h2 id="role-privacy-title">Privacy and data</h2>
      <div className="role-privacy"><ShieldCheck size={20} /><div><strong>Contact stays task-specific</strong><p>{copy.privacy}</p></div></div>
    </section>
    {children}
    {error && <p className="order-error" role="alert">{error}</p>}
    <div className="role-account-actions">
      <button className="secondary-button" type="button" onClick={() => setConfirmingSignOut(true)}><LogOut size={18} /> Sign out</button>
      {allowsAccountDeletion && <button className="danger-button" type="button" onClick={() => setConfirmingDelete(true)}><Trash2 size={18} /> Delete account</button>}
    </div>
    {editing && <AccountProfileSheet profile={profile} busy={busy} error={error} contactMessage={copy.editorPrivacy} onDismiss={() => { setEditing(false); setError(undefined); }} onSave={save} />}
    {confirmingSignOut && <AccountActionDialog
      action="sign-out"
      message="You'll need to sign in again to access this account."
      onConfirm={onSignOut}
      onDismiss={() => setConfirmingSignOut(false)}
    />}
    {confirmingDelete && <AccountActionDialog
      action="delete-account"
      busy={busy}
      message="Your role access is removed and retained records are detached from your identity. This cannot be undone."
      onConfirm={() => void remove()}
      onDismiss={() => setConfirmingDelete(false)}
    />}
  </section>;
}

function message(error: unknown, fallback: string) { return error instanceof Error ? error.message : fallback; }

function roleAccountCopy(roleName: string) {
  if (roleName === "Merchant") return {
    introduction: "Your store identity, contact details and access controls.",
    privacy: "Your unverified number is used only when an active order requires store contact. It is never used to sign in.",
    editorPrivacy: "Used only when an active order requires store contact. It is not used to sign in.",
  };
  if (roleName === "Delivery Partner") return {
    introduction: "Your delivery identity, availability access and account controls.",
    privacy: "Your unverified number is shared only during an assigned delivery when contact is required. It is never used to sign in.",
    editorPrivacy: "Shared only during an assigned delivery when contact is required. It is not used to sign in.",
  };
  return {
    introduction: "Your identity, access and account controls.",
    privacy: "Your unverified number is used only when an active task requires contact. It is never used to sign in.",
    editorPrivacy: "Used only when an active task requires contact. It is not used to sign in.",
  };
}
