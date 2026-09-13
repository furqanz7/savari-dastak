import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  BadgeCheck,
  Building2,
  Check,
  CircleAlert,
  Activity,
  Database,
  ExternalLink,
  FileText,
  LayoutDashboard,
  Navigation,
  PackageSearch,
  RotateCcw,
  ScrollText,
  ShieldCheck,
  Store,
  UsersRound,
  WalletCards,
  WifiOff,
  X,
} from "lucide-react";
import { RoleAccountView } from "./RoleAccountView";
import { AdminAccessPanel } from "./AdminAccessPanel";
import { AdminPrivilegedActionDialog } from "./AdminPrivilegedActionDialog";
import { AdminCataloguePanel } from "./AdminCataloguePanel";
import { runAdminPrivilegedMutation } from "./adminPrivilegedMutation";
import {
  getAdminOrderPage,
  getEvidenceUrl,
  getMerchantApplications,
  getOwnerOperations,
  getOwnerExceptionPage,
  getPartnerApplications,
  reconcileOwnerOrders,
  resetOwnerHandoff,
  resolveOwnerSupportCase,
  reviewOrderRefund,
  reviewMerchantApplication,
  reviewPartnerApplication,
  type AdminOrder,
  type AdminOrderPage,
  type MerchantAdminApplication,
  type OwnerOperationsSnapshot,
  type OwnerExceptionPage,
  type OwnerOrderException,
  type PartnerAdminApplication,
  type ReviewDecision,
} from "./admin";
import { formatPrice } from "./catalogue";
import { orderStatusLabel } from "./orders";
import { processOrderRefund } from "./payments";
import { AdminV1ExecutionPanel } from "./AdminV1ExecutionPanel";
import { AdminSystemHealthPanel } from "./AdminSystemHealthPanel";
import { AdminOperationalSafetyPanel } from "./AdminOperationalSafetyPanel";
import { AdminRoyaltyPayoutPanel } from "./AdminRoyaltyPayoutPanel";
import { AdminOverviewPanel } from "./AdminOverviewPanel";
import { AdminWorkspaceNavigation } from "./AdminWorkspaceNavigation";
import { AdminNetworkPanel } from "./AdminNetworkPanel";
import { AdminAuditHistoryPanel } from "./AdminAuditHistoryPanel";
import { AdminMerchantGovernancePanel } from "./AdminMerchantGovernancePanel";
import { AdminDeliveryPartnerGovernancePanel } from "./AdminDeliveryPartnerGovernancePanel";
import { AdminCustomerRecoveryPanel } from "./AdminCustomerRecoveryPanel";
import {
  getV1AdminAccess,
  getV1AdminCommandCenter,
  type V1AdminAccess,
  type V1AdminCommandCenter,
} from "./dastakV1";
import { useAdminPullToRefresh, useAdminWorkspaceRefresh } from "./adminRefresh";
import { refreshVisibleAdminWorkspaces } from "./adminRefresh";
import { AdminRuntimeProvider } from "./AdminRuntimeContext";
import {
  adminFallbackCadence,
  adminFeedFailed,
  adminFeedHasContent,
  adminFeedStarted,
  adminFeedStale,
  adminFeedSucceeded,
  initialAdminFeedState,
  isAdminSessionExpired,
  shouldRunAdminFallback,
  useAdminRealtime,
  type AdminChangeSignal,
  type AdminFeedState,
} from "./adminRuntime";
import { RefreshQueue } from "./orderRealtime";
import { userFacingError } from "./userFacingError";
import "./design/admin-workspace.css";

type Props = {
  accessToken: string;
  client: SupabaseClient;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  onSignOut: () => void;
};

type AdminTab =
  | "overview" | "approvals" | "exceptions" | "orders" | "network" | "audit"
  | "catalogue" | "merchants" | "safety" | "finance" | "health" | "access"
  | "riders" | "customers" | "legacy" | "account";

type AdminBootstrapFeed =
  | "merchantApprovals"
  | "deliveryApprovals"
  | "legacyHistory"
  | "operations"
  | "adminAccess"
  | "commandCenter";

const adminFeedLabels: Record<AdminBootstrapFeed, string> = {
  merchantApprovals: "Merchant approvals",
  deliveryApprovals: "Delivery approvals",
  legacyHistory: "Legacy history",
  operations: "Exception desk",
  adminAccess: "Admin access",
  commandCenter: "Command center",
};

const adminBootstrapFeeds: AdminBootstrapFeed[] = [
  "merchantApprovals",
  "deliveryApprovals",
  "legacyHistory",
  "operations",
  "adminAccess",
  "commandCenter",
];

function initialBootstrapFeedStates() {
  return Object.fromEntries(adminBootstrapFeeds.map((feed) => [feed, initialAdminFeedState()])) as Record<AdminBootstrapFeed, AdminFeedState>;
}

function createBootstrapQueues() {
  return Object.fromEntries(adminBootstrapFeeds.map((feed) => [feed, new RefreshQueue()])) as Record<AdminBootstrapFeed, RefreshQueue>;
}

export function AdminDashboard({ accessToken, client, displayName, email, phoneNumber, supabaseUrl, publishableKey, onSignOut }: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [merchants, setMerchants] = useState<MerchantAdminApplication[]>([]);
  const [partners, setPartners] = useState<PartnerAdminApplication[]>([]);
  const [orders, setOrders] = useState<AdminOrder[]>([]);
  const [legacyQuery, setLegacyQuery] = useState("");
  const [legacyQueryInput, setLegacyQueryInput] = useState("");
  const [legacyHasMore, setLegacyHasMore] = useState(false);
  const legacyCursor = useRef<AdminOrderPage["nextCursor"]>(undefined);
  const [operations, setOperations] = useState<OwnerOperationsSnapshot>();
  const [exceptionsHaveMore, setExceptionsHaveMore] = useState(false);
  const exceptionCursor = useRef<OwnerExceptionPage["nextCursor"]>(undefined);
  const [adminAccess, setAdminAccess] = useState<V1AdminAccess>();
  const [commandCenter, setCommandCenter] = useState<V1AdminCommandCenter>();
  const [tab, setTab] = useState<AdminTab>("overview");
  const previousTab = useRef(tab);
  useEffect(() => {
    if (previousTab.current === tab) return;
    previousTab.current = tab;
    const frame = window.requestAnimationFrame(() => {
      window.scrollTo({ top: 0, behavior: "instant" });
      document.getElementById("admin-workspace-title")?.focus({ preventScroll: true });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [tab]);
  const [busy, setBusy] = useState<string>();
  const [actionError, setActionError] = useState<string>();
  const [feedStates, setFeedStates] = useState(initialBootstrapFeedStates);
  const [notice, setNotice] = useState<string>();
  const queues = useRef(createBootstrapQueues());
  const controllers = useRef(new Map<AdminBootstrapFeed, AbortController>());
  const sessionRecoveryStarted = useRef(false);
  const recoverExpiredSession = useCallback(() => {
    if (sessionRecoveryStarted.current) return;
    sessionRecoveryStarted.current = true;
    onSignOut();
  }, [onSignOut]);
  const reportRequestError = useCallback((error: unknown) => {
    if (!isAdminSessionExpired(error)) return false;
    recoverExpiredSession();
    return true;
  }, [recoverExpiredSession]);
  useEffect(() => { sessionRecoveryStarted.current = false; }, [accessToken]);

  const refreshFeed = useCallback(async (feed: AdminBootstrapFeed) => {
    await queues.current[feed].request(false, async () => {
      const controller = new AbortController();
      controllers.current.set(feed, controller);
      setFeedStates((current) => ({ ...current, [feed]: adminFeedStarted(current[feed]) }));
      try {
        if (feed === "merchantApprovals") {
          const value = await getMerchantApplications({ ...auth, signal: controller.signal });
          setMerchants(value.filter((application) => application.status === "pending"));
        } else if (feed === "deliveryApprovals") {
          const value = await getPartnerApplications({ ...auth, signal: controller.signal });
          setPartners(value.filter((application) => application.status === "pending"));
        } else if (feed === "legacyHistory") {
          const page = await getAdminOrderPage({ ...auth, query: legacyQuery, limit: 50, signal: controller.signal });
          setOrders(page.orders);
          setLegacyHasMore(page.hasMore);
          legacyCursor.current = page.nextCursor;
        } else if (feed === "operations") {
          const [summary, page] = await Promise.all([
            getOwnerOperations({ ...auth, limit: 1, signal: controller.signal }),
            getOwnerExceptionPage({ ...auth, limit: 50, signal: controller.signal }),
          ]);
          setOperations({ ...summary, exceptions: page.exceptions });
          setExceptionsHaveMore(page.hasMore);
          exceptionCursor.current = page.nextCursor;
        } else if (feed === "adminAccess") {
          setAdminAccess(await getV1AdminAccess({ ...auth, signal: controller.signal }));
        } else {
          setCommandCenter(await getV1AdminCommandCenter({ ...auth, signal: controller.signal }));
        }
        setFeedStates((current) => ({ ...current, [feed]: adminFeedSucceeded(current[feed]) }));
      } catch (error) {
        if (controller.signal.aborted) return;
        reportRequestError(error);
        setFeedStates((current) => ({ ...current, [feed]: adminFeedFailed(current[feed], error) }));
        throw error;
      } finally {
        if (controllers.current.get(feed) === controller) controllers.current.delete(feed);
      }
    });
  }, [auth, legacyQuery, reportRequestError]);

  const loadMoreLegacy = useCallback(async () => {
    await queues.current.legacyHistory.request(false, async () => {
      const cursor = legacyCursor.current;
      if (!cursor || !legacyHasMore) return;
      try {
        const page = await getAdminOrderPage({ ...auth, query: legacyQuery, limit: 50, cursor });
        setOrders((current) => mergeById(current, page.orders, (order) => order.orderId));
        setLegacyHasMore(page.hasMore);
        legacyCursor.current = page.nextCursor;
      } catch (error) {
        reportRequestError(error);
        setFeedStates((current) => ({ ...current, legacyHistory: adminFeedFailed(current.legacyHistory, error) }));
      }
    });
  }, [auth, legacyHasMore, legacyQuery, reportRequestError]);
  const loadMoreExceptions = useCallback(async () => {
    await queues.current.operations.request(false, async () => {
      const cursor = exceptionCursor.current;
      if (!cursor || !exceptionsHaveMore) return;
      try {
        const page = await getOwnerExceptionPage({ ...auth, limit: 50, cursor });
        setOperations((current) => current ? {
          ...current, exceptions: mergeById(current.exceptions, page.exceptions, (exception) => exception.exceptionId),
        } : current);
        setExceptionsHaveMore(page.hasMore);
        exceptionCursor.current = page.nextCursor;
      } catch (error) {
        reportRequestError(error);
        setFeedStates((current) => ({ ...current, operations: adminFeedFailed(current.operations, error) }));
      }
    });
  }, [auth, exceptionsHaveMore, reportRequestError]);

  const refreshAllBootstrap = useCallback(async () => {
    await Promise.allSettled(adminBootstrapFeeds.map((feed) => refreshFeed(feed)));
  }, [refreshFeed]);
  const refreshMerchantApprovals = useCallback(() => refreshFeed("merchantApprovals"), [refreshFeed]);
  const refreshDeliveryApprovals = useCallback(() => refreshFeed("deliveryApprovals"), [refreshFeed]);
  const refreshLegacyHistory = useCallback(() => refreshFeed("legacyHistory"), [refreshFeed]);
  const refreshOperations = useCallback(() => refreshFeed("operations"), [refreshFeed]);
  const refreshAdminAccess = useCallback(() => refreshFeed("adminAccess"), [refreshFeed]);
  const refreshCommandCenter = useCallback(() => refreshFeed("commandCenter"), [refreshFeed]);
  useAdminWorkspaceRefresh("merchantApprovals", refreshMerchantApprovals);
  useAdminWorkspaceRefresh("deliveryApprovals", refreshDeliveryApprovals);
  useAdminWorkspaceRefresh("legacyHistory", refreshLegacyHistory);
  useAdminWorkspaceRefresh("operations", refreshOperations);
  useAdminWorkspaceRefresh("adminAccess", refreshAdminAccess);
  useAdminWorkspaceRefresh("commandCenter", refreshCommandCenter);
  const pull = useAdminPullToRefresh();

  const handleRealtimeChange = useCallback((signal?: AdminChangeSignal) => {
    void refreshVisibleAdminWorkspaces(signal?.workspaces);
  }, []);
  const realtimeHealth = useAdminRealtime({
    client,
    accessToken,
    onChange: handleRealtimeChange,
    onSessionExpired: recoverExpiredSession,
  });

  useEffect(() => { void refreshAllBootstrap(); }, [refreshAllBootstrap]);
  useEffect(() => () => {
    controllers.current.forEach((controller) => controller.abort());
    controllers.current.clear();
  }, []);
  useEffect(() => {
    if (realtimeHealth !== "subscribed" || (typeof navigator !== "undefined" && !navigator.onLine)) {
      setFeedStates((current) => Object.fromEntries(adminBootstrapFeeds.map((feed) =>
        [feed, adminFeedStale(current[feed])])) as Record<AdminBootstrapFeed, AdminFeedState>);
    }
    const interval = window.setInterval(() => {
      if (!shouldRunAdminFallback(document.visibilityState, navigator.onLine)) return;
      void refreshVisibleAdminWorkspaces();
    }, adminFallbackCadence(realtimeHealth));
    return () => window.clearInterval(interval);
  }, [realtimeHealth]);

  const performMutation = async (input: {
    identity: string;
    mutate: (idempotencyKey: string) => Promise<unknown>;
    reconcile: () => Promise<unknown>;
    success: string;
  }) => {
    const identity = input.identity;
    setBusy(identity);
    setActionError(undefined);
    setNotice(undefined);
    const result = await runAdminPrivilegedMutation({
      operationIdentity: identity, mutate: input.mutate, reconcile: input.reconcile,
    });
    setBusy(undefined);
    if (result.kind === "completed") {
      setNotice(input.success);
      return;
    }
    if (result.kind === "reconciled") {
      setNotice(result.message);
      return;
    }
    if (result.kind === "uncertain_reconciled") {
      setNotice(result.message);
      return;
    }
    if (result.kind === "uncertain_blocked") {
      setActionError(result.message);
      throw result;
    }
    reportRequestError(result.error);
    setActionError(message(result.error));
    throw result.error;
  };

  const review = async (kind: "merchant" | "partner", applicationId: string, decision: ReviewDecision, reason?: string) => {
    const reconcile = () => refreshFeed(kind === "merchant" ? "merchantApprovals" : "deliveryApprovals");
    await performMutation({
      identity: `${kind}-application:${applicationId}:${decision}:${reason ?? ""}`,
      mutate: (idempotencyKey) => {
        const input = { ...auth, applicationId, decision, reason, idempotencyKey };
        return kind === "merchant" ? reviewMerchantApplication(input) : reviewPartnerApplication(input);
      },
      reconcile,
      success: `${kind === "merchant" ? "Merchant" : "Delivery Partner"} application ${decision === "approve" ? "approved" : "rejected"}.`,
    });
  };

  const openEvidence = async (objectPath: string) => {
    setBusy(`evidence:${objectPath}`);
    setActionError(undefined);
    try {
      const signedUrl = await getEvidenceUrl({ ...auth, objectPath });
      window.location.assign(signedUrl);
    } catch (evidenceError) {
      reportRequestError(evidenceError);
      setActionError(message(evidenceError));
    } finally {
      setBusy(undefined);
    }
  };

  const reviewRefund = async (
    order: AdminOrder,
    outcome: "approve_full" | "approve_items_only" | "deny",
    faultSource: "merchant" | "dastak" | null,
    reason: string,
  ) => {
    let updated: Awaited<ReturnType<typeof reviewOrderRefund>> | undefined;
    const reloadOrders = () => refreshFeed("legacyHistory");
    await performMutation({
      identity: `refund-decision:${order.orderId}:${order.updatedAt}:${outcome}:${faultSource ?? "none"}:${reason}`,
      mutate: async (idempotencyKey) => {
        updated = await reviewOrderRefund({ ...auth, orderId: order.orderId, outcome, faultSource, reason, idempotencyKey });
        return updated;
      },
      reconcile: reloadOrders,
      success: outcome === "deny" ? "Refund request denied and recorded." : "Refund decision recorded.",
    });
    if (outcome !== "deny" && updated?.paymentState === "refund_pending" && updated.status !== "returning_to_merchant") {
      await performMutation({
        identity: `provider-refund:${order.orderId}`,
        mutate: (idempotencyKey) => processOrderRefund({ ...auth, orderId: order.orderId, idempotencyKey }),
        reconcile: reloadOrders,
        success: "Provider refund submitted and authoritative payment state reloaded.",
      });
    }
  };

  const retryRefund = async (order: AdminOrder) => {
    await performMutation({
      identity: `provider-refund:${order.orderId}`,
      mutate: (idempotencyKey) => processOrderRefund({ ...auth, orderId: order.orderId, idempotencyKey }),
      reconcile: () => refreshFeed("legacyHistory"),
      success: "Provider refund submitted and authoritative payment state reloaded.",
    });
  };

  const resolveSupport = async (exception: OwnerOrderException, resolution: string) => {
    await performMutation({
      identity: `support:${exception.entityId}:${exception.status}:${resolution}`,
      mutate: (idempotencyKey) => resolveOwnerSupportCase({ ...auth, caseId: exception.entityId, resolution, idempotencyKey }),
      reconcile: () => refreshFeed("operations"),
      success: "Support case resolved and recorded.",
    });
  };

  const resetHandoff = async (exception: OwnerOrderException, reason: string) => {
    if (!exception.purpose) return;
    await performMutation({
      identity: `handoff:${exception.entityKind}:${exception.entityId}:${exception.purpose}:${exception.status}:${reason}`,
      mutate: (idempotencyKey) => resetOwnerHandoff({ ...auth, entityKind: exception.entityKind,
        entityId: exception.entityId, purpose: exception.purpose!, reason, idempotencyKey }),
      reconcile: () => refreshFeed("operations"),
      success: "Handoff code unlocked and securely regenerated.",
    });
  };

  const reconcile = async () => {
    await performMutation({
      identity: "owner-lifecycle-recovery",
      mutate: async (idempotencyKey) => {
        const result = await reconcileOwnerOrders({ ...auth, idempotencyKey });
        const recovered = result.merchantOrdersRecovered + result.parcelsRecovered;
        const offers = result.merchantOffersCreated + result.parcelOffersCreated;
        setNotice(`Recovery complete: ${recovered} records repaired, ${offers} offers created.`);
        return result;
      },
      reconcile: () => refreshFeed("operations"),
      success: "Lifecycle recovery completed and the exception desk was reloaded.",
    });
  };

  const mainNavigation: Array<{ id: AdminTab; label: string; icon: ReactNode; badge?: number }> = [
    { id: "overview", label: "Overview", icon: <LayoutDashboard size={18} /> },
    { id: "approvals", label: "Approvals", icon: <ShieldCheck size={18} />, badge: merchants.length + partners.length },
    { id: "orders", label: "Live orders", icon: <PackageSearch size={18} /> },
    { id: "network", label: "Network", icon: <UsersRound size={18} /> },
    { id: "catalogue", label: "Catalogue", icon: <Database size={18} /> },
    { id: "exceptions", label: "Exceptions", icon: <CircleAlert size={18} />, badge: operations?.summary.totalExceptions },
  ];
  const controlNavigation: Array<{ id: AdminTab; label: string; icon: ReactNode }> = [
    { id: "audit", label: "Audit History", icon: <ScrollText size={18} /> },
    { id: "merchants", label: "Merchant governance", icon: <Building2 size={18} /> },
    { id: "riders", label: "Rider governance", icon: <Navigation size={18} /> },
    { id: "customers", label: "Customer recovery", icon: <UsersRound size={18} /> },
    { id: "safety", label: "Safety controls", icon: <CircleAlert size={18} /> },
    { id: "finance", label: "Finance & payouts", icon: <WalletCards size={18} /> },
    { id: "health", label: "System health", icon: <Activity size={18} /> },
    { id: "legacy", label: "Legacy history", icon: <FileText size={18} /> },
    { id: "access", label: "Admin access", icon: <ShieldCheck size={18} /> },
    { id: "account", label: "My account", icon: <BadgeCheck size={18} /> },
  ];
  const navigation = [...mainNavigation, ...controlNavigation];
  const navigationGroups = [
    { label: "Daily operations", items: ["overview", "orders", "approvals", "exceptions", "safety"].flatMap((id) => navigation.filter((item) => item.id === id)) },
    { label: "Marketplace", items: ["merchants", "riders", "customers", "network", "catalogue"].flatMap((id) => navigation.filter((item) => item.id === id)) },
    { label: "Oversight", items: ["audit", "finance", "legacy", "health", "access", "account"].flatMap((id) => navigation.filter((item) => item.id === id)) },
  ];

  return <AdminRuntimeProvider realtimeHealth={realtimeHealth} onSessionExpired={recoverExpiredSession}>
    <div className="admin-console" style={{ "--admin-pull-distance": `${pull.distance}px`, "--admin-pull-progress": pull.progress } as CSSProperties}>
    <a className="admin-skip-link" href="#admin-workspace-title">Skip to workspace</a>
    <div className={`admin-pull-indicator ${pull.refreshing ? "refreshing" : ""}`} aria-live="polite" aria-hidden={!pull.refreshing && pull.distance === 0}>
      <span><span className="admin-pull-glyph">↓</span>{pull.refreshing ? "Refreshing current workspace" : pull.progress >= 1 ? "Release to refresh" : "Pull to refresh"}</span>
    </div>
    <AdminWorkspaceNavigation groups={navigationGroups} selected={tab} onSelect={setTab} displayName={displayName ?? "Dastak Admin"} role={adminRoleLabel(adminAccess?.role)} />

    <main className="admin-shell">
      <header className="admin-heading"><div><p className="eyebrow">{navigationGroups.find((group) => group.items.some((item) => item.id === tab))?.label}</p><h1 id="admin-workspace-title" tabIndex={-1}>{tabTitle(tab)}</h1><p>{tabDescription(tab)}</p></div><span className={`admin-update-status ${realtimeHealth}`} role="status"><i aria-hidden="true" />{realtimeHealth === "subscribed" ? "Live updates" : realtimeHealth === "connecting" ? "Connecting" : "Reconnecting"}</span></header>
      <AdminFeedStatus states={feedStates} realtimeHealth={realtimeHealth} />
      {actionError ? <p className="order-error" role="alert">{actionError}</p> : null}
      {notice ? <div className="admin-notice" role="status"><Check size={18} /><span>{notice}</span><button type="button" onClick={() => setNotice(undefined)} aria-label="Dismiss confirmation"><X size={16} /></button></div> : null}

      {tab === "overview" ? <AdminOverviewPanel snapshot={commandCenter} loading={feedStates.commandCenter.phase === "loading"} onNavigate={setTab} />
        : tab === "network" ? <AdminNetworkPanel auth={auth} />
        : tab === "audit" ? <AdminAuditHistoryPanel auth={auth} />
        : tab === "merchants" ? <AdminMerchantGovernancePanel auth={auth} />
        : tab === "riders" ? <AdminDeliveryPartnerGovernancePanel auth={auth} />
        : tab === "customers" ? <AdminCustomerRecoveryPanel auth={auth} />
        : tab === "catalogue" ? <AdminCataloguePanel auth={auth} />
        : tab === "orders" ? <AdminV1ExecutionPanel auth={auth} />
        : tab === "finance" ? <AdminRoyaltyPayoutPanel auth={auth} />
        : tab === "safety" ? <AdminOperationalSafetyPanel auth={auth} />
        : tab === "health" ? <AdminSystemHealthPanel auth={auth} />
        : tab === "access" ? adminAccess?.canManageAdmins
          ? <AdminAccessPanel auth={auth} access={adminAccess} onChange={(value) => {
            setAdminAccess(value);
            setFeedStates((current) => ({ ...current, adminAccess: adminFeedSucceeded(current.adminAccess) }));
          }} />
          : <section className="admin-section" role="tabpanel"><h2>Admin access</h2><p className="admin-empty">{adminAccess ? "Only the permanent Superadmin can assign Executive Admin seats." : "Admin access settings are not available yet. Use the workspace retry above."}</p></section>
        : tab === "account" ? <RoleAccountView accessToken={accessToken} displayName={displayName} email={email} phoneNumber={phoneNumber} roleName={adminRoleLabel(adminAccess?.role)} accessLabel="Full operations access" supabaseUrl={supabaseUrl} publishableKey={publishableKey} allowsAccountDeletion={false} onSignOut={onSignOut} />
        : tab === "approvals" ? <div className="admin-approvals" role="tabpanel">
          <ApprovalSection title="Merchant applications" count={merchants.length} empty={approvalEmptyMessage(feedStates.merchantApprovals, "merchant")}>{merchants.map((application) => <ReviewCard key={application.applicationId} icon={<Store size={20} />} title={application.businessName} subtitle={application.businessAddress} facts={[
            application.merchantType === "RESTAURANT_CAFE" ? "Restaurant / Cafe" : "Retail store",
            `Legal name · ${application.legalName}`,
            `Applicant · ${application.applicantName}`,
            application.applicantPhone,
            `Service area · ${application.serviceZoneName}`,
            `Submitted ${formatDate(application.submittedAt)}`,
          ]} location={{ latitude: application.latitude, longitude: application.longitude }} evidence={[{ label: "View business evidence", path: application.evidenceObjectPath }]} approvalSummary={`Approval creates one active ${application.merchantType === "RESTAURANT_CAFE" ? "restaurant" : "retail"} organization and branch in ${application.serviceZoneName}, grants this applicant Merchant owner access, and starts the branch closed until the merchant opens it.`} busy={Boolean(busy)} onEvidence={openEvidence} onReview={(decision, reason) => review("merchant", application.applicationId, decision, reason)} />)}</ApprovalSection>
          <ApprovalSection title="Delivery Partner applications" count={partners.length} empty={approvalEmptyMessage(feedStates.deliveryApprovals, "delivery")}>{partners.map((application) => <ReviewCard key={application.applicationId} icon={<Navigation size={20} />} title={application.displayName} subtitle={application.phoneNumber} facts={[methodLabel(application.deliveryMethod), ...(application.vehicleRegistrationNumber ? [`${application.vehicleRegistrationNumber} · ${application.vehicleMakeModel}`] : []), `Submitted ${formatDate(application.submittedAt)}`]} evidence={[{ label: "View identity proof", path: application.identityEvidenceObjectPath }, ...(application.vehicleEvidenceObjectPath ? [{ label: "View vehicle RC", path: application.vehicleEvidenceObjectPath }] : [])]} approvalSummary="Approval creates the verified Delivery Partner profile and starts it offline. The rider must deliberately go online from an active service area before receiving work." busy={Boolean(busy)} onEvidence={openEvidence} onReview={(decision, reason) => review("partner", application.applicationId, decision, reason)} />)}</ApprovalSection>
        </div>
        : tab === "legacy" ? <OrdersPanel orders={orders} available={adminFeedHasContent(feedStates.legacyHistory)} busy={Boolean(busy)} query={legacyQueryInput} hasMore={legacyHasMore} onQuery={setLegacyQueryInput} onSearch={() => {
          const next = legacyQueryInput.trim();
          if (next === legacyQuery) void refreshFeed("legacyHistory"); else setLegacyQuery(next);
        }} onLoadMore={loadMoreLegacy} onReview={reviewRefund} onRefund={retryRefund} />
        : <ExceptionsPanel operations={operations} available={adminFeedHasContent(feedStates.operations)} busy={Boolean(busy)} hasMore={exceptionsHaveMore} onLoadMore={loadMoreExceptions} onResolve={resolveSupport} onReset={resetHandoff} onReconcile={reconcile} onReviewRefund={() => setTab("legacy")} />}
    </main>

    </div>
  </AdminRuntimeProvider>;
}

function AdminFeedStatus({ states, realtimeHealth }: {
  states: Record<AdminBootstrapFeed, AdminFeedState>;
  realtimeHealth: "connecting" | "subscribed" | "degraded";
}) {
  const activeIssues = adminBootstrapFeeds
    .filter((feed) => states[feed].phase === "failed-with-content" || states[feed].phase === "failed-without-content");
  const stale = realtimeHealth !== "subscribed" && adminBootstrapFeeds.some((feed) => states[feed].phase === "stale");
  if (activeIssues.length === 0 && !stale) return null;
  return <section className="admin-feed-status" aria-label="Workspace refresh status">
    <header><span><WifiOff size={18} /></span><div><strong>{activeIssues.length ? "Some workspaces are temporarily unavailable" : "Live updates are reconnecting"}</strong><p>{activeIssues.length ? "Current successful data stays visible while Dastak retries automatically." : "Last-known data remains visible while the authenticated channel reconnects."}</p></div></header>
    {activeIssues.length ? <ul>{activeIssues.map((feed) => <li key={feed}><div><strong>{adminFeedLabels[feed]}</strong><span>{feedFailureMessage(feed, states[feed].error)}</span></div><small>{formatFeedUpdatedAt(states[feed].updatedAt)}</small></li>)}</ul> : null}
  </section>;
}

function tabTitle(tab: AdminTab) {
  return ({
    overview: "Command center", approvals: "Application approvals", exceptions: "Exception desk",
    orders: "Live order control", network: "Marketplace network", catalogue: "Master catalogue",
    audit: "Audit History", merchants: "Merchant governance", riders: "Rider governance", customers: "Customer recovery",
    safety: "Safety controls", finance: "Finance & payouts", health: "System health",
    access: "Admin access", legacy: "Historical orders", account: "My account",
  } satisfies Record<AdminTab, string>)[tab];
}

function tabDescription(tab: AdminTab) {
  return ({
    overview: "A connected, real-time view of the Dastak marketplace.",
    approvals: "Review Merchant and Delivery Partner evidence with a complete audit trail.",
    exceptions: "Resolve customer support, refunds, secure handoffs and stalled lifecycles.",
    orders: "Inspect matching, preparation, custody, collection, delivery and financial truth.",
    network: "Understand every identity and its independently onboarded personas.",
    audit: "Search reviewed, append-only operational history across current and legacy Dastak systems.",
    merchants: "Govern organization and branch eligibility, routing records and operational context.",
    riders: "Govern Delivery Partner eligibility while preserving active-work custody and availability controls.",
    customers: "Review Customer sessions and correct governed contact claims without changing OAuth identity.",
    catalogue: "Control exact SKUs, evidence, QA readiness, pricing and visibility.",
    safety: "Manage scoped pauses and rider recovery without weakening custody.",
    finance: "Review earned Royalty and controlled payout readiness.",
    health: "Monitor invariants, outbox delivery and reconciliation queues.",
    access: "Protect one permanent Superadmin and two replaceable Executive Admin seats.",
    legacy: "Read-only oversight for the pre-V1 order lifecycle.",
    account: "Profile, security, sessions and sign-out controls.",
  } satisfies Record<AdminTab, string>)[tab];
}

function adminRoleLabel(role?: V1AdminAccess["role"]) {
  return role === "SUPERADMIN" ? "Superadmin" : role === "EXECUTIVE_ADMIN" ? "Executive Admin" : "Admin";
}

function ExceptionsPanel({ operations, available, busy, hasMore, onLoadMore, onResolve, onReset, onReconcile, onReviewRefund }: {
  operations?: OwnerOperationsSnapshot;
  available: boolean;
  busy: boolean;
  hasMore: boolean;
  onLoadMore: () => Promise<void>;
  onResolve: (exception: OwnerOrderException, resolution: string) => Promise<void>;
  onReset: (exception: OwnerOrderException, reason: string) => Promise<void>;
  onReconcile: () => Promise<void>;
  onReviewRefund: () => void;
}) {
  const exceptions = operations?.exceptions ?? [];
  const [confirmRecovery, setConfirmRecovery] = useState(false);
  return (
    <section className="admin-section admin-exceptions" role="tabpanel">
      <header>
        <div><h2>Exceptions</h2><p>Support, locked handoffs, refunds and stalled deliveries.</p></div>
        <button className="secondary-button" type="button" disabled={busy} onClick={() => setConfirmRecovery(true)}><RotateCcw size={17} /> Run recovery</button>
      </header>
      {exceptions.length === 0 ? <p className="admin-empty">{available ? "No marketplace exceptions need attention." : "Exception data is not available yet."}</p> : (
        <div className="exception-list">
          {exceptions.map((exception) => (
            <ExceptionCard
              key={exception.exceptionId}
              exception={exception}
              busy={busy}
              onResolve={onResolve}
              onReset={onReset}
              onReviewRefund={onReviewRefund}
              onReconcile={onReconcile}
            />
          ))}
        </div>
      )}
      {exceptions.length > 0 ? <button className="secondary-button admin-page-more" type="button" disabled={busy || !hasMore} onClick={() => void onLoadMore()}>{hasMore ? "Load older exceptions" : "All current exceptions loaded"}</button> : null}
      {confirmRecovery ? <AdminPrivilegedActionDialog intent={{
        title: "Run marketplace lifecycle recovery?", entityLabel: "Operational scope", entityValue: "Stalled merchant orders and parcel deliveries",
        currentState: `${operations?.summary.stalledOrders ?? 0} stalled lifecycle signal(s)`, resultingState: "Authoritative state reconciled; eligible offers may be recreated",
        consequence: "Recovery may repair stalled lifecycle records and create new rider offers. It does not bypass payment, assignment, custody, or handoff rules.",
        confirmLabel: "Run controlled recovery",
      }} busy={busy} onDismiss={() => setConfirmRecovery(false)} onConfirm={async () => {
        await onReconcile(); setConfirmRecovery(false);
      }} /> : null}
    </section>
  );
}

function ExceptionCard({ exception, busy, onResolve, onReset, onReviewRefund, onReconcile }: {
  exception: OwnerOrderException;
  busy: boolean;
  onResolve: (exception: OwnerOrderException, resolution: string) => Promise<void>;
  onReset: (exception: OwnerOrderException, reason: string) => Promise<void>;
  onReviewRefund: () => void;
  onReconcile: () => Promise<void>;
}) {
  const [note, setNote] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [intent, setIntent] = useState<"resolve" | "reset" | "recover">();
  const requiresNote = exception.kind === "support" || exception.kind === "handoff_locked";

  const submit = async () => {
    if (note.trim().length < 5) return;
    setSubmitting(true);
    try {
      if (exception.kind === "support") await onResolve(exception, note.trim());
      if (exception.kind === "handoff_locked") await onReset(exception, note.trim());
      setIntent(undefined);
      setNote("");
    } catch {
      // The dashboard keeps the note in place and displays the action error.
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <article className={`exception-card ${exception.severity}`}>
      <header><span><CircleAlert size={19} /></span><div><p className="eyebrow">{exception.kind.replaceAll("_", " ")}</p><h3>{exception.title}</h3></div><time>{formatDate(exception.occurredAt)}</time></header>
      <p>{exception.detail}</p>
      <small>{exception.entityKind.replaceAll("_", " ")} · {shortId(exception.entityId)} · {exception.status.replaceAll("_", " ")}</small>
      {requiresNote && <div className="exception-action"><input value={note} maxLength={exception.kind === "support" ? 500 : 300} onChange={(event) => setNote(event.target.value)} placeholder={exception.kind === "support" ? "Resolution shared with the customer" : "Reason for secure code reset"} /><button className="primary-button" type="button" disabled={busy || submitting || note.trim().length < 5} onClick={() => setIntent(exception.kind === "support" ? "resolve" : "reset")}>{exception.kind === "support" ? "Resolve case" : "Reset code"}</button></div>}
      {exception.kind === "refund_review" && <button className="primary-button" type="button" disabled={busy} onClick={onReviewRefund}>Review refund</button>}
      {exception.kind === "stalled_order" && <button className="secondary-button" type="button" disabled={busy} onClick={() => setIntent("recover")}><RotateCcw size={17} /> Recover lifecycle</button>}
      {intent ? <AdminPrivilegedActionDialog intent={{
        title: intent === "resolve" ? "Resolve this customer support case?" : intent === "reset" ? "Reset this secure handoff?" : "Recover this stalled lifecycle?",
        entityLabel: exception.entityKind.replaceAll("_", " "), entityValue: `${exception.title} · ${exception.entityId}`,
        currentState: exception.status.replaceAll("_", " "),
        resultingState: intent === "resolve" ? "Support case resolved" : intent === "reset" ? `${exception.purpose ?? "Handoff"} code invalidated and regenerated` : "Lifecycle reconciled; eligible work may resume",
        consequence: intent === "resolve"
          ? "This closes the customer issue with the exact resolution shown and records the operator action."
          : intent === "reset"
            ? "The current secure code becomes invalid. A replacement code is generated for the same handoff; package custody does not change."
            : "Recovery can repair stalled state and create a new rider offer, but cannot bypass payment, assignment, custody, or verification rules.",
        confirmLabel: intent === "resolve" ? "Resolve case" : intent === "reset" ? "Reset secure code" : "Run recovery",
        tone: intent === "reset" ? "danger" : "primary",
        reason: intent === "recover" ? undefined : note.trim(),
      }} busy={busy || submitting} onDismiss={() => setIntent(undefined)} onConfirm={intent === "recover" ? async () => {
        setSubmitting(true); try { await onReconcile(); setIntent(undefined); } finally { setSubmitting(false); }
      } : submit} /> : null}
    </article>
  );
}

function ApprovalSection({ title, count, empty, children }: { title: string; count: number; empty: string; children: ReactNode }) {
  return (
    <section className="admin-section">
      <header><h2>{title}</h2><span>{count}</span></header>
      {count === 0 ? <p className="admin-empty">{empty}</p> : <div className="review-list">{children}</div>}
    </section>
  );
}

function ReviewCard({ icon, title, subtitle, facts, evidence, location, approvalSummary, busy, onEvidence, onReview }: {
  icon: ReactNode;
  title: string;
  subtitle: string;
  facts: string[];
  evidence: Array<{ label: string; path: string }>;
  location?: { latitude: number; longitude: number };
  approvalSummary: string;
  busy: boolean;
  onEvidence: (path: string) => Promise<void>;
  onReview: (decision: ReviewDecision, reason?: string) => Promise<void>;
}) {
  const [mode, setMode] = useState<ReviewDecision>();

  const confirm = async (reason: string) => {
    if (!mode) return;
    try {
      await onReview(mode, reason);
      setMode(undefined);
    } catch {
      // The dashboard displays the server error and preserves the review form.
    }
  };

  return (
    <article className="review-card">
      <header><span className="review-icon">{icon}</span><div><h3>{title}</h3><p>{subtitle}</p></div></header>
      <div className="review-facts">{facts.map((fact) => <span key={fact}>{fact}</span>)}</div>
      {location ? <a className="evidence-button" href={`https://maps.apple.com/?ll=${location.latitude},${location.longitude}&q=Store`} target="_blank" rel="noreferrer"><Store size={17} /> Open exact store pin <ExternalLink size={14} /></a> : null}
      {evidence.map((document) => (
        <button key={document.path} className="evidence-button" type="button" disabled={busy} onClick={() => void onEvidence(document.path)}>
          <FileText size={17} /> {document.label} <ExternalLink size={14} />
        </button>
      ))}
      {!mode ? (
        <div className="review-actions">
          <button className="danger-button" type="button" disabled={busy} onClick={() => setMode("reject")}><X size={17} /> Reject</button>
          <button className="primary-button" type="button" disabled={busy} onClick={() => setMode("approve")}><Check size={17} /> Approve</button>
        </div>
      ) : null}
      {mode ? <AdminPrivilegedActionDialog intent={{
        title: `${mode === "approve" ? "Approve" : "Reject"} this application?`,
        entityLabel: "Reviewed applicant", entityValue: `${title} · ${subtitle}`,
        currentState: "Application pending review", resultingState: mode === "approve" ? "Approved and operational profile created" : "Application rejected",
        consequence: mode === "approve" ? approvalSummary : "The applicant will not receive operational access. The decision and operator reason are recorded for audit.",
        confirmLabel: mode === "approve" ? "Approve application" : "Reject application", tone: mode === "reject" ? "danger" : "primary",
        reasonOptions: mode === "approve"
          ? ["Evidence verified", "Eligibility verified", "Compliance review complete", "Other"]
          : ["Evidence could not be verified", "Eligibility requirements not met", "Application information incomplete", "Compliance concern", "Other"],
      }} busy={busy} onDismiss={() => setMode(undefined)} onConfirm={confirm} /> : null}
    </article>
  );
}

function OrdersPanel({ orders, available, busy, query, hasMore, onQuery, onSearch, onLoadMore, onReview, onRefund }: {
  orders: AdminOrder[];
  available: boolean;
  busy: boolean;
  query: string;
  hasMore: boolean;
  onQuery: (query: string) => void;
  onSearch: () => void;
  onLoadMore: () => Promise<void>;
  onReview: (
    order: AdminOrder,
    outcome: "approve_full" | "approve_items_only" | "deny",
    faultSource: "merchant" | "dastak" | null,
    reason: string,
  ) => Promise<void>;
  onRefund: (order: AdminOrder) => Promise<void>;
}) {
  return (
    <section className="admin-section admin-orders" role="tabpanel">
      <header><h2>Recent orders</h2><span>{orders.length}</span></header>
      <form className="admin-feed-search" role="search" onSubmit={(event) => { event.preventDefault(); onSearch(); }}><label htmlFor="admin-legacy-search">Search legacy history</label><span><input id="admin-legacy-search" type="search" value={query} maxLength={80} placeholder="Exact order ID or store name" onChange={(event) => onQuery(event.target.value)} /><button className="secondary-button" type="submit">Search</button></span></form>
      {orders.length === 0 ? <p className="admin-empty">{available ? "No historical orders yet." : "Historical order data is not available yet."}</p> : (
        <div className="admin-order-table" role="table" aria-label="Recent orders">
          <div className="admin-order-header" role="row"><span role="columnheader">Order</span><span role="columnheader">Store</span><span role="columnheader">Status</span><span role="columnheader">Payment</span><span role="columnheader">Total</span></div>
          {orders.map((order) => (
            <AdminOrderRow key={order.orderId} order={order} busy={busy} onReview={onReview} onRefund={onRefund} />
          ))}
        </div>
      )}
      {orders.length > 0 ? <button className="secondary-button admin-page-more" type="button" disabled={busy || !hasMore} onClick={() => void onLoadMore()}>{hasMore ? "Load older orders" : "End of matching history"}</button> : null}
    </section>
  );
}

function AdminOrderRow({ order, busy, onReview, onRefund }: {
  order: AdminOrder;
  busy: boolean;
  onReview: (
    order: AdminOrder,
    outcome: "approve_full" | "approve_items_only" | "deny",
    faultSource: "merchant" | "dastak" | null,
    reason: string,
  ) => Promise<void>;
  onRefund: (order: AdminOrder) => Promise<void>;
}) {
  const postPickup = order.refundDecision?.eligibility === "delivery_fee_retained_unless_fault" ||
    ["picked_up", "in_transit", "returning_to_merchant"].includes(order.status);
  const [outcome, setOutcome] = useState<"approve_full" | "approve_items_only" | "deny">(
    postPickup ? "approve_items_only" : "approve_full",
  );
  const [faultSource, setFaultSource] = useState<"merchant" | "dastak" | "">("");
  const [reason, setReason] = useState("");
  const [confirming, setConfirming] = useState<"decision" | "provider">();
  const needsFault = postPickup && outcome === "approve_full";

  return (
    <article className="admin-order-row" role="row">
      <div role="cell" data-label="Order"><strong>{shortId(order.orderId)}</strong><small>{formatDate(order.createdAt)} · {order.itemCount} items</small></div>
      <strong role="cell" data-label="Store">{order.store.name}</strong>
      <span role="cell" data-label="Status" className={`admin-status status-${order.status}`}>{orderStatusLabel(order.status)}</span>
      <span role="cell" data-label="Payment">{paymentLabel(order.paymentState)}</span>
      <strong role="cell" data-label="Total">{formatPrice(order.total.paise)}</strong>

      {order.refundDecision?.decisionStatus === "review_required" && (
        <div className="admin-refund-review">
          <strong>Refund review</strong>
          <small>{order.refundDecision.reason}</small>
          <select value={outcome} onChange={(event) => setOutcome(event.target.value as typeof outcome)} aria-label="Refund decision">
            {postPickup && <option value="approve_items_only">Refund items only</option>}
            <option value="approve_full">Full refund</option>
            <option value="deny">Deny refund</option>
          </select>
          {needsFault && (
            <select value={faultSource} onChange={(event) => setFaultSource(event.target.value as typeof faultSource)} aria-label="Responsible party">
              <option value="">Select responsible party</option>
              <option value="merchant">Merchant fault</option>
              <option value="dastak">Dastak fault</option>
            </select>
          )}
            <input value={reason} maxLength={300} onChange={(event) => setReason(event.target.value)} placeholder="Decision reason" aria-label="Refund decision reason" />
          <button
            className="primary-button"
            type="button"
            disabled={busy || !reason.trim() || (needsFault && !faultSource)}
            onClick={() => setConfirming("decision")}
          >
            Submit decision
          </button>
        </div>
      )}

      {order.paymentState === "refund_pending" && order.status !== "returning_to_merchant" && (
        <div className="admin-refund-review">
          <strong>Refund pending</strong>
          <small>Retry safely if the provider call did not finish.</small>
          <button className="primary-button" type="button" disabled={busy} onClick={() => setConfirming("provider")}>Process refund</button>
        </div>
      )}
      {confirming ? <AdminPrivilegedActionDialog intent={{
        title: confirming === "provider" ? "Submit this provider refund?" : "Record this refund decision?",
        entityLabel: "Order", entityValue: `${shortId(order.orderId)} · ${order.store.name} · ${formatPrice(order.total.paise)}`,
        currentState: `${orderStatusLabel(order.status)} · ${paymentLabel(order.paymentState)}`,
        resultingState: confirming === "provider" ? "Original-method refund submitted" : outcome === "deny" ? "Refund denied" : outcome === "approve_items_only" ? "Item refund approved" : "Full refund approved",
        consequence: confirming === "provider"
          ? "Dastak will ask the payment provider to return the approved amount through the original payment method. An uncertain response is reconciled before any retry."
          : outcome === "deny"
            ? "No refund will be issued from this decision. The operator reason is preserved in the order audit trail."
            : `${outcome === "approve_full" ? "The full eligible amount" : "The item subtotal only"} becomes refundable. If eligible, provider processing may begin immediately after this decision.`,
        confirmLabel: confirming === "provider" ? "Submit provider refund" : "Record decision",
        tone: outcome === "deny" ? "danger" : "primary",
        reason: confirming === "provider" ? undefined : reason.trim(),
      }} busy={busy} onDismiss={() => setConfirming(undefined)} onConfirm={async () => {
        if (confirming === "provider") await onRefund(order);
        else await onReview(order, outcome, faultSource || null, reason.trim());
        setConfirming(undefined);
      }} /> : null}
    </article>
  );
}

function shortId(value: string) { return `#${value.slice(0, 8).toUpperCase()}`; }
function mergeById<T>(current: T[], incoming: T[], key: (value: T) => string) {
  const merged = new Map(current.map((value) => [key(value), value]));
  incoming.forEach((value) => merged.set(key(value), value));
  return Array.from(merged.values());
}
function formatDate(value: string) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
function formatFeedUpdatedAt(value?: number) {
  return value ? `Last updated ${formatDate(new Date(value).toISOString())}` : "No successful response yet";
}
function methodLabel(value: string) {
  if (value === "goods_vehicle") return "Tempo / goods vehicle";
  if (value === "motorbike" || value === "bike") return "Motorbike";
  return value.charAt(0).toUpperCase() + value.slice(1);
}
function paymentLabel(value: AdminOrder["paymentState"]) {
  return value.split("_").map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
}
function feedFailureMessage(feed: AdminBootstrapFeed, error: unknown) {
  if (isAdminSessionExpired(error)) {
    return "Your Admin session needs to be refreshed. Reopen the app or sign in again.";
  }
  return ({
    merchantApprovals: "Merchant applications could not be refreshed.",
    deliveryApprovals: "Delivery Partner applications could not be refreshed.",
    legacyHistory: "Read-only historical orders could not be refreshed.",
    operations: "Support, refunds and recovery signals could not be refreshed.",
    adminAccess: "Protected Admin access settings could not be refreshed.",
    commandCenter: "Command center metrics could not be refreshed.",
  } satisfies Record<AdminBootstrapFeed, string>)[feed];
}
function approvalEmptyMessage(state: AdminFeedState, kind: "merchant" | "delivery") {
  const label = kind === "merchant" ? "merchant applications" : "Delivery Partner applications";
  if (state.phase === "loading") return `Loading ${label}…`;
  if (state.phase === "failed-without-content") return `${label.charAt(0).toUpperCase()}${label.slice(1)} are not available yet.`;
  return `No pending ${label}.`;
}
function message(error: unknown) { return userFacingError(error, "Dastak Admin is unavailable."); }
