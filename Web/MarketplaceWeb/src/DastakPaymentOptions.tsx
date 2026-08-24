import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, Check, CircleAlert, Clock3, LockKeyhole, QrCode, RefreshCw, ShieldCheck, Smartphone, X } from "lucide-react";
import type { DastakV1Auth } from "./dastakV1";
import { formatV1Price } from "./dastakV1";
import {
  completeV1CustomCheckout,
  discoverRazorpayMethods,
  isMobileWeb,
  launchRazorpayCustomUPI,
  reportV1CheckoutFailure,
  type CheckoutSession,
} from "./payments";

type PaymentState =
  | "loading"
  | "ready"
  | "launching"
  | "awaiting_return"
  | "processing"
  | "awaiting_provider"
  | "paid"
  | "cancelled"
  | "retryable"
  | "expired"
  | "reconciliation";

type Props = {
  auth: DastakV1Auth;
  session: CheckoutSession;
  customer: { name?: string; email?: string; phoneNumber?: string };
  expiresAt?: string;
  onDismiss: () => void;
  onProviderReturn: () => Promise<"paid" | "awaiting" | "expired">;
};

export function DastakPaymentOptions({ auth, session, customer, expiresAt, onDismiss, onProviderReturn }: Props) {
  const mobile = useMemo(() => isMobileWeb(), []);
  const [state, setState] = useState<PaymentState>("loading");
  const [upiAvailable, setUpiAvailable] = useState(false);
  const [selected, setSelected] = useState(true);
  const [error, setError] = useState<string>();

  const discover = useCallback(async () => {
    setState("loading");
    setError(undefined);
    try {
      const methods = await discoverRazorpayMethods(session.keyId);
      setUpiAvailable(methods.upi);
      if (!methods.upi) {
        setState("retryable");
        setError("UPI is not enabled for this payment. No unavailable method has been substituted.");
      } else {
        setState("ready");
      }
    } catch (discoveryError) {
      setState("retryable");
      setError(discoveryError instanceof Error ? discoveryError.message : "Payment methods could not be loaded.");
    }
  }, [session.keyId]);

  useEffect(() => { void discover(); }, [discover, session.providerOrderId]);

  useEffect(() => {
    if (!expiresAt) return;
    const remaining = Date.parse(expiresAt) - Date.now();
    if (remaining <= 0) {
      setState("expired");
      return;
    }
    const timer = window.setTimeout(() => setState("expired"), remaining);
    return () => window.clearTimeout(timer);
  }, [expiresAt]);

  const pay = async () => {
    if (!selected || !upiAvailable || state !== "ready") return;
    setError(undefined);
    setState("launching");
    const authorization = launchRazorpayCustomUPI(session, customer, mobile ? "intent" : "qr");
    setState("awaiting_return");
    const result = await authorization;
    if (result.status === "failed") {
      setState(result.message.toLowerCase().includes("cancel") ? "cancelled" : "retryable");
      setError(result.message);
      if (session.attemptId) {
        await reportV1CheckoutFailure({
          ...auth,
          orderId: session.orderId,
          paymentAttemptId: session.attemptId,
          failureCode: result.message.toLowerCase().includes("cancel") ? "CHECKOUT_DISMISSED" : "CHECKOUT_FAILED",
          idempotencyKey: crypto.randomUUID(),
        }).catch(() => undefined);
      }
      return;
    }

    if (!session.attemptId) {
      setState("reconciliation");
      setError("Payment returned without a Dastak attempt reference. Operations reconciliation is required.");
      return;
    }

    setState("processing");
    try {
      const completion = await completeV1CustomCheckout({
        ...auth,
        orderId: session.orderId,
        paymentAttemptId: session.attemptId,
        completion: result.completion,
        idempotencyKey: crypto.randomUUID(),
      });
      if (completion.state === "RECONCILIATION_REQUIRED") {
        setState("reconciliation");
        setError("Authorization returned after the reservation boundary. Dastak is reconciling or reversing it safely.");
        return;
      }
      if (completion.state === "PAID") {
        setState("paid");
        await onProviderReturn();
        return;
      }
      setState("awaiting_provider");
      const providerState = await onProviderReturn();
      setState(providerState === "paid" ? "paid" : providerState === "expired" ? "reconciliation" : "awaiting_provider");
      if (providerState === "awaiting") {
        setError("Authorization returned. Dastak is still waiting for Razorpay's captured-payment confirmation.");
      } else if (providerState === "expired") {
        setError("The reservation expired before capture confirmation. Dastak is reconciling or reversing the payment safely.");
      }
    } catch (completionError) {
      setState("reconciliation");
      setError(completionError instanceof Error
        ? completionError.message
        : "Dastak could not verify the payment return. Provider reconciliation is still running.");
    }
  };

  const dismiss = async () => {
    if (state === "launching" || state === "awaiting_return" || state === "processing") return;
    if ((state === "ready" || state === "cancelled" || state === "retryable") && session.attemptId) {
      await reportV1CheckoutFailure({
        ...auth,
        orderId: session.orderId,
        paymentAttemptId: session.attemptId,
        failureCode: "CHECKOUT_DISMISSED",
        idempotencyKey: crypto.randomUUID(),
      }).catch(() => undefined);
    }
    onDismiss();
  };

  const busy = ["loading", "launching", "awaiting_return", "processing"].includes(state);

  return <main className="v1-payment-options-page">
    <header className="v1-payment-options-header">
      <button type="button" onClick={() => void dismiss()} disabled={busy} aria-label="Back to order"><ArrowLeft size={22} /></button>
      <div><span>PAYMENT</span><h1>Payment options</h1></div>
      <button type="button" onClick={() => void dismiss()} disabled={busy} aria-label="Close payment options"><X size={21} /></button>
    </header>

    <section className="v1-payment-options-hero">
      <span>SECURED BASKET</span>
      <h2>Choose how to authorize</h2>
      <p>Dastak fixes the amount and Razorpay order. Your UPI PIN stays inside your UPI app.</p>
    </section>

    <PaymentStateCard state={state} mobile={mobile} error={error} />

    {state === "loading" ? <section className="v1-payment-method-loading" role="status">
      <span /><span /><span />
      <p>Loading provider-supported methods…</p>
    </section> : null}

    {upiAvailable ? <>
      <section className="v1-payment-options-section">
        <header><span>RECOMMENDED</span><small>AVAILABLE NOW</small></header>
        <button type="button" className={selected ? "v1-payment-option selected" : "v1-payment-option"} onClick={() => setSelected(true)} disabled={busy}>
          <span className="v1-payment-option-icon">{mobile ? <Smartphone size={24} /> : <QrCode size={24} />}</span>
          <span><strong>{mobile ? "Pay with a UPI app" : "UPI QR code"}</strong><small>{mobile ? "Choose an available UPI app during authorization" : "Scan with any supported UPI app"}</small></span>
          <span className="v1-payment-option-check"><Check size={17} /></span>
        </button>
      </section>
      <section className="v1-payment-options-section">
        <header><span>ALL PAYMENT OPTIONS</span><small>UPI FIRST</small></header>
        <div className="v1-payment-scope-note"><ShieldCheck size={21} /><span><strong>UPI</strong><small>{mobile ? "Other UPI apps remain available through the device authorization chooser." : "Desktop uses provider-supported dynamic QR; installed mobile apps are not falsely enumerated."}</small></span></div>
        <div className="v1-payment-scope-note muted"><LockKeyhole size={21} /><span><strong>Cards and other methods</strong><small>Not enabled in this release. Dastak does not collect card credentials.</small></span></div>
      </section>
    </> : null}

    {(state === "retryable" || state === "cancelled") ? <button className="secondary-button v1-payment-retry-action" type="button" onClick={() => void discover()}><RefreshCw size={17} /> Check payment methods again</button> : null}

    <footer className="v1-payment-options-footer">
      <span><small>TOTAL</small><strong>{formatV1Price(session.amountPaise)}</strong></span>
      <button className="primary-button" type="button" onClick={() => void pay()} disabled={!selected || !upiAvailable || state !== "ready"}>
        {state === "launching" ? "Opening…" : state === "awaiting_return" ? "Awaiting authorization…" : state === "processing" ? "Processing…" : "Continue"}
      </button>
    </footer>
  </main>;
}

function PaymentStateCard({ state, mobile, error }: { state: PaymentState; mobile: boolean; error?: string }) {
  if (state === "ready" && !error) return null;
  const presentation = statePresentation(state, mobile, error);
  const Icon = presentation.icon;
  return <section className={`v1-payment-state ${presentation.tone}`} role={presentation.tone === "danger" ? "alert" : "status"}>
    <Icon size={22} />
    <span><strong>{presentation.title}</strong><small>{presentation.detail}</small></span>
  </section>;
}

function statePresentation(state: PaymentState, mobile: boolean, error?: string) {
  switch (state) {
    case "loading": return { icon: RefreshCw, title: "Loading payment methods", detail: "Checking what Razorpay supports for this payment.", tone: "neutral" };
    case "launching": return { icon: Smartphone, title: mobile ? "Opening your UPI app" : "Creating secure QR", detail: "Only the selected authorization surface will open.", tone: "neutral" };
    case "awaiting_return": return { icon: Clock3, title: "Waiting for authorization", detail: mobile ? "Approve in your UPI app, then return to Dastak." : "Scan and approve the QR in your UPI app.", tone: "neutral" };
    case "processing": return { icon: ShieldCheck, title: "Verifying payment return", detail: "Dastak is checking the provider order and signature.", tone: "neutral" };
    case "awaiting_provider": return { icon: Clock3, title: "Awaiting provider confirmation", detail: error ?? "Authorization returned; payment.captured remains the paid authority.", tone: "warning" };
    case "paid": return { icon: Check, title: "Payment confirmed", detail: "Razorpay confirmed capture. Your order can now prepare.", tone: "success" };
    case "cancelled": return { icon: CircleAlert, title: "Payment cancelled", detail: error ?? "Your basket remains reserved and can be retried.", tone: "warning" };
    case "expired": return { icon: Clock3, title: "Payment reservation expired", detail: "Reserved items are being released safely.", tone: "danger" };
    case "reconciliation": return { icon: ShieldCheck, title: "Reconciliation required", detail: error ?? "Dastak is checking provider truth before changing the order.", tone: "warning" };
    case "retryable": return { icon: CircleAlert, title: "Payment needs attention", detail: error ?? "Try again while your basket remains reserved.", tone: "danger" };
    case "ready": return { icon: Check, title: "UPI ready", detail: "Choose Continue to authorize.", tone: "success" };
  }
}
