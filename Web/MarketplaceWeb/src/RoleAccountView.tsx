import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import {
  BadgeCheck,
  Bell,
  Bike,
  CarFront,
  ChevronRight,
  Footprints,
  Hand,
  LogOut,
  ShieldCheck,
  Siren,
  Trash2,
} from "lucide-react";
import { AccountProfileSheet } from "./AccountProfileSheet";
import { AccountActionDialog } from "./AccountActionDialog";
import {
  AccountProfileRequestError,
  deleteAccount,
  snapshotAccountProfile,
  updateAccountProfile,
  type AccountProfile,
} from "./accountProfile";
import type { DeliveryMethod, DeliveryPartnerSnapshot } from "./delivery";

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
  deliveryPartner?: DeliveryPartnerSnapshot;
  deliveryPartnerLoading?: boolean;
  deliveryPartnerError?: string;
  onRefreshPartner?: () => void;
  onOpenWorkspace?: () => void;
  onSignOut: () => void;
  children?: ReactNode;
};

export function RoleAccountView({
  accessToken, displayName, email, phoneNumber, roleName, accessLabel = "Active",
  supabaseUrl, publishableKey, allowsAccountDeletion = true, deliveryPartner,
  deliveryPartnerLoading = false, deliveryPartnerError, onRefreshPartner,
  onOpenWorkspace, onSignOut, children,
}: Props) {
  const auth = useMemo(
    () => ({ accessToken, supabaseUrl, publishableKey }),
    [accessToken, publishableKey, supabaseUrl],
  );
  const copy = roleAccountCopy(roleName);
  const isDeliveryPartner = roleName === "Delivery Partner";
  const [profile, setProfile] = useState<AccountProfile>({ displayName: displayName ?? "", phoneNumber: phoneNumber ?? "" });
  const [editing, setEditing] = useState(false);
  const [confirmingSignOut, setConfirmingSignOut] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadFailed, setLoadFailed] = useState(false);
  const [error, setError] = useState<string>();

  const loadProfile = useCallback(async () => {
    setLoading(true);
    setLoadFailed(false);
    setError(undefined);
    try {
      setProfile(await snapshotAccountProfile(auth));
    } catch (loadError) {
      if (loadError instanceof AccountProfileRequestError && loadError.status === 401) {
        onSignOut();
        return;
      }
      setLoadFailed(true);
      setError(message(loadError, "Your account details could not be loaded."));
    } finally {
      setLoading(false);
    }
  }, [auth, onSignOut]);

  useEffect(() => { void loadProfile(); }, [loadProfile]);

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
    <header className="role-account-heading">
      <p className="eyebrow">{roleName}</p>
      <h1>Your account</h1>
      <p>{copy.introduction}</p>
    </header>

    <button className="role-profile" type="button" onClick={() => setEditing(true)} disabled={loading}>
      <span className="role-profile-avatar" aria-hidden="true">{initials(profile.displayName || roleName)}</span>
      <span className="role-profile-copy">
        <strong>{loading ? "Loading account" : profile.displayName || `${roleName} account`}</strong>
        {profile.phoneNumber && <small>{profile.phoneNumber}</small>}
        {email && <small>{email}</small>}
      </span>
      <span className="role-profile-edit">Edit</span>
    </button>

    {isDeliveryPartner && <PartnerCredentials
      partner={deliveryPartner}
      accessLabel={accessLabel}
      loading={deliveryPartnerLoading}
      error={deliveryPartnerError}
      onRetry={onRefreshPartner}
    />}

    {!isDeliveryPartner && <section className="role-account-section" aria-labelledby="role-access-title">
      <h2 id="role-access-title">Work profile</h2>
      <div className="role-account-group">
        <AccountRow icon={<ShieldCheck size={19} />} title="Access" detail="Your current Dastak workspace permission" value={accessLabel} />
      </div>
    </section>}

    <section className="role-account-section" aria-labelledby="role-preferences-title">
      <h2 id="role-preferences-title">Preferences</h2>
      <div className="role-account-group">
        <AccountRow icon={<Bell size={19} />} title="Notifications" detail="In-app and delivery updates" value="In app" />
        <AccountRow icon={<Hand size={19} />} title="Privacy and data" detail={copy.privacy} />
      </div>
    </section>

    {isDeliveryPartner && <section className="role-account-section" aria-labelledby="role-support-title">
      <h2 id="role-support-title">Support and safety</h2>
      <div className="role-account-group">
        {onOpenWorkspace && <button type="button" className="role-account-row" onClick={onOpenWorkspace}>
          <span className="role-row-icon"><Bike size={19} /></span>
          <span><strong>Delivery workspace</strong><small>Open your current assignment</small></span>
          <ChevronRight size={18} />
        </button>}
        <a className="role-account-row destructive" href="tel:112">
          <span className="role-row-icon"><Siren size={19} /></span>
          <span><strong>Emergency assistance</strong><small>Call India emergency services</small></span>
          <ChevronRight size={18} />
        </a>
      </div>
    </section>}

    {children}

    <section className="role-account-section" aria-labelledby="role-controls-title">
      <h2 id="role-controls-title">Account controls</h2>
      <div className="role-account-group">
        <button type="button" className="role-account-row" onClick={() => setConfirmingSignOut(true)}>
          <span className="role-row-icon"><LogOut size={19} /></span>
          <span><strong>Sign out</strong><small>End this session on this device</small></span>
          <ChevronRight size={18} />
        </button>
        {allowsAccountDeletion && <button type="button" className="role-account-row destructive" onClick={() => setConfirmingDelete(true)}>
          <span className="role-row-icon"><Trash2 size={19} /></span>
          <span><strong>Delete account</strong><small>Permanently remove your Dastak account</small></span>
          <ChevronRight size={18} />
        </button>}
      </div>
    </section>

    {error && !editing && <div className="role-account-error" role="alert">
      <p>{error}</p>
      {loadFailed && <button type="button" onClick={() => void loadProfile()}>Try again</button>}
    </div>}

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

function PartnerCredentials({
  partner, accessLabel, loading, error, onRetry,
}: {
  partner?: DeliveryPartnerSnapshot;
  accessLabel: string;
  loading: boolean;
  error?: string;
  onRetry?: () => void;
}) {
  const approved = partner?.onboardingState === "approved";
  const method = partner?.deliveryMethod;
  const vehicleVerified = method === "bike" || method === "auto" || method === "car";
  const statusLabel = approved ? accessLabel : loading ? "Checking" : partner?.onboardingState === "pending" ? "Pending" : partner?.onboardingState === "rejected" ? "Review" : "Unavailable";
  const statusTitle = approved ? "Verified partner" : loading ? "Checking partner access" : "Partner access unavailable";
  const statusMessage = approved ? "Your identity and work method are approved" : loading ? "Loading your approved work details" : "Refresh to check your work profile";

  return <section className="role-account-section" aria-labelledby="role-work-profile-title">
    <h2 id="role-work-profile-title">Work profile</h2>
    <div className="partner-credentials">
      <header>
        <span className={`partner-verification-icon ${approved ? "approved" : ""}`}><BadgeCheck size={21} /></span>
        <span><strong>{statusTitle}</strong><small>{statusMessage}</small></span>
        <b>{statusLabel}</b>
      </header>
      <dl>
        <CredentialRow icon={methodIcon(method)} title="Delivery method" value={methodLabel(method)} />
        {partner?.vehicleRegistrationNumber && <CredentialRow
          icon={<CarFront size={18} />}
          title="Vehicle"
          value={partner.vehicleMakeModel || partner.vehicleRegistrationNumber}
          detail={partner.vehicleMakeModel ? partner.vehicleRegistrationNumber : undefined}
        />}
        <CredentialRow icon={<ShieldCheck size={18} />} title="Verification" value={approved ? (vehicleVerified ? "Identity and vehicle verified" : "Identity verified") : "Not verified"} />
        <CredentialRow icon={<BadgeCheck size={18} />} title="Availability" value={partner ? (partner.availability?.status === "online" ? "Online" : "Offline") : "Not available"} />
      </dl>
    </div>
    {error && <div className="partner-credentials-error" role="alert"><span>{error}</span>{onRetry && <button type="button" onClick={onRetry}>Try again</button>}</div>}
    <p className="partner-credentials-note">Identity, delivery method and vehicle changes require Dastak review to protect customers, merchants and partners.</p>
  </section>;
}

function AccountRow({ icon, title, detail, value }: { icon: ReactNode; title: string; detail: string; value?: string }) {
  return <div className="role-account-row">
    <span className="role-row-icon">{icon}</span>
    <span><strong>{title}</strong><small>{detail}</small></span>
    {value && <b>{value}</b>}
  </div>;
}

function CredentialRow({ icon, title, value, detail }: { icon: ReactNode; title: string; value: string; detail?: string }) {
  return <div><dt>{icon} {title}</dt><dd>{value}{detail && <small>{detail}</small>}</dd></div>;
}

function initials(name: string) {
  return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase() || "D";
}

function methodLabel(method?: DeliveryMethod | null) {
  switch (method) {
    case "walking": return "Walking";
    case "bicycle": return "Bicycle";
    case "bike": return "Motorbike";
    case "auto": return "Auto";
    case "car": return "Car";
    default: return "Not available";
  }
}

function methodIcon(method?: DeliveryMethod | null) {
  if (method === "walking") return <Footprints size={18} />;
  if (method === "bicycle" || method === "bike") return <Bike size={18} />;
  if (method === "auto" || method === "car") return <CarFront size={18} />;
  return <ShieldCheck size={18} />;
}

function message(error: unknown, fallback: string) { return error instanceof Error ? error.message : fallback; }

function roleAccountCopy(roleName: string) {
  if (roleName === "Merchant") return {
    introduction: "Manage your store identity, contact details and account access.",
    privacy: "Your number is used only when an active order requires store contact.",
    editorPrivacy: "Used only when an active order requires store contact. It is not used to sign in.",
  };
  if (roleName === "Delivery Partner") return {
    introduction: "Manage the identity, verified work details and permissions used while you deliver.",
    privacy: "Your number is shared only during an assigned delivery when contact is required.",
    editorPrivacy: "Shared only during an assigned delivery when contact is required. It is not used to sign in.",
  };
  return {
    introduction: "Manage your identity, permissions and account access.",
    privacy: "Your number is used only when an active task requires contact.",
    editorPrivacy: "Used only when an active task requires contact. It is not used to sign in.",
  };
}
