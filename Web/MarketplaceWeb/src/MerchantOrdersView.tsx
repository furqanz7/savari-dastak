import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { BellRing, Check, ChevronDown, ClipboardList, Store, UserRound, WalletCards } from "lucide-react";
import { CustomerNotice, CustomerSkeleton } from "./CustomerUI";
import "./design/customer-experience.css";
import "./design/merchant-experience.css";
import { MerchantV1CommerceControl } from "./MerchantV1CommerceControl";
import { MerchantV1Opportunities } from "./MerchantV1Opportunities";
import { RoleAccountView } from "./RoleAccountView";
import { RoyaltyPanel } from "./RoyaltyPanel";
import { useDastakWebPush, type DastakWebPushController } from "./useDastakWebPush";
import {
  classifyMerchantBranch,
  discoverDefaultMerchantBranches,
  mergeMerchantBranches,
  persistMerchantBranch,
  readPersistedMerchantBranch,
  type MerchantBranch,
} from "./merchantBranchContext";
import { getV1MerchantOpportunities } from "./dastakV1";

type Props = {
  accessToken: string;
  accountId: string;
  client: SupabaseClient;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  webPushPublicKey: string;
  onSignOut: () => void;
};

type MerchantSection = "orders" | "catalogue" | "royalty" | "account";

export function MerchantOrdersView({
  accessToken,
  accountId,
  client,
  displayName,
  email,
  phoneNumber,
  supabaseUrl,
  publishableKey,
  webPushPublicKey,
  onSignOut,
}: Props) {
  const auth = useMemo(
    () => ({ accessToken, supabaseUrl, publishableKey }),
    [accessToken, publishableKey, supabaseUrl],
  );
  const [section, setSection] = useState<MerchantSection>("orders");
  const [branches, setBranches] = useState<MerchantBranch[]>([]);
  const [selectedBranchId, setSelectedBranchId] = useState<string>();
  const [branchLoading, setBranchLoading] = useState(true);
  const [branchIssue, setBranchIssue] = useState<string>();
  const branchProbes = useRef(new Set<string>());
  const webPushAuthentication = useMemo(() => ({
    accountId,
    accessToken,
    supabaseUrl,
    publishableKey,
    publicKey: webPushPublicKey,
  }), [accessToken, accountId, publishableKey, supabaseUrl, webPushPublicKey]);
  const webPush = useDastakWebPush(webPushAuthentication);
  const selectedBranch = branches.find((branch) => branch.id === selectedBranchId);
  const contentRef = useRef<HTMLElement>(null);
  const openSection = (next: MerchantSection) => {
    setSection(next);
    contentRef.current?.focus({ preventScroll: true });
    window.scrollTo({ top: 0, behavior: "instant" });
  };

  const acceptBranches = useCallback((incoming: MerchantBranch[]) => {
    setBranches((current) => mergeMerchantBranches(current, incoming));
  }, []);

  useEffect(() => {
    setBranches([]);
    setSelectedBranchId(undefined);
    setBranchIssue(undefined);
    branchProbes.current.clear();
  }, [accountId]);

  // Customer restaurant discovery requires a fresh merchant reachability
  // heartbeat. The orders surface already refreshes this through its feed, but
  // merchants commonly stay on Store while editing their menu or banner. Keep
  // the branch reachable while this authenticated merchant workspace is open.
  useEffect(() => {
    let active = true;
    const heartbeat = () => {
      void getV1MerchantOpportunities({ ...auth, limit: 1 }).catch(() => {
        // Heartbeats are advisory; the existing workspace remains usable when
        // the order service is temporarily unavailable.
      });
    };
    heartbeat();
    const timer = window.setInterval(() => {
      if (active && document.visibilityState === "visible") heartbeat();
    }, 60_000);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, [auth]);

  useEffect(() => {
    if (selectedBranchId && branches.some((branch) => branch.id === selectedBranchId)) return;
    const persisted = readPersistedMerchantBranch(accountId);
    const next = persisted && branches.some((branch) => branch.id === persisted) ? persisted : branches[0]?.id;
    setSelectedBranchId(next);
    if (next) persistMerchantBranch(accountId, next);
  }, [accountId, branches, selectedBranchId]);

  useEffect(() => {
    let active = true;
    setBranchLoading(true);
    void discoverDefaultMerchantBranches(auth).then((result) => {
      if (!active) return;
      acceptBranches(result.branches);
      if (result.failures.includes("session")) {
        onSignOut();
        return;
      }
      const operationalFailure = result.failures.find((failure) => failure !== "not_applicable");
      setBranchIssue(operationalFailure === "access"
        ? "Dastak could not verify all branch permissions. Only verified branches are shown."
        : operationalFailure === "connectivity"
          ? "Some branches could not be checked while Dastak reconnects."
          : operationalFailure === "service" ? "Some branch details are temporarily unavailable."
            : result.branches.length === 0 ? "No Store branch is currently available to this merchant account." : undefined);
    }).finally(() => { if (active) setBranchLoading(false); });
    return () => { active = false; };
  }, [acceptBranches, auth, onSignOut]);

  const discoverOperationalBranches = useCallback((candidates: Array<{ id: string; displayName: string }>) => {
    candidates.forEach((candidate) => {
      if (branchProbes.current.has(candidate.id)) return;
      branchProbes.current.add(candidate.id);
      void classifyMerchantBranch(auth, candidate).then((branch) => {
        acceptBranches([branch]);
        setBranchIssue(undefined);
      }).catch((error: unknown) => {
        branchProbes.current.delete(candidate.id);
        if (error && typeof error === "object" && "status" in error && error.status === 401) onSignOut();
        else setBranchIssue("A branch visible in Operations could not be verified for Store management.");
      });
    });
  }, [acceptBranches, auth, onSignOut]);

  const selectBranch = (branchId: string) => {
    setSelectedBranchId(branchId);
    persistMerchantBranch(accountId, branchId);
  };

  return (
    <div className="merchant-workspace merchant-experience">
      <a className="customer-skip-link" href="#merchant-content">Skip to content</a>
      <aside className="merchant-sidebar">
        <button className="merchant-brand" type="button" onClick={() => openSection("orders")} aria-label="Dastak Merchant · Open Orders">Dastak<span>.</span><small>MERCHANT</small></button>
        <nav className="merchant-navigation" aria-label="Merchant navigation">
          <MerchantTab selected={section === "orders"} onSelect={() => openSection("orders")} icon={<ClipboardList size={21} />} label="Orders" />
          <MerchantTab selected={section === "catalogue"} onSelect={() => openSection("catalogue")} icon={<Store size={21} />} label="Store" />
          <MerchantTab selected={section === "royalty"} onSelect={() => openSection("royalty")} icon={<WalletCards size={21} />} label="Earnings" />
          <MerchantTab selected={section === "account"} onSelect={() => openSection("account")} icon={<UserRound size={21} />} label="Account" />
        </nav>
        <p className="merchant-sidebar-note">Every detail.<br />Every doorstep.</p>
      </aside>
      <section className="merchant-main" id="merchant-content" ref={contentRef} tabIndex={-1} aria-label={section === "catalogue" ? "Store" : section === "royalty" ? "Earnings" : section === "account" ? "Account" : "Orders"}>
      <MerchantBranchSelector branches={branches} selected={selectedBranch} loading={branchLoading} issue={branchIssue} onSelect={selectBranch} />

      {section === "catalogue" ? (
        selectedBranch ? <MerchantV1CommerceControl key={selectedBranch.id} auth={auth} branch={selectedBranch} onSessionExpired={onSignOut} />
          : branchIssue ? <CustomerNotice title="Store unavailable">{branchIssue}</CustomerNotice> : <CustomerSkeleton label="Loading your branches" kind="orders" />
      ) : section === "royalty" ? (
        <RoyaltyPanel auth={auth} kind="MERCHANT" />
      ) : section === "account" ? (
        <RoleAccountView
          accessToken={accessToken}
          displayName={displayName}
          email={email}
          phoneNumber={phoneNumber}
          roleName="Merchant"
          persona="MERCHANT"
          supabaseUrl={supabaseUrl}
          publishableKey={publishableKey}
          onOpenWorkspace={() => openSection("catalogue")}
          notificationSurface={<MerchantNotificationStatus controller={webPush} />}
          onSignOut={onSignOut}
        />
      ) : (
        <div className="merchant-orders-shell">
          <header className="merchant-orders-heading">
            <div>
              <p className="eyebrow">YOUR ORDER DESK</p>
              <h1>Ready for what’s next.</h1>
              <p>From the first request to the final handoff.</p>
            </div>
            <MerchantNotificationStatus controller={webPush} />
          </header>
          <MerchantV1Opportunities
            auth={auth}
            client={client}
            accountId={accountId}
            onSessionExpired={onSignOut}
            activeBranchId={selectedBranch?.id}
            onBranchesDiscovered={discoverOperationalBranches}
          />
        </div>
      )}
      </section>
    </div>
  );
}

export function MerchantBranchSelector({ branches, selected, loading, issue, onSelect }: {
  branches: MerchantBranch[];
  selected?: MerchantBranch;
  loading: boolean;
  issue?: string;
  onSelect: (branchId: string) => void;
}) {
  return <section className="merchant-branch-context" aria-label="Active merchant branch">
    <Store size={18} />
    <span><small>Active branch</small><strong>{selected?.branchName ?? (loading ? "Loading branches…" : "No verified branch")}</strong>{selected ? <em>{selected.organizationName}</em> : null}</span>
    {branches.length > 1 ? <label><span className="sr-only">Choose active branch</span><select value={selected?.id ?? ""} onChange={(event) => onSelect(event.target.value)}>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.branchName} · {branch.organizationName}</option>)}</select><ChevronDown size={16} aria-hidden="true" /></label> : null}
    {issue ? <p role="status">{issue}</p> : null}
  </section>;
}

export function MerchantNotificationStatus({ controller }: { controller: DastakWebPushController }) {
  if (controller.status === "checking") {
    return <p className="merchant-notification-status" role="status"><BellRing size={17} /> Checking order alerts…</p>;
  }
  if (controller.status === "enabled") {
    return <p className="merchant-notification-status enabled"><Check size={17} /> New-order alerts on</p>;
  }
  const blocked = controller.status === "blocked";
  const unsupported = controller.status === "unsupported";
  return <aside className="merchant-notification-status attention" aria-label="New-order notifications">
    <BellRing size={18} />
    <span><strong>{blocked ? "Order alerts are blocked" : unsupported ? "Browser alerts unavailable" : "Don’t miss a new request"}</strong><small>{controller.message ?? (blocked ? "Allow notifications in browser settings, then retry." : unsupported ? "Keep this order desk open for live in-app updates." : "Enable browser alerts for incoming retail and restaurant requests.")}</small></span>
    {!unsupported ? <button type="button" disabled={controller.status === "enabling"} onClick={() => void controller.enable()}>{controller.status === "enabling" ? "Enabling…" : blocked ? "Retry" : "Enable alerts"}</button> : null}
  </aside>;
}

function MerchantTab({
  selected,
  onSelect,
  icon,
  label,
}: {
  selected: boolean;
  onSelect: () => void;
  icon: ReactNode;
  label: string;
}) {
  return (
    <button
      type="button"
      aria-current={selected ? "page" : undefined}
      aria-controls="merchant-content"
      className={selected ? "selected" : ""}
      onClick={onSelect}
    >
      {icon}
      <span>{label}</span>
    </button>
  );
}
