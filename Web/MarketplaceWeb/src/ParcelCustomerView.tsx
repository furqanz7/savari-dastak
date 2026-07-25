import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { CreditCard, MapPin, Package, Phone, RefreshCw, Send, ShieldCheck, X } from "lucide-react";
import { formatPrice } from "./catalogue";
import { LocationSearchField, type SelectedPlace } from "./LocationSearchField";
import {
  canCancelParcel,
  cancelParcel,
  createParcel,
  getCustomerParcels,
  parcelStatusLabel,
  quoteParcel,
  type ParcelDelivery,
  type ParcelDeliveryMethod,
  type ParcelQuote,
  type CustomerParcelDelivery,
} from "./parcels";
import { createParcelCheckoutSession, openRazorpayCheckout, processParcelRefund } from "./payments";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
};

export function ParcelCustomerView({ accessToken, displayName, email, phoneNumber, supabaseUrl, publishableKey }: Props) {
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

  const refresh = useCallback(async () => {
    try {
      setParcels(await getCustomerParcels(auth));
      setError(undefined);
    } catch (refreshError) {
      setError(message(refreshError));
    } finally {
      setLoading(false);
    }
  }, [auth]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    if (!parcels.some((parcel) => !isFinal(parcel))) return;
    const interval = window.setInterval(() => void refresh(), 5_000);
    return () => window.clearInterval(interval);
  }, [parcels, refresh]);

  const requestQuote = async (event: FormEvent) => {
    event.preventDefault();
    if (!pickup || !dropoff) return;
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    try {
      setQuote(await quoteParcel({
        ...auth,
        deliveryMethod,
        pickup,
        dropoff,
        idempotencyKey: crypto.randomUUID(),
      }));
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
      const parcel = await createParcel({
        ...auth,
        quoteId: quote.quoteId,
        recipientName,
        recipientPhoneNumber: recipientPhone,
        declaredContents: contents,
        declaredValuePaise,
        idempotencyKey: crypto.randomUUID(),
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

  const cancel = async (parcel: ParcelDelivery) => {
    if (!window.confirm("Cancel this parcel delivery?")) return;
    setBusy(true);
    setError(undefined);
    try {
      const updated = await cancelParcel({
        ...auth,
        parcelId: parcel.parcelId,
        reason: "Customer cancelled from web",
        idempotencyKey: crypto.randomUUID(),
      });
      setParcels((current) => current.map((item) => item.parcelId === updated.parcelId ? { ...updated, audience: "sender" } : item));
      if (updated.paymentStatus === "refund_pending") {
        await processParcelRefund({ ...auth, parcelId: updated.parcelId, idempotencyKey: crypto.randomUUID() });
        setNotice("Refund initiated.");
        await refresh();
      }
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
  };

  return (
    <div className="parcel-customer-shell">
      <header className="catalogue-heading">
        <div><p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak customer"}</p><h1>Send a parcel</h1><p>Immediate pickup and delivery inside an active service area.</p></div>
        <button className="icon-button" type="button" onClick={() => void refresh()} disabled={busy} aria-label="Refresh parcels" title="Refresh parcels"><RefreshCw size={19} /></button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}
      {notice && <p className="success-text" role="status">{notice}</p>}

      <section className="parcel-history" aria-label="Your parcel deliveries">
        <header><h2>Sent and received</h2><span>{parcels.length}</span></header>
        {loading ? <div className="catalogue-loading" role="status"><span /> Loading parcels</div> : parcels.length === 0 ? <p className="merchant-orders-empty">No parcels yet.</p> : (
          <div className="parcel-list">{parcels.map((parcel) => <ParcelCard key={parcel.parcelId} parcel={parcel} busy={busy} onPay={pay} onCancel={cancel} />)}</div>
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
    </div>
  );
}

function ParcelCard({ parcel, busy, onPay, onCancel }: {
  parcel: CustomerParcelDelivery;
  busy: boolean;
  onPay: (parcel: ParcelDelivery) => Promise<void>;
  onCancel: (parcel: ParcelDelivery) => Promise<void>;
}) {
  return (
    <article className="parcel-card">
      <header><span><ShieldCheck size={20} /></span><div><strong>Parcel {parcel.parcelId.slice(-6).toUpperCase()}</strong><small>{parcel.audience === "recipient" ? "Incoming · " : "Sent · "}{parcelStatusLabel(parcel.status)}</small></div><b>{formatPrice(parcel.deliveryFee.paise)}</b></header>
      <div className="parcel-route"><p><MapPin size={16} /><span><small>Pickup</small>{parcel.pickup.address}</span></p><p><MapPin size={16} /><span><small>Drop-off</small>{parcel.dropoff.address}</span></p></div>
      <div className="parcel-recipient"><Package size={17} /><span>{parcel.declaredContents}</span>{parcel.recipient.phoneNumber && <a href={`tel:${parcel.recipient.phoneNumber}`}><Phone size={16} /> {parcel.recipient.name}</a>}</div>
      {parcel.handoffCode && <div className="boarding-code"><small>{parcel.handoffCode.purpose === "pickup" ? "Pickup code" : "Delivery code"}</small><strong>{parcel.handoffCode.code}</strong></div>}
      <div className="parcel-actions">
        {parcel.audience === "sender" && parcel.status === "payment_pending" && <button className="primary-button" type="button" disabled={busy} onClick={() => void onPay(parcel)}><CreditCard size={17} /> Pay</button>}
        {parcel.audience === "sender" && canCancelParcel(parcel.status) && <button className="danger-button" type="button" disabled={busy} onClick={() => void onCancel(parcel)}><X size={17} /> Cancel</button>}
      </div>
    </article>
  );
}

function isFinal(parcel: ParcelDelivery) { return parcel.status === "delivered" || parcel.status === "cancelled"; }
function formatDistance(meters: number) { return meters < 1000 ? `${meters} m` : `${(meters / 1000).toFixed(1)} km`; }
function formatDuration(seconds: number) { const minutes = Math.max(1, Math.round(seconds / 60)); return `${minutes} min`; }
function delay(milliseconds: number) { return new Promise((resolve) => window.setTimeout(resolve, milliseconds)); }
function message(error: unknown) { return error instanceof Error ? error.message : "The parcel request could not be completed."; }
