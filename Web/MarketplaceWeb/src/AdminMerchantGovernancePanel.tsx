import { useCallback, useEffect, useRef, useState } from "react";
import { Building2, CheckCircle2, ChevronDown, MapPin, PauseCircle, Search, Settings2, ShieldAlert } from "lucide-react";
import { AdminPrivilegedActionDialog, type AdminPrivilegedActionIntent } from "./AdminPrivilegedActionDialog";
import { runAdminPrivilegedMutation } from "./adminPrivilegedMutation";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { useAdminRuntime } from "./AdminRuntimeContext";
import {
  correctV1AdminMerchantBranchDetails,
  getV1AdminMerchantGovernancePage,
  setV1AdminMerchantBranchStatus,
  setV1AdminMerchantOrganizationStatus,
  type DastakV1Auth,
  type V1AdminMerchantBranchChanges,
  type V1AdminMerchantGovernanceRow,
} from "./dastakV1";
import { adminFeedFailed, adminFeedHasContent, adminFeedStarted, adminFeedSucceeded, initialAdminFeedState } from "./adminRuntime";
import { RefreshQueue } from "./orderRealtime";
import { userFacingError } from "./userFacingError";

type Intent = {
  dialog: AdminPrivilegedActionIntent;
  operationIdentity: string;
  mutate: (idempotencyKey: string, reason: string) => Promise<unknown>;
  success: string;
};

type BranchDraft = {
  displayName: string;
  line1: string;
  line2: string;
  city: string;
  state: string;
  postalCode: string;
  countryCode: string;
  latitude: string;
  longitude: string;
  serviceZoneId: string;
  capacityLimit: string;
};

export function AdminMerchantGovernancePanel({ auth }: { auth: DastakV1Auth }) {
  const [query, setQuery] = useState("");
  const [rows, setRows] = useState<V1AdminMerchantGovernanceRow[]>([]);
  const [serviceZones, setServiceZones] = useState<Array<{ id: string; name: string }>>([]);
  const [cursor, setCursor] = useState<{ updatedAt: string; rowId: string }>();
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [feedState, setFeedState] = useState(initialAdminFeedState());
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [reconciliationBlocked, setReconciliationBlocked] = useState(false);
  const [intent, setIntent] = useState<Intent>();
  const [editing, setEditing] = useState<string>();
  const [draft, setDraft] = useState<BranchDraft>();
  const requestGeneration = useRef(0);
  const controller = useRef<AbortController | undefined>(undefined);
  const queue = useRef(new RefreshQueue());
  const { reportRequestError } = useAdminRuntime();
  const normalizedQuery = query.trim();

  const load = useCallback(async (append: boolean, signal?: AbortSignal) => {
    const generation = ++requestGeneration.current;
    if (append) setLoadingMore(true);
    else setFeedState((current) => adminFeedStarted(current));
    try {
      const page = await getV1AdminMerchantGovernancePage({
        ...auth,
        query: normalizedQuery,
        limit: 40,
        cursor: append ? cursor : undefined,
        signal,
      });
      if (signal?.aborted || generation !== requestGeneration.current) return;
      setRows((current) => append ? mergeRows(current, page.merchants) : page.merchants);
      setServiceZones(page.serviceZones);
      setCursor(page.nextCursor);
      setHasMore(page.hasMore);
      setFeedState((current) => adminFeedSucceeded(current));
      setError(undefined);
    } catch (cause) {
      if (signal?.aborted || generation !== requestGeneration.current) return;
      reportRequestError(cause);
      setFeedState((current) => adminFeedFailed(current, cause));
      setError(message(cause));
      throw cause;
    } finally {
      if (generation === requestGeneration.current) setLoadingMore(false);
    }
  }, [auth, cursor, normalizedQuery, reportRequestError]);

  const refresh = useCallback(() => queue.current.request(false, async () => {
    controller.current?.abort();
    const next = new AbortController();
    controller.current = next;
    await load(false, next.signal);
  }), [load]);

  useEffect(() => {
    controller.current?.abort();
    const next = new AbortController();
    controller.current = next;
    const timer = window.setTimeout(() => void load(false, next.signal).catch(() => undefined), 250);
    return () => { window.clearTimeout(timer); next.abort(); };
    // Cursor belongs to append-only loading and must not restart filtered first pages.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth, normalizedQuery]);
  useAdminWorkspaceRefresh("merchantGovernance", refresh);

  const beginStatus = (
    row: V1AdminMerchantGovernanceRow,
    target: "organization" | "branch",
  ) => {
    const entity = row[target];
    const nextStatus = entity.status === "SUSPENDED" ? "ACTIVE" : "SUSPENDED";
    const suspending = nextStatus === "SUSPENDED";
    const isOrganization = target === "organization";
    setIntent({
      operationIdentity: `merchant-governance:${target}:${entity.id}:${entity.version}:${nextStatus}`,
      success: `${isOrganization ? "Merchant organization" : "Branch"} ${suspending ? "suspended" : "reactivated"}.`,
      dialog: {
        eyebrow: "Merchant governance",
        title: `${suspending ? "Suspend" : "Reactivate"} ${isOrganization ? "Merchant organization" : "branch"}?`,
        entityLabel: isOrganization ? "Organization" : "Branch",
        entityValue: isOrganization
          ? `${row.organization.displayName} · ${row.organization.id}`
          : `${row.organization.displayName} / ${row.branch.displayName} · ${row.branch.id}`,
        currentState: entity.status,
        resultingState: nextStatus,
        consequence: suspending
          ? isOrganization
            ? "The organization becomes ineligible for new work. Active committed fulfilments or custody will block this action and must be resolved first. Merchant-controlled open/closed state is preserved."
            : "This branch becomes governance-ineligible for new work. Existing operational pause and merchant-controlled open/closed state remain separate and unchanged."
          : "Governance eligibility is restored. The existing operational pause and merchant-controlled open/closed state are not changed.",
        confirmLabel: suspending ? "Confirm suspension" : "Confirm reactivation",
        tone: suspending ? "danger" : "primary",
        reasonOptions: suspending
          ? ["Compliance intervention", "Safety intervention", "Onboarding issue", "Authorized support action", "Other"]
          : ["Compliance cleared", "Safety cleared", "Onboarding corrected", "Authorized support action", "Other"],
        confirmationValue: suspending ? entity.displayName : undefined,
      },
      mutate: (idempotencyKey, reason) => isOrganization
        ? setV1AdminMerchantOrganizationStatus({
          ...auth, organizationId: row.organization.id, status: nextStatus,
          expectedVersion: row.organization.version, reason, idempotencyKey,
        })
        : setV1AdminMerchantBranchStatus({
          ...auth, branchId: row.branch.id, status: nextStatus,
          expectedVersion: row.branch.version, reason, idempotencyKey,
        }),
    });
  };

  const beginEdit = (row: V1AdminMerchantGovernanceRow) => {
    setEditing(row.branch.id);
    setDraft(draftFor(row));
    setError(undefined);
    setNotice(undefined);
  };

  const reviewCorrection = (row: V1AdminMerchantGovernanceRow) => {
    if (!draft) return;
    const latitude = Number(draft.latitude);
    const longitude = Number(draft.longitude);
    const capacity = Number(draft.capacityLimit);
    if (!draft.displayName.trim() || !draft.line1.trim() || draft.countryCode.trim().length !== 2 ||
      !draft.latitude.trim() || !draft.longitude.trim() ||
      !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
      !Number.isSafeInteger(capacity) || capacity < 1 || capacity > 500 || !draft.serviceZoneId) {
      setError("Review the branch name, pickup address, coordinates, active service zone and capacity before continuing.");
      return;
    }
    const changes = changesFor(row, draft);
    const changedFields = Object.keys(changes);
    if (changedFields.length === 0) {
      setError("No reviewed branch values have changed.");
      return;
    }
    const routeCritical = changedFields.some((field) => ["address", "latitude", "longitude", "serviceZoneId"].includes(field));
    setIntent({
      operationIdentity: `merchant-branch-correction:${row.branch.id}:${row.branch.version}:${JSON.stringify(changes)}`,
      success: "The reviewed branch details were corrected and authoritative state was reloaded.",
      dialog: {
        eyebrow: "Route-critical correction",
        title: "Apply reviewed branch corrections?",
        entityLabel: "Merchant branch",
        entityValue: `${row.organization.displayName} / ${row.branch.displayName} · ${row.branch.id}`,
        currentState: `Version ${row.branch.version} · ${summaryAddress(row)}`,
        resultingState: `${changedFields.join(", ")} updated`,
        consequence: routeCritical
          ? "Pickup routing and 50 m proximity use these destination values. Active pickup or return work will block this change so a rider's destination can never move underneath them."
          : "Only the reviewed branch presentation or capacity value changes. Merchant type, open/closed state, operational pause and historical onboarding remain unchanged.",
        confirmLabel: "Apply corrections",
        reasonOptions: ["Correct verified branch record", "Service-zone correction", "Route correction", "Capacity correction", "Other"],
        confirmationValue: row.branch.displayName,
      },
      mutate: (idempotencyKey, reason) => correctV1AdminMerchantBranchDetails({
        ...auth, branchId: row.branch.id, changes,
        expectedVersion: row.branch.version, reason, idempotencyKey,
      }),
    });
  };

  const perform = async (reason: string) => {
    if (!intent || busy) return;
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    setReconciliationBlocked(false);
    const result = await runAdminPrivilegedMutation({
      operationIdentity: intent.operationIdentity,
      mutate: (key) => intent.mutate(key, reason),
      reconcile: refresh,
    });
    setBusy(false);
    if (result.kind === "completed") {
      setNotice(intent.success);
      setIntent(undefined);
      setEditing(undefined);
      setDraft(undefined);
      await refresh().catch(() => undefined);
    } else if (result.kind === "reconciled" || result.kind === "uncertain_reconciled") {
      setNotice(result.message);
      setIntent(undefined);
      setEditing(undefined);
      setDraft(undefined);
    } else if (result.kind === "uncertain_blocked") {
      setReconciliationBlocked(true);
      setError(result.message);
    } else {
      reportRequestError(result.error);
      setError(message(result.error));
    }
  };

  const reconcileIntent = async () => {
    setBusy(true);
    try {
      await refresh();
      setReconciliationBlocked(false);
      setNotice("Authoritative Merchant state was reloaded. Review it before acting again.");
      setIntent(undefined);
      setEditing(undefined);
      setDraft(undefined);
    } catch (cause) {
      setError(message(cause));
    } finally {
      setBusy(false);
    }
  };

  return <section className="admin-section admin-merchant-governance" role="tabpanel">
    <header className="admin-section-heading"><div><p className="eyebrow">MERCHANT GOVERNANCE</p><h2>Organizations & branches</h2><p>Govern eligibility, correct reviewed routing records and keep operational pauses distinct from merchant open/closed state.</p></div></header>
    <label className="admin-search admin-governance-search"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search organization, legal name, branch or exact ID" aria-label="Search Merchant governance" /></label>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {notice ? <p className="admin-access-message success" role="status">{notice}</p> : null}
    {feedState.phase === "loading" ? <div className="admin-directory-loading" role="status"><span /><p>Loading governed Merchant records…</p></div> : null}
    {rows.length === 0 && adminFeedHasContent(feedState) ? <div className="admin-empty-state"><Building2 size={28} /><h3>No Merchant branches match</h3><p>Try another name or exact organization/branch ID.</p></div> : null}
    <div className="admin-governance-list">
      {rows.map((row) => <article className="admin-governance-card" key={row.branch.id}>
        <header>
          <span className="admin-person-mark" aria-hidden="true"><Building2 size={20} /></span>
          <div><p className="eyebrow">{label(row.organization.merchantType)}</p><h3>{row.organization.displayName}</h3><p>{row.organization.legalName}</p></div>
          <div className="admin-governance-statuses"><Status value={row.organization.status} label="Organization" /><Status value={row.branch.status} label="Branch" /></div>
        </header>
        <div className="admin-governance-branch">
          <div><strong>{row.branch.displayName}</strong><span><MapPin size={14} /> {summaryAddress(row)}</span><small>{row.branch.serviceZone.name ?? "No service zone"} · {formatCoordinates(row)}</small></div>
          <dl>
            <div><dt>Operations</dt><dd>{row.branch.operationalState.isOpen ? "Open" : "Closed"} · {row.branch.operationalState.acceptingOrders ? "Accepting" : "Not accepting"}</dd></div>
            <div><dt>Capacity</dt><dd>{row.branch.capacityLimit}</dd></div>
            <div><dt>Active fulfilments</dt><dd>{row.branch.activeNonTerminalFulfilmentCount}</dd></div>
            <div><dt>Pickup / returns</dt><dd>{row.branch.activePickupReturnWorkCount}</dd></div>
          </dl>
          {row.branch.operationalPause?.active ? <p className="admin-governance-pause"><PauseCircle size={15} /> Operational pause active · {row.branch.operationalPause.reason}</p> : <p className="admin-governance-live"><CheckCircle2 size={15} /> No branch operational pause</p>}
        </div>
        <footer>
          <button className="secondary-button" type="button" disabled={busy || !["ACTIVE", "SUSPENDED"].includes(row.organization.status) || (row.organization.status === "ACTIVE" && (row.organization.activeNonTerminalFulfilmentCount > 0 || row.organization.activePickupReturnWorkCount > 0))} onClick={() => beginStatus(row, "organization")}>
            <ShieldAlert size={16} /> {row.organization.status === "SUSPENDED" ? "Reactivate organization" : "Suspend organization"}
          </button>
          <button className="secondary-button" type="button" disabled={busy || !["ACTIVE", "SUSPENDED"].includes(row.branch.status)} onClick={() => beginStatus(row, "branch")}>
            {row.branch.status === "SUSPENDED" ? <CheckCircle2 size={16} /> : <ShieldAlert size={16} />} {row.branch.status === "SUSPENDED" ? "Reactivate branch" : "Suspend branch"}
          </button>
          <button className="secondary-button" type="button" disabled={busy} onClick={() => beginEdit(row)}><Settings2 size={16} /> Correct details</button>
          {row.organization.status === "ACTIVE" && (row.organization.activeNonTerminalFulfilmentCount > 0 || row.organization.activePickupReturnWorkCount > 0) ? <small>Resolve {row.organization.activeNonTerminalFulfilmentCount} fulfilment(s) and {row.organization.activePickupReturnWorkCount} custody journey(s) before organization suspension.</small> : null}
        </footer>
        {editing === row.branch.id && draft ? <BranchCorrectionForm draft={draft} serviceZones={serviceZones.some((zone) => zone.id === row.branch.serviceZone.id) || !row.branch.serviceZone.id ? serviceZones : [{ id: row.branch.serviceZone.id, name: `${row.branch.serviceZone.name ?? "Current zone"} (current)` }, ...serviceZones]} disabled={busy} onChange={setDraft} onCancel={() => { setEditing(undefined); setDraft(undefined); }} onReview={() => reviewCorrection(row)} /> : null}
      </article>)}
    </div>
    {rows.length > 0 ? <button className="secondary-button admin-page-more" type="button" disabled={!hasMore || loadingMore} onClick={() => {
      controller.current?.abort();
      const next = new AbortController();
      controller.current = next;
      void load(true, next.signal).catch(() => undefined);
    }}>{loadingMore ? "Loading…" : hasMore ? "Load more Merchant branches" : "All matching branches loaded"}</button> : null}
    {intent ? <AdminPrivilegedActionDialog intent={intent.dialog} busy={busy} error={error} notice={notice} reconciliationBlocked={reconciliationBlocked} onReconcile={reconcileIntent} onDismiss={() => { setIntent(undefined); setError(undefined); setNotice(undefined); }} onConfirm={perform} /> : null}
  </section>;
}

function BranchCorrectionForm({ draft, serviceZones, disabled, onChange, onCancel, onReview }: {
  draft: BranchDraft;
  serviceZones: Array<{ id: string; name: string }>;
  disabled: boolean;
  onChange: (draft: BranchDraft) => void;
  onCancel: () => void;
  onReview: () => void;
}) {
  const set = (key: keyof BranchDraft, value: string) => onChange({ ...draft, [key]: value });
  return <form className="admin-branch-correction" onSubmit={(event) => { event.preventDefault(); onReview(); }}>
    <header><div><p className="eyebrow">REVIEWED CORRECTION</p><h4>Branch details</h4></div><small>Merchant type cannot be changed here.</small></header>
    <div className="admin-branch-correction-grid">
      <label><span>Customer-facing name</span><input disabled={disabled} value={draft.displayName} maxLength={100} onChange={(event) => set("displayName", event.target.value)} /></label>
      <label className="wide"><span>Pickup address line 1</span><input disabled={disabled} value={draft.line1} maxLength={200} onChange={(event) => set("line1", event.target.value)} /></label>
      <label className="wide"><span>Address line 2</span><input disabled={disabled} value={draft.line2} maxLength={200} onChange={(event) => set("line2", event.target.value)} /></label>
      <label><span>City</span><input disabled={disabled} value={draft.city} maxLength={100} onChange={(event) => set("city", event.target.value)} /></label>
      <label><span>State</span><input disabled={disabled} value={draft.state} maxLength={100} onChange={(event) => set("state", event.target.value)} /></label>
      <label><span>Postal code</span><input disabled={disabled} value={draft.postalCode} maxLength={20} onChange={(event) => set("postalCode", event.target.value)} /></label>
      <label><span>Country code</span><input disabled={disabled} value={draft.countryCode} maxLength={2} onChange={(event) => set("countryCode", event.target.value.toUpperCase())} /></label>
      <label><span>Latitude</span><input disabled={disabled} inputMode="decimal" value={draft.latitude} onChange={(event) => set("latitude", event.target.value)} /></label>
      <label><span>Longitude</span><input disabled={disabled} inputMode="decimal" value={draft.longitude} onChange={(event) => set("longitude", event.target.value)} /></label>
      <label><span>Service zone</span><select disabled={disabled} value={draft.serviceZoneId} onChange={(event) => set("serviceZoneId", event.target.value)}>{serviceZones.map((zone) => <option key={zone.id} value={zone.id}>{zone.name}</option>)}</select><ChevronDown size={15} /></label>
      <label><span>Capacity limit</span><input disabled={disabled} type="number" min={1} max={500} value={draft.capacityLimit} onChange={(event) => set("capacityLimit", event.target.value)} /></label>
    </div>
    <footer><button className="secondary-button" type="button" disabled={disabled} onClick={onCancel}>Cancel</button><button className="primary-button" type="submit" disabled={disabled}>Review corrections</button></footer>
  </form>;
}

function Status({ value, label: caption }: { value: string; label: string }) {
  return <span className={`admin-governance-status ${value.toLowerCase()}`}><small>{caption}</small><strong>{label(value)}</strong></span>;
}

function draftFor(row: V1AdminMerchantGovernanceRow): BranchDraft {
  const address = row.branch.normalizedAddress;
  return {
    displayName: row.branch.displayName,
    line1: address.line1 ?? "",
    line2: address.line2 ?? "",
    city: address.city ?? "",
    state: address.state ?? "",
    postalCode: address.postalCode ?? "",
    countryCode: address.countryCode ?? "IN",
    latitude: row.branch.latitude?.toString() ?? "",
    longitude: row.branch.longitude?.toString() ?? "",
    serviceZoneId: row.branch.serviceZone.id ?? "",
    capacityLimit: row.branch.capacityLimit.toString(),
  };
}

function changesFor(row: V1AdminMerchantGovernanceRow, draft: BranchDraft): V1AdminMerchantBranchChanges {
  const changes: V1AdminMerchantBranchChanges = {};
  const current = draftFor(row);
  if (draft.displayName.trim() !== current.displayName) changes.displayName = draft.displayName.trim();
  const addressChanged = (["line1", "line2", "city", "state", "postalCode", "countryCode"] as const)
    .some((key) => draft[key].trim() !== current[key]);
  if (addressChanged) changes.address = {
    line1: draft.line1.trim(), line2: draft.line2.trim() || undefined,
    city: draft.city.trim() || undefined, state: draft.state.trim() || undefined,
    postalCode: draft.postalCode.trim() || undefined,
    countryCode: draft.countryCode.trim().toUpperCase(),
  };
  if (draft.latitude.trim() !== current.latitude || draft.longitude.trim() !== current.longitude) {
    changes.latitude = Number(draft.latitude);
    changes.longitude = Number(draft.longitude);
  }
  if (draft.serviceZoneId !== current.serviceZoneId) changes.serviceZoneId = draft.serviceZoneId;
  if (draft.capacityLimit !== current.capacityLimit) changes.capacityLimit = Number(draft.capacityLimit);
  return changes;
}

function mergeRows(current: V1AdminMerchantGovernanceRow[], next: V1AdminMerchantGovernanceRow[]) {
  const rows = new Map(current.map((row) => [row.branch.id, row]));
  next.forEach((row) => rows.set(row.branch.id, row));
  return [...rows.values()];
}

function summaryAddress(row: V1AdminMerchantGovernanceRow) {
  const address = row.branch.normalizedAddress;
  return [address.line1, address.line2, address.city, address.state, address.postalCode, address.countryCode].filter(Boolean).join(", ") || "Address not available";
}

function formatCoordinates(row: V1AdminMerchantGovernanceRow) {
  return row.branch.latitude === undefined || row.branch.longitude === undefined
    ? "Coordinates unavailable"
    : `${row.branch.latitude.toFixed(5)}, ${row.branch.longitude.toFixed(5)}`;
}

function label(value: string) {
  return value.replaceAll("_", " ").toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function message(error: unknown) {
  return userFacingError(error, "Merchant governance is temporarily unavailable.");
}
