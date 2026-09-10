import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { BellRing, BookOpen, Check, ChevronDown, ClipboardList, Store, UserRound, WalletCards } from "lucide-react";
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

  const acceptBranches = useCallback((incoming: MerchantBranch[]) => {
    setBranches((current) => mergeMerchantBranches(current, incoming));
  }, []);

  useEffect(() => {
    setBranches([]);
    setSelectedBranchId(undefined);
    setBranchIssue(undefined);
    branchProbes.current.clear();
  }, [accountId]);

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
    <div className="merchant-workspace">
      <nav className="workspace-tabs merchant-tabs" aria-label="Merchant workspace" role="tablist">
        <MerchantTab selected={section === "orders"} onSelect={() => setSection("orders")} icon={<ClipboardList size={18} />} label="Orders" />
        <MerchantTab selected={section === "catalogue"} onSelect={() => setSection("catalogue")} icon={<BookOpen size={18} />} label="Catalogue" />
        <MerchantTab selected={section === "royalty"} onSelect={() => setSection("royalty")} icon={<WalletCards size={18} />} label="Royalty" />
        <MerchantTab selected={section === "account"} onSelect={() => setSection("account")} icon={<UserRound size={18} />} label="Account" />
      </nav>

      <MerchantBranchSelector branches={branches} selected={selectedBranch} loading={branchLoading} issue={branchIssue} onSelect={selectBranch} />

      {section === "catalogue" ? (
        selectedBranch ? <MerchantV1CommerceControl key={selectedBranch.id} auth={auth} branch={selectedBranch} onSessionExpired={onSignOut} />
          : <div className="catalogue-loading" role={branchIssue ? "alert" : "status"}><span /> {branchIssue ?? "Loading your branches"}</div>
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
          onOpenWorkspace={() => setSection("catalogue")}
          onSignOut={onSignOut}
        />
      ) : (
        <div className="merchant-orders-shell">
          <header className="merchant-orders-heading">
            <div>
              <p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak merchant"}</p>
              <h1>Orders</h1>
              <p>Live exact-item requests and fulfilments.</p>
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
      role="tab"
      aria-selected={selected}
      className={selected ? "selected" : ""}
      onClick={onSelect}
    >
      {icon}
      <span>{label}</span>
    </button>
  );
}
