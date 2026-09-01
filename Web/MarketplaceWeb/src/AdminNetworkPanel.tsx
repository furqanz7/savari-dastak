import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import {
  Bike,
  CheckCircle2,
  ChevronDown,
  CalendarDays,
  Clock3,
  IdCard,
  Mail,
  Phone,
  Search,
  ShieldCheck,
  ShoppingBag,
  Store,
  UsersRound,
} from "lucide-react";
import {
  getV1AdminNetworkPage,
  type DastakV1Auth,
  type V1AdminNetworkPerson,
  type V1AdminPersona,
  type V1AdminPersonaState,
} from "./dastakV1";
import { useAdminWorkspaceRefresh } from "./adminRefresh";
import { userFacingError } from "./userFacingError";

export function AdminNetworkPanel({ auth }: { auth: DastakV1Auth }) {
  const [query, setQuery] = useState("");
  const [persona, setPersona] = useState<V1AdminPersona>();
  const [state, setState] = useState<V1AdminPersonaState>();
  const [people, setPeople] = useState<V1AdminNetworkPerson[]>([]);
  const [cursor, setCursor] = useState<{ updatedAt: string; accountId: string }>();
  const [hasMore, setHasMore] = useState(false);
  const [selected, setSelected] = useState<string>();
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string>();

  const filters = useMemo(() => ({ query: query.trim(), persona, state }), [persona, query, state]);

  const load = useCallback(async (append: boolean, signal?: AbortSignal) => {
    if (append) setLoadingMore(true);
    else setLoading(true);
    try {
      const page = await getV1AdminNetworkPage({
        ...auth,
        ...filters,
        cursor: append ? cursor : undefined,
        limit: 40,
        signal,
      });
      setPeople((current) => append ? [...current, ...page.people] : page.people);
      setCursor(page.nextCursor);
      setHasMore(page.hasMore);
      if (!append) {
        setSelected((current) => current && page.people.some((person) => person.id === current)
          ? current : page.people[0]?.id);
      }
      setError(undefined);
    } catch (loadError) {
      if (loadError instanceof DOMException && loadError.name === "AbortError") return;
      setError(message(loadError));
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [auth, cursor, filters]);

  useEffect(() => {
    const controller = new AbortController();
    const timer = window.setTimeout(() => void load(false, controller.signal), 250);
    return () => { window.clearTimeout(timer); controller.abort(); };
    // Cursor and current people intentionally do not restart a filtered first page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth, filters]);

  const selectedPerson = people.find((person) => person.id === selected);
  const refreshWorkspace = useCallback(() => load(false), [load]);
  useAdminWorkspaceRefresh(refreshWorkspace);

  return <section className="admin-section admin-network" role="tabpanel">
    <header className="admin-section-heading">
      <div><p className="eyebrow">CONNECTED IDENTITIES</p><h2>Customer, Merchant & Delivery network</h2><p>One canonical identity with independently onboarded personas and live operating context.</p></div>
    </header>

    <div className="admin-network-toolbar">
      <label className="admin-search"><Search size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search name, email or phone" aria-label="Search network" /></label>
      <label><span>Persona</span><select value={persona ?? ""} onChange={(event) => setPersona(event.target.value ? event.target.value as V1AdminPersona : undefined)}><option value="">All personas</option><option value="CUSTOMER">Customers</option><option value="MERCHANT">Merchants</option><option value="DELIVERY">Delivery Partners</option><option value="ADMIN">Admins</option></select><ChevronDown size={15} /></label>
      <label><span>State</span><select value={state ?? ""} onChange={(event) => setState(event.target.value ? event.target.value as V1AdminPersonaState : undefined)}><option value="">Any state</option><option value="ACTIVE">Active</option><option value="DELETED">Deleted / recoverable</option></select><ChevronDown size={15} /></label>
    </div>

    {error ? <p className="order-error" role="alert">{error}</p> : null}
    {loading ? <div className="admin-directory-loading" role="status"><span /><p>Connecting identity and operating records…</p></div> : people.length === 0 ? <div className="admin-empty-state"><UsersRound size={28} /><h3>No identities match these filters</h3><p>Try another search or persona state.</p></div> : <div className="admin-network-layout">
      <div className="admin-people-list" aria-label="Dastak identities">
        {people.map((person) => <button type="button" key={person.id} className={person.id === selected ? "selected" : ""} onClick={() => setSelected(person.id)}>
          <span className="admin-person-mark" aria-hidden="true"><IdCard size={20} /></span>
          <span><strong>{person.displayName}</strong><small>{person.email ?? person.phoneNumber}</small><span className="admin-persona-row">{person.adminRole ? <b className="admin-persona admin"><ShieldCheck size={11} /> {roleLabel(person.adminRole)}</b> : null}{person.personas.map((entry) => <b key={entry.persona} className={`admin-persona ${entry.state.toLowerCase()}`}>{personaIcon(entry.persona)} {personaLabel(entry.persona)}</b>)}</span></span>
          <em>{person.accountState === "ACTIVE" ? "Active" : "Retired"}</em>
        </button>)}
        {hasMore ? <button type="button" className="admin-load-more" onClick={() => void load(true)} disabled={loadingMore}>{loadingMore ? "Loading…" : "Load more identities"}</button> : null}
      </div>
      <div className="admin-person-detail">{selectedPerson ? <PersonDetail person={selectedPerson} /> : null}</div>
    </div>}
  </section>;
}

function PersonDetail({ person }: { person: V1AdminNetworkPerson }) {
  return <article>
    <header><span className="admin-person-mark large" aria-hidden="true"><IdCard size={25} /></span><div><p className="eyebrow">IDENTITY RECORD</p><h3>{person.displayName}</h3><span>{person.accountState === "ACTIVE" ? <><CheckCircle2 size={14} /> Active canonical account</> : <><Clock3 size={14} /> Deleted identity · eligible for governed recovery</>}</span></div></header>
    <dl className="admin-contact-grid">
      <div><dt><Mail size={14} /> Email</dt><dd>{person.email ?? "No email available"}</dd></div>
      <div><dt><Phone size={14} /> Verified phone</dt><dd>{person.phoneNumber} {person.phoneVerified ? <CheckCircle2 size={13} /> : null}</dd></div>
      <div><dt><Clock3 size={14} /> Last sign-in</dt><dd>{person.lastSignInAt ? formatDate(person.lastSignInAt) : "Never recorded"}</dd></div>
      <div><dt><CalendarDays size={14} /> Joined</dt><dd>{formatDate(person.createdAt)}</dd></div>
    </dl>

    <section><h4>Persona lifecycle</h4><div className="admin-persona-detail-grid">
      <PersonaDetail icon={<ShoppingBag />} title="Customer" state={personaState(person, "CUSTOMER")} detail={`${person.customer.orderCount} orders · ${person.customer.activeOrderCount} active`} />
      <PersonaDetail icon={<Store />} title="Merchant" state={personaState(person, "MERCHANT")} detail={person.merchant ? `${label(person.merchant.applicationStatus)} · ${person.merchant.organizationName ?? person.merchant.businessName} · ${person.merchant.branchCount} branches` : "Onboarding not started"} />
      <PersonaDetail icon={<Bike />} title="Delivery Partner" state={personaState(person, "DELIVERY")} detail={person.delivery ? `${label(person.delivery.applicationStatus)} · ${label(person.delivery.deliveryMethod)} · ${person.delivery.activeMissionCount} active missions` : "Onboarding not started"} />
      {person.adminRole ? <PersonaDetail icon={<ShieldCheck />} title="Admin" state="ACTIVE" detail={`${roleLabel(person.adminRole)} · full operations access`} /> : null}
    </div></section>
    <footer>Identity {person.id.slice(0, 8).toUpperCase()} · Updated {formatDate(person.updatedAt)}</footer>
  </article>;
}

function PersonaDetail({ icon, title, state, detail }: { icon: ReactNode; title: string; state: string; detail: string }) {
  return <div><span>{icon}</span><div><strong>{title}</strong><p>{detail}</p></div><b className={state === "ACTIVE" ? "active" : state === "DELETED" ? "deleted" : "neutral"}>{label(state)}</b></div>;
}

function personaState(person: V1AdminNetworkPerson, persona: "CUSTOMER" | "MERCHANT" | "DELIVERY") {
  return person.personas.find((entry) => entry.persona === persona)?.state ?? "NOT ONBOARDED";
}
function label(value: string) { return value.replaceAll("_", " ").toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase()); }
function personaLabel(value: string) { return value === "DELIVERY" ? "Delivery" : label(value); }
function roleLabel(value: string) { return value === "SUPERADMIN" ? "Superadmin" : "Executive Admin"; }
function personaIcon(value: string) { return value === "MERCHANT" ? <Store size={11} /> : value === "DELIVERY" ? <Bike size={11} /> : <ShoppingBag size={11} />; }
function formatDate(value: string) { return new Date(value).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" }); }
function message(error: unknown) { return userFacingError(error, "The network directory could not be loaded."); }
