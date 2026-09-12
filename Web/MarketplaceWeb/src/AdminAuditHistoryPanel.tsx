import { useCallback, useEffect, useRef, useState, type Dispatch, type FormEvent, type SetStateAction } from "react";
import { CalendarClock, ChevronDown, FileClock, Search, ShieldCheck } from "lucide-react";
import {
  getV1AdminAuditHistory,
  type DastakV1Auth,
  type V1AdminAuditEvent,
} from "./dastakV1";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { useAdminRuntime } from "./AdminRuntimeContext";
import {
  adminFeedFailed,
  adminFeedHasContent,
  adminFeedStarted,
  adminFeedSucceeded,
  initialAdminFeedState,
} from "./adminRuntime";
import { RefreshQueue } from "./orderRealtime";
import { userFacingError } from "./userFacingError";

type Filters = {
  from: string;
  to: string;
  actor: string;
  action: string;
  resourceType: string;
  resourceId: string;
  orderId: string;
  branchId: string;
  accountId: string;
  eventId: string;
};

const emptyFilters: Filters = {
  from: "", to: "", actor: "", action: "", resourceType: "",
  resourceId: "", orderId: "", branchId: "", accountId: "", eventId: "",
};
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function AdminAuditHistoryPanel({ auth }: { auth: DastakV1Auth }) {
  const [draft, setDraft] = useState<Filters>(emptyFilters);
  const [filters, setFilters] = useState<Filters>(emptyFilters);
  const [events, setEvents] = useState<V1AdminAuditEvent[]>([]);
  const [cursor, setCursor] = useState<{ occurredAt: string; eventId: string }>();
  const [hasMore, setHasMore] = useState(false);
  const [feedState, setFeedState] = useState(initialAdminFeedState);
  const [loadingMore, setLoadingMore] = useState(false);
  const [filterError, setFilterError] = useState<string>();
  const requestGeneration = useRef(0);
  const controller = useRef<AbortController | undefined>(undefined);
  const refreshQueue = useRef(new RefreshQueue());
  const { reportRequestError } = useAdminRuntime();

  const load = useCallback(async (append: boolean, signal?: AbortSignal) => {
    const generation = ++requestGeneration.current;
    if (append) setLoadingMore(true);
    else setFeedState((current) => adminFeedStarted(current));
    try {
      const page = await getV1AdminAuditHistory({
        ...auth,
        fromOccurredAt: toIso(filters.from),
        toOccurredAt: toIso(filters.to),
        actorQuery: clean(filters.actor),
        action: clean(filters.action),
        resourceType: clean(filters.resourceType),
        resourceId: clean(filters.resourceId),
        orderId: clean(filters.orderId),
        branchId: clean(filters.branchId),
        accountId: clean(filters.accountId),
        eventId: clean(filters.eventId),
        limit: 50,
        cursor: append ? cursor : undefined,
        signal,
      });
      if (signal?.aborted || generation !== requestGeneration.current) return;
      setEvents((current) => append ? mergeEvents(current, page.events) : page.events);
      setCursor(page.nextCursor);
      setHasMore(page.hasMore);
      setFeedState((current) => adminFeedSucceeded(current));
    } catch (error) {
      if (signal?.aborted || generation !== requestGeneration.current) return;
      reportRequestError(error);
      setFeedState((current) => adminFeedFailed(current, error));
      throw error;
    } finally {
      if (generation === requestGeneration.current) setLoadingMore(false);
    }
  }, [auth, cursor, filters, reportRequestError]);

  useEffect(() => {
    controller.current?.abort();
    const next = new AbortController();
    controller.current = next;
    void load(false, next.signal).catch(() => undefined);
    return () => next.abort();
    // A cursor update must not restart the authoritative first page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth, filters]);

  const refresh = useCallback(() => refreshQueue.current.request(false, async () => {
    controller.current?.abort();
    const next = new AbortController();
    controller.current = next;
    await load(false, next.signal);
  }), [load]);
  useAdminWorkspaceRefresh("auditHistory", refresh);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const validation = validateFilters(draft);
    setFilterError(validation);
    if (!validation) setFilters({ ...draft });
  };
  const clearFilters = () => {
    setFilterError(undefined);
    setDraft(emptyFilters);
    setFilters(emptyFilters);
  };
  const loadMore = async () => {
    controller.current?.abort();
    const next = new AbortController();
    controller.current = next;
    await load(true, next.signal);
  };

  return <section className="admin-section admin-audit" role="tabpanel">
    <header className="admin-section-heading">
      <div><p className="eyebrow">GOVERNED HISTORY</p><h2>Audit History</h2><p>Reviewed, append-only operational events across current and legacy Dastak systems.</p></div>
    </header>

    <form className="admin-audit-filters" onSubmit={submit} noValidate>
      <label className="admin-search"><Search size={17} /><input value={draft.actor} onChange={(event) => setDraftField(setDraft, "actor", event.target.value)} placeholder="Actor name or account ID" aria-label="Filter audit history by actor" /></label>
      <label><span>Action</span><input value={draft.action} onChange={(event) => setDraftField(setDraft, "action", event.target.value)} placeholder="Exact action" /></label>
      <label><span>Resource type</span><input value={draft.resourceType} onChange={(event) => setDraftField(setDraft, "resourceType", event.target.value)} placeholder="Exact type" /></label>
      <button type="submit" className="primary-button">Apply filters</button>
      <details className="admin-audit-advanced">
        <summary>More filters <ChevronDown size={15} /></summary>
        <div>
          <label><span>From</span><input type="datetime-local" value={draft.from} onChange={(event) => setDraftField(setDraft, "from", event.target.value)} /></label>
          <label><span>To</span><input type="datetime-local" value={draft.to} onChange={(event) => setDraftField(setDraft, "to", event.target.value)} /></label>
          <AuditIdField label="Event ID" value={draft.eventId} placeholder="v1:123 or legacy:UUID" onChange={(value) => setDraftField(setDraft, "eventId", value)} />
          <AuditIdField label="Resource ID" value={draft.resourceId} onChange={(value) => setDraftField(setDraft, "resourceId", value)} />
          <AuditIdField label="Order ID" value={draft.orderId} onChange={(value) => setDraftField(setDraft, "orderId", value)} />
          <AuditIdField label="Branch ID" value={draft.branchId} onChange={(value) => setDraftField(setDraft, "branchId", value)} />
          <AuditIdField label="Account ID" value={draft.accountId} onChange={(value) => setDraftField(setDraft, "accountId", value)} />
          <button type="button" className="secondary-button" onClick={clearFilters}>Clear all</button>
        </div>
      </details>
    </form>

    {filterError ? <p className="order-error" role="alert">{filterError}</p> : null}
    {feedState.phase === "failed-with-content" || feedState.phase === "failed-without-content"
      ? <p className="order-error" role="alert">{userFacingError(feedState.error, "Audit History could not be loaded.")}</p> : null}
    {feedState.phase === "loading" ? <div className="admin-directory-loading" role="status"><span /><p>Loading reviewed audit events…</p></div>
      : events.length === 0 && adminFeedHasContent(feedState) ? <div className="admin-empty-state"><FileClock size={28} /><h3>No audit events match these filters</h3><p>Change the time range or use an exact resource identifier.</p></div>
      : events.length > 0 ? <div className="admin-audit-list" aria-label="Admin audit events">
        {events.map((auditEvent) => <AuditEvent key={auditEvent.eventId} event={auditEvent} />)}
        {hasMore ? <button type="button" className="admin-load-more" onClick={() => void loadMore().catch(() => undefined)} disabled={loadingMore}>{loadingMore ? "Loading…" : "Load older events"}</button> : null}
      </div> : null}
  </section>;
}

function AuditIdField({ label, value, onChange, placeholder = "UUID" }: { label: string; value: string; onChange: (value: string) => void; placeholder?: string }) {
  return <label><span>{label}</span><input value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} spellCheck={false} /></label>;
}

function AuditEvent({ event }: { event: V1AdminAuditEvent }) {
  const summary = Object.entries(event.summary);
  return <article className="admin-audit-event">
    <span className="admin-audit-icon" aria-hidden="true"><ShieldCheck size={19} /></span>
    <div className="admin-audit-main">
      <header><div><b>{humanize(event.action)}</b><span className={`admin-audit-source ${event.source.toLowerCase()}`}>{event.source === "V1" ? "Current" : "Legacy"}</span></div><time dateTime={event.occurredAt}><CalendarClock size={14} /> {formatDate(event.occurredAt)}</time></header>
      <p><strong>{event.actor.displayName}</strong>{event.actor.id ? <span> · {shortId(event.actor.id)}</span> : null}</p>
      <dl>
        <div><dt>Resource</dt><dd>{humanize(event.resource.type)}{event.resource.id ? ` · ${event.resource.id}` : ""}</dd></div>
        {event.reason ? <div><dt>Reason</dt><dd>{event.reason}</dd></div> : null}
        {summary.length ? <div><dt>Change</dt><dd>{summary.map(([key, value]) => <span key={key}><b>{humanize(key)}</b> {String(value)}</span>)}</dd></div> : null}
        <div><dt>Event</dt><dd>{event.eventId}</dd></div>
      </dl>
    </div>
  </article>;
}

function validateFilters(filters: Filters) {
  for (const [label, value] of [["Resource ID", filters.resourceId], ["Order ID", filters.orderId], ["Branch ID", filters.branchId], ["Account ID", filters.accountId]]) {
    if (value.trim() && !uuidPattern.test(value.trim())) return `${label} must be a complete UUID.`;
  }
  if (filters.eventId.trim() && !/^(legacy:[0-9a-f-]{36}|v1:\d+)$/i.test(filters.eventId.trim())) return "Event ID must begin with v1: or legacy: and contain the complete event identifier.";
  if (filters.from && filters.to && new Date(filters.from).getTime() > new Date(filters.to).getTime()) return "The start time must be before the end time.";
  return undefined;
}

function setDraftField(setter: Dispatch<SetStateAction<Filters>>, field: keyof Filters, value: string) {
  setter((current) => ({ ...current, [field]: value }));
}
function clean(value: string) { return value.trim() || undefined; }
function toIso(value: string) { return value ? new Date(value).toISOString() : undefined; }
function shortId(value: string) { return value.slice(0, 8).toUpperCase(); }
function humanize(value: string) { return value.replaceAll("_", " ").replaceAll(".", " ").replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase()); }
function formatDate(value: string) { return new Date(value).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" }); }
function mergeEvents(current: V1AdminAuditEvent[], next: V1AdminAuditEvent[]) {
  const seen = new Set(current.map((event) => event.eventId));
  return [...current, ...next.filter((event) => !seen.has(event.eventId))];
}
