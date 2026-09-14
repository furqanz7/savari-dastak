import { useId, useRef, useState } from "react";
import { Check, ChefHat, Timer, X } from "lucide-react";
import type { V1RestaurantRequest } from "./dastakV1";
import { useModalDialog } from "./useModalDialog";

/** Same bounded promises offered by Merchant iOS. The server still validates acceptance. */
const restaurantPreparationMinutes = [10, 15, 20, 30, 45, 60, 90, 120, 180, 240];

export function MerchantPrepChoices({ options, value, onChange, disabled = false }: {
  options: number[]; value: number; onChange: (value: number) => void; disabled?: boolean;
}) {
  const name = useId();
  // Keep an existing server promise visible even when it is outside the usual suggestions.
  const choices = [...new Set([...options, value])].filter((minutes) => Number.isInteger(minutes) && minutes >= 1 && minutes <= 240).sort((a, b) => a - b);
  return <fieldset className="merchant-prep-options" disabled={disabled}>
    <legend><Timer size={16} aria-hidden="true" /> Preparation time <small>minutes</small></legend>
    <div>{choices.map((minutes) => <label key={minutes} className={value === minutes ? "selected" : ""}>
      <input type="radio" name={name} value={minutes} checked={value === minutes} onChange={() => onChange(minutes)} />
      <span>{minutes}<span className="sr-only"> minutes</span></span>
    </label>)}</div>
  </fieldset>;
}

export function MerchantDeclineDialog({ orderNumber, busy, reason, error, onReason, onDismiss, onConfirm }: {
  orderNumber: string; busy: boolean; reason: string; onReason: (reason: string) => void;
  error?: string;
  onDismiss: () => void; onConfirm: () => void;
}) {
  const titleId = useId();
  const descriptionId = useId();
  const reasonId = useId();
  const input = useRef<HTMLTextAreaElement>(null);
  const dialog = useModalDialog<HTMLFormElement>({ busy, onDismiss, initialFocus: input });
  return <div className="merchant-dialog-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget && !busy) onDismiss(); }}>
    <form ref={dialog} className="merchant-dialog" role="dialog" aria-modal="true" aria-labelledby={titleId} aria-describedby={descriptionId} aria-busy={busy} tabIndex={-1}
      onSubmit={(event) => { event.preventDefault(); if (!busy && reason.trim().length >= 3) onConfirm(); }}>
      <header><div><p className="eyebrow">{orderNumber}</p><h2 id={titleId}>Decline this request?</h2></div><button className="icon-button" type="button" aria-label="Close decline dialog" disabled={busy} onClick={onDismiss}><X size={20} /></button></header>
      <p id={descriptionId}>Tell us why your kitchen can’t prepare this order. The request will be declined when you confirm.</p>
      <label htmlFor={reasonId}>Reason for declining</label>
      <textarea ref={input} id={reasonId} value={reason} onChange={(event) => onReason(event.target.value)} minLength={3} maxLength={500} rows={3} required disabled={busy} placeholder="For example, an ingredient is unavailable" />
      <small>At least 3 characters. Please be specific.</small>
      {error ? <p className="merchant-dialog-error" role="alert">{error}</p> : null}
      <footer><button className="secondary-button" type="button" disabled={busy} onClick={onDismiss}>Keep request</button><button className="primary-button merchant-danger-action" type="submit" disabled={busy || reason.trim().length < 3}>{busy ? "Declining…" : "Decline request"}</button></footer>
    </form>
  </div>;
}

export function MerchantRestaurantRequestCard({ request, busy, prepMinutes, onPrepMinutes, onRespond }: {
  request: V1RestaurantRequest; busy: boolean; prepMinutes: number;
  onPrepMinutes: (minutes: number) => void;
  onRespond: (response: "CONFIRM" | "DECLINE", reason?: string) => Promise<boolean>;
}) {
  const [declining, setDeclining] = useState(false);
  const [reason, setReason] = useState("");
  const [checked, setChecked] = useState(false);
  const [declineError, setDeclineError] = useState<string>();
  const actionable = request.status === "OFFERED";
  return <article className="v1-opportunity-card merchant-food-request" aria-label={`Food request ${request.displayOrderNumber}`} aria-busy={busy}>
    <header><span className="v1-opportunity-icon"><ChefHat size={21} /></span><span><small className="merchant-card-eyebrow">New food order</small><strong>{request.displayOrderNumber}</strong><small>{request.branch.displayName}</small></span><b className="merchant-status-badge">New</b></header>
    <ul className="merchant-order-lines">{request.lines.map((line) => <li key={line.orderLineId}><b className="merchant-line-quantity">{line.quantity}×</b><span><strong>{line.name}</strong><small>{menuSelectionSummary(line.selection)}</small></span><em>{formatProductValue(line.lineSubtotalPaise ?? line.unitPricePaise * line.quantity)}</em></li>)}</ul>
    {request.productSubtotalPaise === undefined ? null : <p className="merchant-product-value"><span>Product value</span><strong>{formatProductValue(request.productSubtotalPaise)}</strong></p>}
    {request.softThresholdWarning ? <p className="v1-reservation-state merchant-kitchen-warning">Your kitchen has {request.activeOrderCount} active orders. Accept only if you can keep your preparation promise.</p> : null}
    <label className="v1-physical-check"><input type="checkbox" checked={checked} disabled={busy || !actionable} onChange={(event) => setChecked(event.target.checked)} /><span>I can prepare this exact selection.</span></label>
    <MerchantPrepChoices options={restaurantPreparationMinutes} value={prepMinutes} onChange={onPrepMinutes} disabled={busy || !actionable} />
    <div className="v1-opportunity-actions"><button className="secondary-button" type="button" disabled={busy || !actionable} onClick={() => setDeclining(true)}>Decline</button><button className="primary-button" type="button" disabled={busy || !actionable || !checked || !Number.isInteger(prepMinutes) || prepMinutes < 1 || prepMinutes > 240} onClick={() => void onRespond("CONFIRM")}><Check size={18} />{busy ? "Updating…" : "Accept order"}</button></div>
    <p className="merchant-card-footnote">Start preparing after the customer confirms. Payment is collected by the rider at delivery.</p>
    {declining ? <MerchantDeclineDialog orderNumber={request.displayOrderNumber} busy={busy} reason={reason} error={declineError} onReason={setReason} onDismiss={() => { setDeclining(false); setDeclineError(undefined); }} onConfirm={() => {
      setDeclineError(undefined);
      void onRespond("DECLINE", reason.trim()).then((success) => {
        if (success) setDeclining(false);
        else setDeclineError("This request could not be declined. Your reason is kept here. Close this dialog to check the latest order information, or try again.");
      });
    }} /> : null}
  </article>;
}

function menuSelectionSummary(selection: Record<string, unknown>) {
  if (!Array.isArray(selection.groups)) return "Exact menu selection";
  return selection.groups.flatMap((group: unknown) => {
    if (!group || typeof group !== "object" || !("options" in group) || !Array.isArray(group.options)) return [];
    return group.options.flatMap((option: unknown) => option && typeof option === "object" && "name" in option && typeof option.name === "string" ? [option.name] : []);
  }).join(" · ") || "Exact menu selection";
}

function formatProductValue(paise: number) {
  return new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(paise / 100);
}
