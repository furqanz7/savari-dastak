import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { ArrowLeft, Bike, CreditCard, MapPin, Package, Phone, RefreshCw, Send, ShieldCheck, X } from "lucide-react";
import { formatPrice } from "./catalogue";
import { LocationSearchField, type SelectedPlace } from "./LocationSearchField";
import {
  cancelParcel,
  createParcel,
  getCustomerParcels,
  quoteParcel,
  type ParcelDelivery,
  type ParcelDeliveryMethod,
  type ParcelQuote,
  type CustomerParcelDelivery,
} from "./parcels";
import { createParcelCheckoutSession, openRazorpayCheckout, processParcelRefund } from "./payments";
import { customerDataIssue, type CustomerDataIssue } from "./customerDataState";
import { CancellationSheet, CustomerRouteMap, CustomerTimeline } from "./CustomerDeliveryDetails";
import { parcelPaymentStateLabel, parcelPresentation } from "./customerLifecycle";
import { RefreshQueue } from "./orderRealtime";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  orderRefreshToken: number;
  selectedParcelId?: string;
  onOpenParcel: (parcelId: string) => void;
  onCloseParcel: () => void;
  onSignOut: () => void;
};

export function ParcelCustomerView({ accessToken, displayName, email, phoneNumber, supabaseUrl, publishableKey, orderRefreshToken, selectedParcelId, onOpenParcel, onCloseParcel, onSignOut }: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [parcels, setParcels] = useState<CustomerParcelDelivery[]>([]);
  const [pickup, setPickup] = useState<SelectedPlace>();
  const [dropoff, setDropoff] = useState<SelectedPlace>();
  const [deliveryMethod, setDeliveryMethod] = useState<ParcelDeliveryMethod>("bike");
  const [recipientName, setRecipientName] = useState("");
  const [recipientPhone, setRecipientPhone] = useState("+91");
  const [contents, setContents] = useState("");
  const [declaredValue, setDeclaredValue] = useState("");
  const [quote, setQuote] = useState<ParcelQuote>();
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [refreshIssue, setRefreshIssue] = useState<CustomerDataIssue>();
  const [cancellingParcel, setCancellingParcel] = useState<CustomerParcelDelivery>();
  const refreshQueue = useRef(new RefreshQueue());
  const creationRequest = useRef<{ quoteId: string; idempotencyKey: string } | undefined>(undefined);
  const hasActiveParcels = parcels.some((parcel) => !isFinal(parcel));

  const refresh = useCallback(async () => {
    await refreshQueue.current.request(false, async () => {
      try {
        setParcels(await getCustomerParcels(auth));
        setRefreshIssue(undefined);
      } catch (refreshError) {
        setRefreshIssue(customerDataIssue(refreshError));
      } finally {
        setLoading(false);
      }
    });
  }, [auth]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    if (orderRefreshToken > 0) void refresh();
  }, [orderRefreshToken, refresh]);
  useEffect(() => {
    if (!hasActiveParcels || refreshIssue?.kind === "session") return;
    const interval = window.setInterval(() => void refresh(), 30_000);
    const onVisible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    const onOnline = () => void refresh();
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", onOnline);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", onOnline);
    };
  }, [hasActiveParcels, refresh, refreshIssue?.kind]);

  const requestQuote = async (event: FormEvent) => {
    event.preventDefault();
    if (!pickup || !dropoff) return;
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    try {
      const nextQuote = await quoteParcel({
        ...auth,
        deliveryMethod,
        pickup,
        dropoff,
        idempotencyKey: crypto.randomUUID(),
      });
      creationRequest.current = { quoteId: nextQuote.quoteId, idempotencyKey: crypto.randomUUID() };
      setQuote(nextQuote);
    } catch (quoteError) {
      setError(message(quoteError));
    } finally {
      setBusy(false);
    }
  };

  const createAndPay = async () => {
    if (!quote) return;
    const declaredValuePaise = Math.round(Number(declaredValue) * 100);
    if (!recipientName.trim() || !/^\+[1-9][0-9]{7,14}$/.test(recipientPhone) || !contents.trim() || declaredValuePaise < 0) return;
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    try {
      const request = creationRequest.current?.quoteId === quote.quoteId
        ? creationRequest.current
        : { quoteId: quote.quoteId, idempotencyKey: crypto.randomUUID() };
      creationRequest.current = request;
      const parcel = await createParcel({
        ...auth,
        quoteId: request.quoteId,
        recipientName,
        recipientPhoneNumber: recipientPhone,
        declaredContents: contents,
        declaredValuePaise,
        idempotencyKey: request.idempotencyKey,
      });
      setParcels((current) => [{ ...parcel, audience: "sender" }, ...current.filter((item) => item.parcelId !== parcel.parcelId)]);
      await checkout(parcel);
      resetForm();
    } catch (creationError) {
      setError(message(creationError));
    } finally {
      setBusy(false);
    }
  };

  const checkout = async (parcel: ParcelDelivery) => {
    const session = await createParcelCheckoutSession({ ...auth, parcelId: parcel.parcelId, idempotencyKey: crypto.randomUUID() });
    const result = await openRazorpayCheckout(session, { name: displayName, email, phoneNumber });
    if (result === "dismissed") {
      setNotice("Payment was not completed. You can pay from the parcel card.");
      return;
    }
    if (result === "failed") {
      setNotice("Payment failed. The parcel will not be assigned until payment succeeds.");
      return;
    }
    setNotice("Payment received. Confirming securely...");
    for (let attempt = 0; attempt < 10; attempt += 1) {
      await delay(1_500);
      const latest = await getCustomerParcels(auth);
      setParcels(latest);
      if (latest.find((item) => item.parcelId === parcel.parcelId)?.paymentStatus !== "pending") {
        setNotice("Payment confirmed.");
        return;
      }
    }
    setNotice("Payment confirmation is taking longer than expected. This parcel will update automatically.");
  };

  const pay = async (parcel: ParcelDelivery) => {
    setBusy(true);
    setError(undefined);
    try { await checkout(parcel); }
    catch (paymentError) { setError(message(paymentError)); }
    finally { setBusy(false); }
  };

  const cancel = async (parcel: ParcelDelivery, reason: string) => {
    setBusy(true);
    setError(undefined);
    try {
      const updated = await cancelParcel({
        ...auth,
        parcelId: parcel.parcelId,
        reason,
        idempotencyKey: crypto.randomUUID(),
      });
      setParcels((current) => current.map((item) => item.parcelId === updated.parcelId ? { ...updated, audience: "sender" } : item));
      if (updated.paymentStatus === "refund_pending") {
        try {
          await processParcelRefund({ ...auth, parcelId: updated.parcelId, idempotencyKey: crypto.randomUUID() });
          setNotice("Refund initiated.");
        } catch {
          setNotice("Parcel cancelled. Your refund is queued and will update automatically.");
        }
        await refresh();
      }
      setCancellingParcel(undefined);
    } catch (cancelError) {
      setError(message(cancelError));
    } finally {
      setBusy(false);
    }
  };

  const resetForm = () => {
    setPickup(undefined);
    setDropoff(undefined);
    setRecipientName("");
    setRecipientPhone("+91");
    setContents("");
    setDeclaredValue("");
    setQuote(undefined);
    creationRequest.current = undefined;
  };

  const selectedParcel = selectedParcelId ? parcels.find((parcel) => parcel.parcelId === selectedParcelId) : undefined;

  return (
    <div className="parcel-customer-shell">
      {selectedParcel ? <ParcelDetail parcel={selectedParcel} busy={busy} onBack={onCloseParcel} onPay={pay} onCancel={setCancellingParcel} onRefresh={refresh} /> : <>
      <header className="catalogue-heading">
        <div><p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak customer"}</p><h1>Send a parcel</h1><p>Immediate pickup and delivery inside an active service area.</p></div>
        <button className="icon-button" type="button" onClick={() => void refresh()} disabled={busy} aria-label="Refresh parcels" title="Refresh parcels"><RefreshCw size={19} /></button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}
      {refreshIssue && <ParcelRefreshNotice issue={refreshIssue} retry={refresh} signOut={onSignOut} />}
      {notice && <p className="success-text" role="status">{notice}</p>}

      <section className="parcel-history" aria-label="Your parcel deliveries">
        <header><h2>Sent and received</h2><span>{parcels.length}</span></header>
        {loading ? <div className="catalogue-loading" role="status"><span /> Loading parcels</div> : parcels.length === 0 && refreshIssue ? <ParcelRecovery issue={refreshIssue} retry={refresh} signOut={onSignOut} /> : parcels.length === 0 ? <p className="merchant-orders-empty">No parcels yet.</p> : (
          <div className="parcel-list">{parcels.map((parcel) => <ParcelCard key={parcel.parcelId} parcel={parcel} busy={busy} onPay={pay} onCancel={setCancellingParcel} onOpen={onOpenParcel} />)}</div>
        )}
      </section>

      <form className="parcel-form" onSubmit={requestQuote}>
        <header><Package size={21} /><div><h2>Delivery details</h2><p>Pickup and drop-off must be in the same service area.</p></div></header>
        <div className="parcel-locations">
          <LocationSearchField label="Pickup" value={pickup} disabled={busy} onChange={(place) => { setPickup(place); setQuote(undefined); }} />
          <LocationSearchField label="Drop-off" value={dropoff} disabled={busy} onChange={(place) => { setDropoff(place); setQuote(undefined); }} />
        </div>
        <div className="editor-grid">
          <label>Recipient name<input value={recipientName} maxLength={80} onChange={(event) => setRecipientName(event.target.value)} required /></label>
          <label>Recipient Dastak phone<input type="tel" inputMode="tel" value={recipientPhone} onChange={(event) => setRecipientPhone(event.target.value)} required /></label>
          <label>Contents<input value={contents} maxLength={300} onChange={(event) => setContents(event.target.value)} required /></label>
          <label>Declared value (₹)<input type="number" inputMode="decimal" min="0" step="0.01" value={declaredValue} onChange={(event) => setDeclaredValue(event.target.value)} required /></label>
          <label>Delivery method<select value={deliveryMethod} onChange={(event) => { setDeliveryMethod(event.target.value as ParcelDeliveryMethod); setQuote(undefined); }}><option value="bike">Bike</option><option value="auto">Auto</option><option value="bicycle">Bicycle</option><option value="walking">Walking</option></select></label>
        </div>
        {!quote ? (
          <button className="primary-button parcel-submit" type="submit" disabled={busy || !pickup || !dropoff}><Send size={18} /> Check delivery price</button>
        ) : (
          <div className="parcel-quote">
            <div><small>Delivery fee</small><strong>{formatPrice(quote.deliveryFee.paise)}</strong></div>
            <div><small>Distance</small><strong>{formatDistance(quote.routeDistanceMeters)}</strong></div>
            <div><small>ETA</small><strong>{formatDuration(quote.routeDurationSeconds)}</strong></div>
            <button className="primary-button" type="button" disabled={busy || !recipientName.trim() || !contents.trim() || !/^\+[1-9][0-9]{7,14}$/.test(recipientPhone)} onClick={() => void createAndPay()}><CreditCard size={18} /> Create and pay</button>
          </div>
        )}
      </form>
      <small className="map-attribution">Location search data © OpenStreetMap contributors</small>
      </>}
      {cancellingParcel && <CancellationSheet title="Cancel this parcel delivery?" busy={busy} onDismiss={() => setCancellingParcel(undefined)} onConfirm={(reason) => cancel(cancellingParcel, reason)} />}
    </div>
  );
}

function ParcelRefreshNotice({ issue, retry, signOut }: { issue: CustomerDataIssue; retry: () => Promise<void>; signOut: () => void }) {
  return (
    <div className="customer-data-notice" role="status">
      <span><strong>{issue.title}</strong><small>{issue.message}</small></span>
      <button type="button" className="secondary-button compact-button" onClick={issue.action === "sign_in" ? signOut : () => void retry()}>
        {issue.action === "sign_in" ? "Sign in again" : "Try again"}
      </button>
    </div>
  );
}

function ParcelRecovery({ issue, retry, signOut }: { issue: CustomerDataIssue; retry: () => Promise<void>; signOut: () => void }) {
  return (
    <div className="parcel-recovery">
      <strong>{issue.title}</strong>
      <span>{issue.message}</span>
      <button type="button" className="secondary-button compact-button" onClick={issue.action === "sign_in" ? signOut : () => void retry()}>
        {issue.action === "sign_in" ? "Sign in again" : "Try again"}
      </button>
    </div>
  );
}

function ParcelCard({ parcel, busy, onPay, onCancel, onOpen }: {
  parcel: CustomerParcelDelivery;
  busy: boolean;
  onPay: (parcel: ParcelDelivery) => Promise<void>;
  onCancel: (parcel: CustomerParcelDelivery) => void;
  onOpen: (parcelId: string) => void;
}) {
  const presentation = parcelPresentation(parcel.status, parcel.paymentStatus, parcel.audience);
  return (
    <article className="parcel-card">
      <header><span><ShieldCheck size={20} /></span><div><strong>Parcel {parcel.parcelId.slice(-6).toUpperCase()}</strong><small>{parcel.audience === "recipient" ? "Incoming · " : "Sent · "}{presentation.title}</small></div><b>{formatPrice(parcel.deliveryFee.paise)}</b></header>
      <div className="parcel-route"><p><MapPin size={16} /><span><small>Pickup</small>{parcel.pickup.address}</span></p><p><MapPin size={16} /><span><small>Drop-off</small>{parcel.dropoff.address}</span></p></div>
      <div className="parcel-recipient"><Package size={17} /><span>{parcel.declaredContents}</span>{parcel.recipient.phoneNumber && <a href={`tel:${parcel.recipient.phoneNumber}`}><Phone size={16} /> {parcel.recipient.name}</a>}</div>
      {parcel.handoffCode && <div className="boarding-code"><small>{parcel.handoffCode.purpose === "pickup" ? "Pickup code" : "Delivery code"}</small><strong>{parcel.handoffCode.code}</strong></div>}
      <div className="parcel-actions">
        <button className="secondary-button" type="button" onClick={() => onOpen(parcel.parcelId)}>View details</button>
        {presentation.primaryAction === "pay" && <button className="primary-button" type="button" disabled={busy} onClick={() => void onPay(parcel)}><CreditCard size={17} /> Pay</button>}
        {presentation.primaryAction === "cancel" && <button className="danger-button" type="button" disabled={busy} onClick={() => onCancel(parcel)}><X size={17} /> Cancel</button>}
      </div>
    </article>
  );
}

function ParcelDetail({ parcel, busy, onBack, onPay, onCancel, onRefresh }: {
  parcel: CustomerParcelDelivery;
  busy: boolean;
  onBack: () => void;
  onPay: (parcel: ParcelDelivery) => Promise<void>;
  onCancel: (parcel: CustomerParcelDelivery) => void;
  onRefresh: () => Promise<void>;
}) {
  const presentation = parcelPresentation(parcel.status, parcel.paymentStatus, parcel.audience);
  const timeline = parcel.timeline;
  const points = [
    { label: "Pickup", ...parcel.pickup, kind: "pickup" as const },
    { label: "Drop-off", ...parcel.dropoff, kind: "dropoff" as const },
    ...(parcel.courier?.location ? [{ label: parcel.courier.displayName, address: "Delivery partner's latest location", ...parcel.courier.location, kind: "courier" as const }] : []),
  ];
  return (
    <article className="customer-delivery-detail">
      <header className="customer-detail-header"><button className="customer-back-button" type="button" onClick={onBack}><ArrowLeft size={18} /> Parcels</button><button className="icon-button" type="button" disabled={busy} onClick={() => void onRefresh()} aria-label="Refresh parcel" title="Refresh"><RefreshCw size={18} /></button></header>
      <section className="customer-status-hero"><p className="eyebrow">Parcel {parcel.parcelId.slice(-6).toUpperCase()}</p><h1>{presentation.title}</h1><p>{presentation.message}</p><span>{parcelPaymentStateLabel(parcel.paymentStatus)}</span></section>
      <CustomerRouteMap points={points} />
      {parcel.courier && <section className="customer-contact-card"><span className="order-icon"><Bike size={20} /></span><div><strong>{parcel.courier.displayName}</strong><small>Your delivery partner · {parcel.courier.deliveryMethod}</small></div><a href={`tel:${parcel.courier.phoneNumber}`} aria-label="Call delivery partner"><Phone size={18} /></a></section>}
      {parcel.handoffCode && <section className="customer-handoff"><small>Share at {parcel.handoffCode.purpose}</small><strong>{parcel.handoffCode.code}</strong><span>Verification code</span></section>}
      <section className="customer-receipt"><header><h2>Parcel details</h2><strong>{formatPrice(parcel.deliveryFee.paise)}</strong></header><div><span>Contents<small>{parcel.declaredContents}</small></span><strong>{formatPrice(parcel.declaredValue.paise)}</strong></div><div><span>Recipient<small>{parcel.recipient.name}</small></span>{parcel.recipient.phoneNumber && <a href={`tel:${parcel.recipient.phoneNumber}`}>{parcel.recipient.phoneNumber}</a>}</div></section>
      <CustomerTimeline items={[
        { label: "Parcel created", value: timeline?.createdAt ?? parcel.createdAt },
        { label: "Payment confirmed", value: timeline?.paymentCapturedAt },
        { label: "Partner assigned", value: timeline?.assignedAt },
        { label: "Heading to pickup", value: timeline?.enRouteToPickupAt },
        { label: "Picked up", value: timeline?.pickedUpAt },
        { label: "On the way", value: timeline?.inTransitAt },
        { label: "Delivered", value: timeline?.deliveredAt },
        { label: "Cancelled", value: timeline?.cancelledAt },
      ]} />
      <div className="customer-detail-actions">{presentation.primaryAction === "pay" && <button className="primary-button" type="button" disabled={busy} onClick={() => void onPay(parcel)}><CreditCard size={18} /> Pay {formatPrice(parcel.deliveryFee.paise)}</button>}{presentation.primaryAction === "cancel" && <button className="danger-button" type="button" disabled={busy} onClick={() => onCancel(parcel)}><X size={18} /> Cancel parcel</button>}</div>
    </article>
  );
}

function isFinal(parcel: ParcelDelivery) { return parcel.status === "delivered" || parcel.status === "cancelled"; }
function formatDistance(meters: number) { return meters < 1000 ? `${meters} m` : `${(meters / 1000).toFixed(1)} km`; }
function formatDuration(seconds: number) { const minutes = Math.max(1, Math.round(seconds / 60)); return `${minutes} min`; }
function delay(milliseconds: number) { return new Promise((resolve) => window.setTimeout(resolve, milliseconds)); }
function message(error: unknown) { return error instanceof Error ? error.message : "The parcel request could not be completed."; }
