import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Bike, Check, MapPin, Navigation, PackageCheck, Power, RefreshCw, Store, UserRound, X } from "lucide-react";
import {
  acceptDeliveryOffer,
  advanceDeliveryJob,
  declineDeliveryOffer,
  getDeliveryDispatch,
  getDeliveryPartnerSnapshot,
  setDeliveryPartnerAvailability,
  type DeliveryAssignment,
  type DeliveryDispatchSnapshot,
  type DeliveryJobOperation,
  type DeliveryPartnerSnapshot,
} from "./delivery";
import { formatPrice } from "./catalogue";
import { formatDeliveryDistance, orderStatusLabel } from "./orders";
import {
  getParcelPartnerSnapshot,
  mutateParcelAssignment,
  parcelStatusLabel,
  type ParcelAssignment,
  type ParcelPartnerSnapshot,
} from "./parcels";
import { getEarnings, type EarningsSnapshot } from "./earnings";
import { RoleAccountView } from "./RoleAccountView";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  onSignOut: () => void;
};

type DispatchAction = "accept" | "decline" | DeliveryJobOperation;

export function DeliveryPartnerView({ accessToken, displayName, email, phoneNumber, supabaseUrl, publishableKey, onSignOut }: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [partner, setPartner] = useState<DeliveryPartnerSnapshot>();
  const [dispatch, setDispatch] = useState<DeliveryDispatchSnapshot>({ offer: null, currentJob: null });
  const [parcelDispatch, setParcelDispatch] = useState<ParcelPartnerSnapshot>({ offer: null, currentJob: null });
  const [earnings, setEarnings] = useState<EarningsSnapshot>();
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [verificationCode, setVerificationCode] = useState("");
  const [section, setSection] = useState<"deliveries" | "account">("deliveries");
  const refreshInFlight = useRef(false);
  const actionKeys = useRef(new Map<string, string>());

  const refresh = useCallback(async (showProgress = false) => {
    if (refreshInFlight.current) return;
    refreshInFlight.current = true;
    if (showProgress) setBusy("refresh");
    try {
      const [partnerSnapshot, dispatchSnapshot, parcelSnapshot, earningsSnapshot] = await Promise.all([
        getDeliveryPartnerSnapshot(auth),
        getDeliveryDispatch(auth),
        getParcelPartnerSnapshot(auth),
        getEarnings(auth, "deliveryPartnerSnapshot").catch(() => undefined),
      ]);
      setPartner(partnerSnapshot);
      setDispatch(dispatchSnapshot);
      setParcelDispatch(parcelSnapshot);
      setEarnings(earningsSnapshot);
      setError(undefined);
    } catch (refreshError) {
      setError(message(refreshError));
    } finally {
      refreshInFlight.current = false;
      setLoading(false);
      if (showProgress) setBusy(undefined);
    }
  }, [auth]);

  useEffect(() => {
    void refresh();
    const interval = window.setInterval(() => void refresh(), 5_000);
    return () => window.clearInterval(interval);
  }, [refresh]);

  const changeAvailability = async (online: boolean) => {
    setBusy("availability");
    setError(undefined);
    try {
      const location = online ? await currentLocation() : undefined;
      const availability = await setDeliveryPartnerAvailability({
        ...auth,
        online,
        location,
        idempotencyKey: crypto.randomUUID(),
      });
      setPartner((current) => current ? { ...current, availability } : current);
      if (online) {
        const [orderSnapshot, parcelSnapshot] = await Promise.all([
          getDeliveryDispatch(auth),
          getParcelPartnerSnapshot(auth),
        ]);
        setDispatch(orderSnapshot);
        setParcelDispatch(parcelSnapshot);
      }
    } catch (availabilityError) {
      setError(message(availabilityError));
    } finally {
      setBusy(undefined);
    }
  };

  const runParcelAction = async (
    assignment: ParcelAssignment,
    operation: "acknowledgeAssignment" | "declineAssignment" | "startToPickup" | "confirmPickup" | "startDelivery" | "completeDelivery",
    code?: string,
  ) => {
    const requestIdentity = `parcel:${operation}:${assignment.assignmentId}:${assignment.parcel.status}:${code ?? ""}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const snapshot = await mutateParcelAssignment({
        ...auth,
        operation,
        assignmentId: assignment.assignmentId,
        reason: operation === "declineAssignment" ? "Partner declined" : undefined,
        verificationCode: code,
        idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      setParcelDispatch(snapshot);
      setVerificationCode("");
    } catch (actionError) {
      setError(message(actionError));
    } finally {
      setBusy(undefined);
    }
  };

  const runDispatchAction = async (
    assignment: DeliveryAssignment,
    action: DispatchAction,
    code?: string,
  ) => {
    const requestIdentity = `${action}:${assignment.assignmentId}:${assignment.orderStatus}:${code ?? ""}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const snapshot = action === "accept"
        ? await acceptDeliveryOffer({ ...auth, assignmentId: assignment.assignmentId, idempotencyKey })
        : action === "decline"
          ? await declineDeliveryOffer({ ...auth, assignmentId: assignment.assignmentId, idempotencyKey })
          : await advanceDeliveryJob({
            ...auth,
            assignmentId: assignment.assignmentId,
            operation: action,
            verificationCode: code,
            idempotencyKey,
          });
      actionKeys.current.delete(requestIdentity);
      setDispatch(snapshot);
      setVerificationCode("");
    } catch (actionError) {
      setError(message(actionError));
    } finally {
      setBusy(undefined);
    }
  };

  const online = partner?.availability?.status === "online";
  const hasJob = Boolean(dispatch.currentJob || parcelDispatch.currentJob);

  return (
    <div className="delivery-shell">
      <nav className="workspace-tabs" role="tablist" aria-label="Delivery Partner workspace">
        <button type="button" role="tab" aria-selected={section === "deliveries"} className={section === "deliveries" ? "selected" : ""} onClick={() => setSection("deliveries")}><Bike size={18} /> Deliveries</button>
        <button type="button" role="tab" aria-selected={section === "account"} className={section === "account" ? "selected" : ""} onClick={() => setSection("account")}><UserRound size={18} /> Account</button>
      </nav>
      {section === "account" ? <RoleAccountView
        accessToken={accessToken}
        displayName={displayName}
        email={email}
        phoneNumber={phoneNumber}
        roleName="Delivery Partner"
        supabaseUrl={supabaseUrl}
        publishableKey={publishableKey}
        onSignOut={onSignOut}
      /> : <>
      <header className="delivery-heading">
        <div>
          <p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak Delivery Partner"}</p>
          <h1>Delivery</h1>
          <p>{partner?.deliveryMethod ? deliveryMethodLabel(partner.deliveryMethod) : "Delivery Partner"}</p>
        </div>
        <button className="icon-button" type="button" onClick={() => void refresh(true)} disabled={Boolean(busy)} aria-label="Refresh delivery queue" title="Refresh delivery queue">
          <RefreshCw size={19} />
        </button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}
      {loading ? <div className="catalogue-loading" role="status"><span /> Loading delivery queue</div> : (
        <>
          <section className="delivery-availability" aria-label="Availability">
            <span className={`availability-icon ${online ? "online" : ""}`}><Power size={21} /></span>
            <div>
              <strong>{online ? "Online" : "Offline"}</strong>
              <small>{online ? availabilityMessage(partner?.availability?.availableUntil) : "Not receiving assignments"}</small>
            </div>
            <label className="availability-switch" title={online && hasJob ? "Complete the active delivery first" : undefined}>
              <input
                type="checkbox"
                checked={online}
                disabled={Boolean(busy) || (online && hasJob)}
                onChange={(event) => void changeAvailability(event.currentTarget.checked)}
                aria-label="Available for deliveries"
              />
              <span aria-hidden="true" />
            </label>
          </section>
          {earnings && <section className="merchant-summary" aria-label="Earnings summary"><div><small>Completed</small><strong>{formatPrice(earnings.completedPaise)}</strong></div><div><small>This week</small><strong>{formatPrice(earnings.thisWeekPaise)}</strong></div><div><small>In progress</small><strong>{formatPrice(earnings.pendingPaise)}</strong></div></section>}

          {dispatch.currentJob && (
            <CurrentDelivery
              assignment={dispatch.currentJob}
              busy={Boolean(busy)}
              verificationCode={verificationCode}
              onVerificationCode={setVerificationCode}
              onAction={(action, code) => void runDispatchAction(dispatch.currentJob!, action, code)}
            />
          )}

          {parcelDispatch.currentJob && (
            <CurrentParcel
              assignment={parcelDispatch.currentJob}
              busy={Boolean(busy)}
              verificationCode={verificationCode}
              onVerificationCode={setVerificationCode}
              onAction={(operation, code) => void runParcelAction(parcelDispatch.currentJob!, operation, code)}
            />
          )}

          {dispatch.offer && (
            <DeliveryOffer
              offer={dispatch.offer}
              busy={Boolean(busy)}
              onAccept={() => void runDispatchAction(dispatch.offer!, "accept")}
              onDecline={() => void runDispatchAction(dispatch.offer!, "decline")}
            />
          )}

          {parcelDispatch.offer && (
            <ParcelOffer
              offer={parcelDispatch.offer}
              busy={Boolean(busy)}
              onAccept={() => void runParcelAction(parcelDispatch.offer!, "acknowledgeAssignment")}
              onDecline={() => void runParcelAction(parcelDispatch.offer!, "declineAssignment")}
            />
          )}

          {!dispatch.offer && !dispatch.currentJob && !parcelDispatch.offer && !parcelDispatch.currentJob && (
            <section className="delivery-empty">
              <Bike size={25} />
              <div><h2>{online ? "Waiting for assignments" : "Offline"}</h2><p>{online ? "No ready orders nearby." : "Go online when available."}</p></div>
            </section>
          )}
        </>
      )}
      </>}
    </div>
  );
}

function ParcelOffer({ offer, busy, onAccept, onDecline }: {
  offer: ParcelAssignment;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
}) {
  return (
    <section className="delivery-offer" aria-label="New parcel offer">
      <header><div><p className="eyebrow">Parcel offer</p><h2>{offer.parcel.declaredContents}</h2></div><OfferTimer respondBy={offer.respondBy} /></header>
      <p className="delivery-address"><MapPin size={18} /> {offer.parcel.pickup.address}</p>
      <p className="delivery-payout"><small>You earn</small><strong>{formatPrice(offer.parcel.courierPayout.paise)}</strong></p>
      <div className="delivery-route-facts">
        <span><Navigation size={17} /> {formatDeliveryDistance(Math.round(offer.distanceMeters))} to pickup</span>
        <MapLink location={offer.parcel.pickup} label="Open pickup route" />
      </div>
      <div className="delivery-offer-actions">
        <button className="danger-button" type="button" disabled={busy} onClick={onDecline}><X size={17} /> Decline</button>
        <button className="primary-button" type="button" disabled={busy} onClick={onAccept}><Check size={18} /> Accept</button>
      </div>
    </section>
  );
}

type ParcelOperation = "startToPickup" | "confirmPickup" | "startDelivery" | "completeDelivery";

function CurrentParcel({ assignment, busy, verificationCode, onVerificationCode, onAction }: {
  assignment: ParcelAssignment;
  busy: boolean;
  verificationCode: string;
  onVerificationCode: (code: string) => void;
  onAction: (operation: ParcelOperation, code?: string) => void;
}) {
  const action = parcelAction(assignment.parcel.status);
  const headingToRecipient = ["picked_up", "in_transit"].includes(assignment.parcel.status);
  const destination = headingToRecipient ? assignment.parcel.dropoff : assignment.parcel.pickup;
  return (
    <section className="current-delivery" aria-label="Active parcel delivery">
      <header><span className="section-icon"><PackageCheck size={22} /></span><div><p className="eyebrow">Active parcel</p><h2>{parcelStatusLabel(assignment.parcel.status)}</h2></div><p className="active-delivery-payout"><small>Earnings</small><strong>{formatPrice(assignment.parcel.courierPayout.paise)}</strong></p></header>
      <div className="delivery-stop"><span><Store size={19} /></span><div><small>Pickup</small><strong>{assignment.parcel.pickup.address}</strong></div></div>
      <div className="delivery-stop"><span><MapPin size={19} /></span><div><small>Drop-off</small><strong>{assignment.parcel.dropoff.address}</strong></div></div>
      <div className="parcel-job-facts"><p><small>Contents</small><strong>{assignment.parcel.declaredContents}</strong></p><p><small>Recipient</small><strong>{assignment.parcel.recipient.name}</strong></p></div>
      <MapLink location={destination} label={headingToRecipient ? "Open drop-off route" : "Open pickup route"} />
      {action?.needsCode && <label className="handoff-input">{assignment.parcel.status === "en_route_to_pickup" ? "Sender pickup code" : "Recipient delivery code"}<input inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={verificationCode} onChange={(event) => onVerificationCode(event.target.value.replace(/\D/g, "").slice(0, 6))} placeholder="000000" /></label>}
      {action && <button className="primary-button delivery-next-action" type="button" disabled={busy || (action.needsCode && verificationCode.length !== 6)} onClick={() => onAction(action.operation, action.needsCode ? verificationCode : undefined)}>{action.icon} {action.label}</button>}
    </section>
  );
}

function DeliveryOffer({ offer, busy, onAccept, onDecline }: {
  offer: DeliveryAssignment;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
}) {
  return (
    <section className="delivery-offer" aria-label="New delivery offer">
      <header><div><p className="eyebrow">New offer</p><h2>{offer.store.name}</h2></div><OfferTimer respondBy={offer.respondBy} /></header>
      <p className="delivery-address"><Store size={18} /> {offer.store.address}</p>
      <p className="delivery-payout"><small>You earn</small><strong>{formatPrice(offer.courierPayout.paise)}</strong></p>
      <DeliveryItems assignment={offer} />
      <div className="delivery-route-facts">
        <span><Navigation size={17} /> {formatDeliveryDistance(Math.round(offer.distanceMeters))} to store</span>
        <MapLink location={offer.store.pickup} label="Open pickup route" />
      </div>
      <div className="delivery-offer-actions">
        <button className="danger-button" type="button" disabled={busy} onClick={onDecline}><X size={17} /> Decline</button>
        <button className="primary-button" type="button" disabled={busy} onClick={onAccept}><Check size={18} /> Accept</button>
      </div>
    </section>
  );
}

function CurrentDelivery({ assignment, busy, verificationCode, onVerificationCode, onAction }: {
  assignment: DeliveryAssignment;
  busy: boolean;
  verificationCode: string;
  onVerificationCode: (code: string) => void;
  onAction: (operation: DeliveryJobOperation, code?: string) => void;
}) {
  const action = jobAction(assignment.orderStatus);
  const headingToCustomer = ["picked_up", "in_transit"].includes(assignment.orderStatus);
  const destination = headingToCustomer ? assignment.dropoff : assignment.store.pickup;
  return (
    <section className="current-delivery" aria-label="Active delivery">
      <header>
        <span className="section-icon"><PackageCheck size={22} /></span>
        <div><p className="eyebrow">Active delivery</p><h2>{orderStatusLabel(assignment.orderStatus)}</h2></div>
        <p className="active-delivery-payout"><small>Earnings</small><strong>{formatPrice(assignment.courierPayout.paise)}</strong></p>
      </header>
      <div className="delivery-stop">
        <span><Store size={19} /></span>
        <div><small>Pickup</small><strong>{assignment.store.name}</strong><p>{assignment.store.address}</p></div>
      </div>
      <div className="delivery-stop">
        <span><MapPin size={19} /></span>
        <div><small>Drop-off</small><strong>{coordinateLabel(assignment.dropoff)}</strong></div>
      </div>
      <DeliveryItems assignment={assignment} />
      <MapLink location={destination} label={headingToCustomer ? "Open drop-off route" : "Open pickup route"} />

      {assignment.orderStatus === "returning_to_merchant" && (
        <p className="delivery-return-note">Return the items to the merchant. The merchant will confirm receipt and close this delivery.</p>
      )}

      {action?.needsCode && (
        <label className="handoff-input">
          {assignment.orderStatus === "at_store" ? "Merchant pickup code" : "Customer delivery code"}
          <input
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={4}
            value={verificationCode}
            onChange={(event) => onVerificationCode(event.target.value.replace(/\D/g, "").slice(0, 4))}
            placeholder="0000"
          />
        </label>
      )}

      {action && (
        <button
          className="primary-button delivery-next-action"
          type="button"
          disabled={busy || (action.needsCode && verificationCode.length !== 4)}
          onClick={() => onAction(action.operation, action.needsCode ? verificationCode : undefined)}
        >
          {action.icon} {action.label}
        </button>
      )}
    </section>
  );
}

function DeliveryItems({ assignment }: { assignment: DeliveryAssignment }) {
  return (
    <ul className="delivery-items">
      {assignment.items.map((item) => <li key={item.productId}><b>{item.quantity}</b><span>{item.name}<small>{item.unitLabel}</small></span></li>)}
    </ul>
  );
}

function OfferTimer({ respondBy }: { respondBy: string }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const interval = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(interval);
  }, []);
  const seconds = Math.max(0, Math.ceil((Date.parse(respondBy) - now) / 1000));
  return <span className="offer-timer">{seconds}s</span>;
}

function MapLink({ location, label }: { location: { latitude: number; longitude: number }; label: string }) {
  return (
    <a className="map-link" href={`https://maps.apple.com/?daddr=${location.latitude},${location.longitude}&dirflg=d`} target="_blank" rel="noreferrer">
      <Navigation size={17} /> {label}
    </a>
  );
}

function jobAction(status: DeliveryAssignment["orderStatus"]): {
  operation: DeliveryJobOperation;
  label: string;
  needsCode: boolean;
  icon: ReactNode;
} | undefined {
  switch (status) {
    case "assigned": return { operation: "startToStore", label: "Start to store", needsCode: false, icon: <Navigation size={18} /> };
    case "en_route_to_pickup": return { operation: "arriveAtStore", label: "Arrived at store", needsCode: false, icon: <Store size={18} /> };
    case "at_store": return { operation: "confirmPickup", label: "Confirm pickup", needsCode: true, icon: <PackageCheck size={18} /> };
    case "picked_up": return { operation: "startDelivery", label: "Start delivery", needsCode: false, icon: <Navigation size={18} /> };
    case "in_transit": return { operation: "completeDelivery", label: "Complete delivery", needsCode: true, icon: <Check size={18} /> };
    default: return undefined;
  }
}

function parcelAction(status: ParcelAssignment["parcel"]["status"]): {
  operation: ParcelOperation;
  label: string;
  needsCode: boolean;
  icon: ReactNode;
} | undefined {
  switch (status) {
    case "assigned": return { operation: "startToPickup", label: "Start to pickup", needsCode: false, icon: <Navigation size={18} /> };
    case "en_route_to_pickup": return { operation: "confirmPickup", label: "Confirm pickup", needsCode: true, icon: <PackageCheck size={18} /> };
    case "picked_up": return { operation: "startDelivery", label: "Start delivery", needsCode: false, icon: <Navigation size={18} /> };
    case "in_transit": return { operation: "completeDelivery", label: "Complete delivery", needsCode: true, icon: <Check size={18} /> };
    default: return undefined;
  }
}

function currentLocation() {
  if (!navigator.geolocation) return Promise.reject(new Error("Location is unavailable in this browser."));
  return new Promise<{ latitude: number; longitude: number }>((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(
      (position) => resolve({ latitude: position.coords.latitude, longitude: position.coords.longitude }),
      () => reject(new Error("Allow location access to go online.")),
      { enableHighAccuracy: true, timeout: 12_000, maximumAge: 30_000 },
    );
  });
}

function coordinateLabel(location: { latitude: number; longitude: number }) {
  return `${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)}`;
}
function deliveryMethodLabel(method: string) {
  return method === "bike" ? "Bike" : method === "auto" ? "Auto" : `${method.charAt(0).toUpperCase()}${method.slice(1)}`;
}
function availabilityMessage(availableUntil?: string | null) {
  if (!availableUntil) return "Available for nearby orders";
  const time = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(new Date(availableUntil));
  return `Available until ${time} · Auto-offline after 15 minutes`;
}
function message(error: unknown) {
  return error instanceof Error ? error.message : "The delivery service is unavailable right now.";
}
