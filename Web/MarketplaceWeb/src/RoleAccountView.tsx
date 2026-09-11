import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  AlertTriangle,
  BadgeCheck,
  Bike,
  Footprints,
  Bell,
  CarFront,
  ChevronRight,
  ClipboardList,
  Hand,
  LayoutGrid,
  LogOut,
  Mail,
  MonitorSmartphone,
  Navigation,
  Pencil,
  Phone,
  ShieldCheck,
  Siren,
  Store,
  Truck,
  Trash2,
  X,
} from "lucide-react";
import { AccountProfileSheet } from "./AccountProfileSheet";
import { AccountActionDialog } from "./AccountActionDialog";
import { AccountSessionsSheet } from "./AccountSessionsSheet";
import { CustomerNotice } from "./CustomerUI";
import { useModalDialog } from "./useModalDialog";
import { userFacingError } from "./userFacingError";
import {
  AccountProfileRequestError,
  accountDeletionIdempotencyKey,
  clearAccountDeletionIdempotencyKey,
  deleteAccount,
  snapshotAccountProfile,
  updateAccountProfile,
  type AccountProfile,
  type DastakPersona,
} from "./accountProfile";
import {
  deliveryPartnerVerificationState,
  requiresVehicleVerification,
  type DeliveryMethod,
  type DeliveryPartnerSnapshot,
} from "./delivery";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  roleName: string;
  persona?: DastakPersona;
  accessLabel?: string;
  supabaseUrl: string;
  publishableKey: string;
  allowsAccountDeletion?: boolean;
  deliveryPartner?: DeliveryPartnerSnapshot;
  deliveryPartnerLoading?: boolean;
  deliveryPartnerError?: string;
  onRefreshPartner?: () => void;
  onOpenWorkspace?: () => void;
  notificationSurface?: ReactNode;
  onSignOut: () => void;
};

type AccountDetail = "access" | "notifications" | "privacy";

export function RoleAccountView({
  accessToken, displayName, email, phoneNumber, roleName, accessLabel = "Active",
  persona,
  supabaseUrl, publishableKey, allowsAccountDeletion = true, deliveryPartner,
  deliveryPartnerLoading = false, deliveryPartnerError, onRefreshPartner,
  onOpenWorkspace, notificationSurface, onSignOut,
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
  const [sessionsOpen, setSessionsOpen] = useState(false);
  const [detail, setDetail] = useState<AccountDetail>();
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const accountDeletionKey = useRef(accountDeletionIdempotencyKey(persona ?? "CUSTOMER"));
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
      if (!persona) throw new Error("This app cannot delete a persona.");
      await deleteAccount({ ...auth, persona, idempotencyKey: accountDeletionKey.current });
      clearAccountDeletionIdempotencyKey(persona);
      onSignOut();
    } catch (deleteError) {
      setError(message(deleteError, "Your account could not be deleted."));
      setConfirmingDelete(false); setBusy(false);
    }
  };

  return <section className="role-account">
    <header className="role-account-heading">
      <p className="eyebrow">{roleName}</p>
      <h1>{roleName === "Merchant" ? "Your merchant account" : "Your account"}</h1>
      <p>{copy.introduction}</p>
    </header>

    <button className="role-profile" type="button" aria-label={roleName === "Merchant" ? "Edit merchant profile" : isDeliveryPartner ? "Edit delivery profile" : undefined} onClick={() => setEditing(true)} disabled={loading}>
      <span className="role-profile-main">
        <span className="role-profile-avatar" aria-hidden="true">{initials(profile.displayName || roleName)}</span>
        <span className="role-profile-copy">
          <strong>{loading ? "Loading account" : profile.displayName || `${roleName} account`}</strong>
          <small>{roleName}</small>
        </span>
        <span className="role-profile-edit" aria-hidden="true"><Pencil size={16} />{roleName === "Merchant" || isDeliveryPartner ? <span>Edit profile</span> : null}</span>
      </span>
      {!loading && <span className="role-profile-contacts">
        <span><Phone size={15} />{profile.phoneNumber || "Add a contact number"}</span>
        <span><Mail size={15} />{email || "Sign-in email unavailable"}</span>
      </span>}
    </button>

    {isDeliveryPartner && <PartnerCredentials
      partner={deliveryPartner}
      accessLabel={accessLabel}
      loading={deliveryPartnerLoading}
      error={deliveryPartnerError}
      onRetry={onRefreshPartner}
    />}

    {roleName === "Merchant" && onOpenWorkspace && <section className="role-account-section" aria-labelledby="role-store-workspace-title">
      <h2 id="role-store-workspace-title">Your business</h2>
      <div className="role-account-group">
        <AccountButtonRow
          icon={<Store size={19} />}
          title="Store and availability"
          detail="Manage products, your menu and new-order acceptance"
          onClick={onOpenWorkspace}
        />
      </div>
    </section>}

    <section className="role-account-section" aria-labelledby="role-preferences-title">
      <h2 id="role-preferences-title">Preferences</h2>
      <div className="role-account-group">
        {!isDeliveryPartner && <AccountButtonRow
          icon={<ShieldCheck size={19} />}
          title="Access and approval"
          detail="Server-approved workspace permissions"
          value={accessLabel}
          onClick={() => setDetail("access")}
        />}
        {!notificationSurface ? <AccountButtonRow
          icon={<Bell size={19} />}
          title="Notifications"
          detail="Order and account updates"
          value="In app"
          onClick={() => setDetail("notifications")}
        /> : null}
        <AccountButtonRow
          icon={<Hand size={19} />}
          title="Privacy and data"
          detail={copy.privacy}
          onClick={() => setDetail("privacy")}
        />
        <AccountButtonRow
          icon={<MonitorSmartphone size={19} />}
          title="Devices and sessions"
          detail="Review active sign-ins and sign out other devices"
          onClick={() => setSessionsOpen(true)}
        />
      </div>
    </section>

    {notificationSurface ? <section className="role-account-section" aria-label={isDeliveryPartner ? "Browser delivery alerts" : "Browser order alerts"}><h2>{isDeliveryPartner ? "Delivery alerts" : "Order alerts"}</h2>{notificationSurface}</section> : null}

    {isDeliveryPartner && <section className="role-account-section" aria-labelledby="role-support-title">
      <h2 id="role-support-title">Support and safety</h2>
      <div className="role-account-group">
        {onOpenWorkspace && <button type="button" className="role-account-row" onClick={onOpenWorkspace}>
          <span className="role-row-icon"><Navigation size={19} /></span>
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

    <section className="role-account-section" aria-labelledby="role-controls-title">
      <h2 id="role-controls-title">Account controls</h2>
      <div className="role-account-group">
        <button type="button" className="role-account-row" onClick={() => setConfirmingSignOut(true)}>
          <span className="role-row-icon"><LogOut size={19} /></span>
          <span><strong>Sign out</strong><small>End this session on this device</small></span>
          <ChevronRight size={18} />
        </button>
        {allowsAccountDeletion && persona && <button type="button" className="role-account-row destructive" onClick={() => setConfirmingDelete(true)}>
          <span className="role-row-icon"><Trash2 size={19} /></span>
          <span><strong>Delete {roleName}</strong><small>Remove only this {roleName.toLowerCase()} profile</small></span>
          <ChevronRight size={18} />
        </button>}
      </div>
    </section>

    {error && !editing && (roleName === "Merchant" ? <CustomerNotice title="Account details couldn’t update" onRetry={loadFailed ? () => void loadProfile() : undefined}>{error}</CustomerNotice> : <div className="role-account-error" role="alert">
      <p>{error}</p>
      {loadFailed && <button type="button" onClick={() => void loadProfile()}>Try again</button>}
    </div>)}

    {editing && <div className={roleName === "Merchant" ? "customer-experience merchant-profile-presentation" : isDeliveryPartner ? "customer-experience rider-profile-presentation" : undefined}><AccountProfileSheet presentation={roleName === "Merchant" || isDeliveryPartner ? "customer" : undefined} profile={profile} busy={busy} error={error} contactMessage={copy.editorPrivacy} onDismiss={() => { setEditing(false); setError(undefined); }} onSave={save} /></div>}
    {detail && <RoleAccountDetailSheet
      detail={detail}
      roleName={roleName}
      accessLabel={accessLabel}
      onDismiss={() => setDetail(undefined)}
    />}
    {sessionsOpen && <AccountSessionsSheet
      accessToken={accessToken}
      supabaseUrl={supabaseUrl}
      publishableKey={publishableKey}
      appName={roleName}
      onDismiss={() => setSessionsOpen(false)}
      onSessionExpired={onSignOut}
    />}
    {confirmingSignOut && <AccountActionDialog
      action="sign-out"
      message="You'll need to sign in again to access this account."
      onConfirm={onSignOut}
      onDismiss={() => setConfirmingSignOut(false)}
    />}
    {confirmingDelete && <AccountActionDialog
      action="delete-account"
      busy={busy}
      deleteLabel={roleName}
      message={`Only your ${roleName} profile and access will be removed. Your other Dastak profiles stay available, and you can recover this profile later with the same verified identity.`}
      onConfirm={() => void remove()}
      onDismiss={() => setConfirmingDelete(false)}
    />}
  </section>;
}

function RoleAccountDetailSheet({ detail, roleName, accessLabel, onDismiss }: {
  detail: AccountDetail;
  roleName: string;
  accessLabel: string;
  onDismiss: () => void;
}) {
  const content = accountDetailContent(detail, roleName, accessLabel);

  useEffect(() => {
    if (roleName === "Merchant") return;
    const dismissOnEscape = (event: KeyboardEvent) => { if (event.key === "Escape") onDismiss(); };
    document.addEventListener("keydown", dismissOnEscape);
    return () => document.removeEventListener("keydown", dismissOnEscape);
  }, [onDismiss, roleName]);

  const body = <>
      <header>
        <div><p className="eyebrow">{content.eyebrow}</p><h2 id="account-detail-title">{content.title}</h2></div>
        <button className="icon-button" type="button" onClick={onDismiss} aria-label="Close" title="Close"><X size={19} /></button>
      </header>
      <p className="role-detail-introduction">{content.introduction}</p>
      {content.status && <div className="role-detail-status"><ShieldCheck size={20} /><span><strong>{content.status}</strong><small>{content.statusDetail}</small></span></div>}
      <div className="role-detail-list">
        {content.items.map((item) => <div key={item.title}>
          <span className="role-row-icon">{item.icon}</span>
          <span><strong>{item.title}</strong><small>{item.detail}</small></span>
        </div>)}
      </div>
      <button type="button" className="primary-button role-detail-done" onClick={onDismiss}>Done</button>
  </>;
  if (roleName === "Merchant") return <MerchantAccountDetailDialog onDismiss={onDismiss}>{body}</MerchantAccountDetailDialog>;
  return <div className="customer-sheet-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onDismiss(); }}>
    <section className="customer-sheet role-account-detail-sheet" role="dialog" aria-modal="true" aria-labelledby="account-detail-title">{body}</section>
  </div>;
}

function MerchantAccountDetailDialog({ children, onDismiss }: { children: ReactNode; onDismiss: () => void }) {
  const dialog = useModalDialog<HTMLElement>({ onDismiss });
  return <div className="customer-sheet-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onDismiss(); }}>
    <section ref={dialog} tabIndex={-1} className="customer-sheet role-account-detail-sheet" role="dialog" aria-modal="true" aria-labelledby="account-detail-title">{children}</section>
  </div>;
}

function accountDetailContent(detail: AccountDetail, roleName: string, accessLabel: string) {
  if (detail === "access") return {
    eyebrow: roleName,
    title: "Workspace access",
    introduction: "Dastak approves permissions on the server. Editing profile details cannot grant or change access.",
    status: `Access ${accessLabel.toLowerCase()}`,
    statusDetail: roleName === "Merchant" ? "This account can operate its approved store." : "This account can use its approved workspace.",
    items: roleName === "Merchant" ? [
      { icon: <ClipboardList size={18} />, title: "Orders", detail: "Receive and manage orders for your approved store." },
      { icon: <LayoutGrid size={18} />, title: "Catalogue", detail: "Maintain products, prices and availability." },
      { icon: <Store size={18} />, title: "Store", detail: "Manage trading status and store details." },
    ] : [
      { icon: <ShieldCheck size={18} />, title: "Approved operations", detail: "Use only the workspace granted to this account." },
    ],
  };
  if (detail === "notifications") return {
    eyebrow: "Notifications",
    title: "Stay ready",
    introduction: roleName === "Merchant"
      ? "Time-sensitive store and order updates remain visible in your Orders workspace."
      : "Time-sensitive work and account updates remain visible inside Dastak.",
    status: "In-app updates active",
    statusDetail: "Browser push is not requested by this web app.",
    items: [
      { icon: <Bell size={18} />, title: "Order updates", detail: "New orders, cancellations and fulfilment changes." },
      { icon: <ShieldCheck size={18} />, title: "Account updates", detail: "Approval and account status changes." },
    ],
  };
  return {
    eyebrow: "Privacy",
    title: "Your data",
    introduction: "Dastak uses the minimum account information required to operate your approved workspace.",
    status: undefined,
    statusDetail: undefined,
    items: [
      { icon: <Phone size={18} />, title: "Contact number", detail: roleName === "Merchant" ? "Shared only when an active order requires store contact." : "Shared only when active work requires contact." },
      { icon: <ShieldCheck size={18} />, title: "Approved access", detail: "Server permissions, not profile fields, determine which workspace opens." },
      { icon: <Hand size={18} />, title: "Records and control", detail: "Order and financial records may be retained where required; account controls remain available here." },
    ],
  };
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
  const verification = partner ? deliveryPartnerVerificationState(partner) : "unverified";
  const needsVehicleReview = verification === "vehicle_review_required";
  const fullyVerified = verification === "identity_verified" || verification === "identity_and_vehicle_verified";
  const vehicleRequired = method ? requiresVehicleVerification(method) : false;
  const statusLabel = needsVehicleReview ? "Action needed" : approved ? accessLabel : loading ? "Checking" : partner?.onboardingState === "pending" ? "Pending" : partner?.onboardingState === "rejected" ? "Review" : "Unavailable";
  const statusTitle = needsVehicleReview ? "Vehicle review required" : approved ? "Verified partner" : loading ? "Checking partner access" : partner?.onboardingState === "pending" ? "Review in progress" : partner?.onboardingState === "rejected" ? "Review required" : "Partner access unavailable";
  const statusMessage = needsVehicleReview ? "Vehicle details are missing from this legacy approval" : approved ? "Your identity and work method are approved" : loading ? "Loading your work details" : partner?.reviewReason ?? "Refresh to check your work profile";
  const verificationLabel = verification === "identity_and_vehicle_verified"
    ? "Identity and vehicle verified"
    : verification === "identity_verified"
      ? "Identity verified"
      : needsVehicleReview ? "Vehicle verification required" : "Not verified";

  return <section className="role-account-section" aria-labelledby="role-work-profile-title">
    <h2 id="role-work-profile-title">Work profile</h2>
    <div className="partner-credentials">
      <header>
        <span className={`partner-verification-icon ${fullyVerified ? "approved" : needsVehicleReview ? "review" : ""}`}>
          {needsVehicleReview ? <AlertTriangle size={21} /> : <BadgeCheck size={21} />}
        </span>
        <span><strong>{statusTitle}</strong><small>{statusMessage}</small></span>
        <b className={needsVehicleReview ? "review" : undefined}>{statusLabel}</b>
      </header>
      <dl>
        <CredentialRow icon={methodIcon(method)} title="Delivery method" value={methodLabel(method)} />
        {partner && vehicleRequired && <CredentialRow
          icon={<CarFront size={18} />}
          title="Vehicle"
          value={partner.vehicleMakeModel || partner.vehicleRegistrationNumber || "Details missing"}
          detail={partner.vehicleMakeModel && partner.vehicleRegistrationNumber ? partner.vehicleRegistrationNumber : undefined}
        />}
        <CredentialRow icon={<ShieldCheck size={18} />} title="Verification" value={verificationLabel} />
        <CredentialRow icon={<BadgeCheck size={18} />} title="Availability" value={partner ? (partner.availability?.status === "online" ? "Online" : "Offline") : "Not available"} />
      </dl>
    </div>
    {error && <div className="partner-credentials-error" role="alert"><span>{error}</span>{onRetry && <button type="button" onClick={onRetry}>Try again</button>}</div>}
    <p className="partner-credentials-note">Identity, delivery method and vehicle changes require Dastak review to protect customers, merchants and partners.</p>
  </section>;
}

function AccountButtonRow({ icon, title, detail, value, onClick }: {
  icon: ReactNode;
  title: string;
  detail: string;
  value?: string;
  onClick: () => void;
}) {
  return <button type="button" className="role-account-row" onClick={onClick}>
    <span className="role-row-icon">{icon}</span>
    <span><strong>{title}</strong><small>{detail}</small></span>
    <span className="role-row-trailing">{value && <b>{value}</b>}<ChevronRight size={18} /></span>
  </button>;
}

function CredentialRow({ icon, title, value, detail }: { icon: ReactNode; title: string; value: string; detail?: string }) {
  return <div><dt>{icon} {title}</dt><dd>{value}{detail && <small>{detail}</small>}</dd></div>;
}

function initials(name: string) {
  return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase() || "D";
}

function methodLabel(method?: DeliveryMethod | null) {
  switch (method) {
    case "retired": return "Retired delivery method";
    case "walking": return "Walking";
    case "bicycle": return "Bicycle";
    case "bike": return "Motorbike";
    case "auto": return "Auto";
    case "motorbike": return "Motorbike";
    case "scooter": return "Scooter";
    case "goods_vehicle": return "Tempo / goods vehicle";
    default: return "Not available";
  }
}

function methodIcon(method?: DeliveryMethod | null) {
  if (method === "walking") return <Footprints size={18} />;
  if (method === "bicycle") return <Bike size={18} />;
  if (method === "bike" || method === "motorbike" || method === "scooter") return <Navigation size={18} />;
  if (method === "auto") return <CarFront size={18} />;
  if (method === "goods_vehicle") return <Truck size={18} />;
  return <ShieldCheck size={18} />;
}

function message(error: unknown, fallback: string) { return userFacingError(error, fallback); }

function roleAccountCopy(roleName: string) {
  if (roleName === "Merchant") return {
    introduction: "Manage your store identity, contact details and account access.",
    privacy: "Your number is used only when an active order requires store contact.",
    editorPrivacy: "Used only when an active order requires store contact. It is not used to sign in.",
  };
  if (roleName === "Delivery Partner") return {
    introduction: "Manage the identity, work details and permissions used while you deliver.",
    privacy: "Your number is shared only during an assigned delivery when contact is required.",
    editorPrivacy: "Shared only during an assigned delivery when contact is required. It is not used to sign in.",
  };
  return {
    introduction: "Manage your identity, permissions and account access.",
    privacy: "Your number is used only when an active task requires contact.",
    editorPrivacy: "Used only when an active task requires contact. It is not used to sign in.",
  };
}
