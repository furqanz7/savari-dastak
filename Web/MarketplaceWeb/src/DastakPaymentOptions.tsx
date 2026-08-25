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
    const result = await launchRazorpayCustomUPI(
      session,
      customer,
      mobile ? "intent" : "qr",
      { onLaunched: () => setState("awaiting_return") },
    );
    if (result.status !== "success") {
      if (result.status === "not_launched") setState("ready");
      else setState(result.status === "cancelled" ? "cancelled" : "retryable");
      setError(result.message);
      if (session.attemptId && result.status !== "not_launched") {
        await reportV1CheckoutFailure({
          ...auth,
          orderId: session.orderId,
          paymentAttemptId: session.attemptId,
          failureCode: result.status === "cancelled" ? "CHECKOUT_DISMISSED" : "CHECKOUT_FAILED",
          idempotencyKey: crypto.randomUUID(),
        }).catch(() => undefined);
      }
      return;
    }

    if (!session.attemptId) {
      setState("reconciliation");
      setError("We're still checking your payment. No second charge will be attempted.");
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
        setError("This is taking longer than usual. We'll confirm or safely reverse the payment.");
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
        setError("We're waiting for payment confirmation. This usually takes a few seconds.");
      } else if (providerState === "expired") {
        setError("The reservation ended while confirmation was pending. We'll confirm or safely reverse the payment.");
      }
    } catch {
      setState("reconciliation");
      setError("We're still checking your payment. No second charge will be attempted.");
    }
  };

  const dismiss = async () => {
    if (state === "launching" || state === "processing") return;
    if ((state === "ready" || state === "awaiting_return" || state === "cancelled" || state === "retryable") && session.attemptId) {
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

  const busy = ["loading", "launching", "processing"].includes(state);

  return <main className="v1-payment-options-page">
    <header className="v1-payment-options-header">
      <button type="button" onClick={() => void dismiss()} disabled={busy} aria-label="Back to order"><ArrowLeft size={22} /></button>
      <div><span>PAYMENT</span><h1>Payment options</h1></div>
      <button type="button" onClick={() => void dismiss()} disabled={busy} aria-label="Close payment options"><X size={21} /></button>
    </header>

    <section className="v1-payment-options-hero">
      <span>SECURED BASKET</span>
      <h2>Choose how to authorize</h2>
      <p>Your total is fixed securely. Your UPI PIN stays inside your UPI app.</p>
    </section>

    <PaymentStateCard state={state} mobile={mobile} error={error} />

    {state === "loading" ? <section className="v1-payment-method-loading" role="status">
      <span /><span /><span />
      <p>Checking available payment methods…</p>
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
        <div className="v1-payment-scope-note"><ShieldCheck size={21} /><span><strong>UPI</strong><small>{mobile ? "Choose from the UPI apps available on this device." : "Scan the secure QR with a UPI app on your phone."}</small></span></div>
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
    case "loading": return { icon: RefreshCw, title: "Loading payment methods", detail: "Checking the payment options available right now.", tone: "neutral" };
    case "launching": return { icon: Smartphone, title: mobile ? "Opening your UPI app" : "Creating secure QR", detail: "Only the selected authorization surface will open.", tone: "neutral" };
    case "awaiting_return": return { icon: Clock3, title: "Waiting for authorization", detail: mobile ? "Approve in your UPI app, then return to Dastak." : "Scan and approve the QR in your UPI app.", tone: "neutral" };
    case "processing": return { icon: ShieldCheck, title: "Confirming your payment", detail: "We're securely checking the payment details.", tone: "neutral" };
    case "awaiting_provider": return { icon: Clock3, title: "Confirming your payment", detail: error ?? "We're waiting for payment confirmation. This usually takes a few seconds.", tone: "warning" };
    case "paid": return { icon: Check, title: "Payment confirmed", detail: "Your order is moving to preparation.", tone: "success" };
    case "cancelled": return { icon: CircleAlert, title: "Payment cancelled", detail: error ?? "Your basket remains reserved and can be retried.", tone: "warning" };
    case "expired": return { icon: Clock3, title: "Payment reservation expired", detail: "Reserved items are being released safely.", tone: "danger" };
    case "reconciliation": return { icon: ShieldCheck, title: "We're checking your payment", detail: error ?? "This is taking longer than usual. You can safely leave this screen.", tone: "warning" };
    case "retryable": return { icon: CircleAlert, title: "Payment needs attention", detail: error ?? "Try again while your basket remains reserved.", tone: "danger" };
    case "ready": return error
      ? { icon: CircleAlert, title: "UPI app didn't open", detail: error, tone: "warning" }
      : { icon: Check, title: "UPI ready", detail: "Choose Continue to authorize.", tone: "success" };
  }
}
