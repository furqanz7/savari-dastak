import { useEffect, useRef, useState, type ReactNode } from "react";
import { ArrowRight, MapPin, ReceiptText } from "lucide-react";
import { ReimaginedAddressPicker } from "./ReimaginedAddressPicker";
import { formatV1Price } from "./dastakV1";
import { groceryOrderSubmission } from "./reimaginedCheckout";
import type { useReimaginedAddresses } from "./useReimaginedAddresses";

export function ReimaginedGroceryBilling({ items, retail, subtotal, addresses, recipient, online, canEdit, accountUrl, counter, addressManager, onEditRecipient }: {
  items: ReactNode; retail: Record<string, number>; subtotal?: number;
  addresses: ReturnType<typeof useReimaginedAddresses>; recipient: { name?: string; phoneNumber?: string };
  online: boolean; canEdit: boolean; accountUrl: string; counter: ReactNode; addressManager?: ReactNode; onEditRecipient?: () => void;
}) {
  const [step, setStep] = useState<"items" | "billing">("items");
  const container = useRef<HTMLElement>(null);
  const previousStep = useRef(step);
  const itemScroll = useRef(0);
  useEffect(() => {
    if (previousStep.current === step) return;
    previousStep.current = step;
    const content = container.current?.closest<HTMLElement>(".reimagined-panel-content");
    container.current?.querySelector<HTMLElement>(step === "billing" ? ".reimagined-billing-heading" : '.reimagined-billing-steps button')?.focus({ preventScroll: true });
    if (content) content.scrollTop = step === "billing" ? 0 : itemScroll.current;
  }, [step]);
  function changeStep(next: typeof step) {
    if (next === step) return;
    if (next === "billing") itemScroll.current = container.current?.closest<HTMLElement>(".reimagined-panel-content")?.scrollTop ?? 0;
    setStep(next);
  }
  const issues: string[] = [];
  if (!online) issues.push("Reconnect before checkout. Your Bucket is retained.");
  if (!canEdit) issues.push("This tab cannot edit or submit the Bucket.");
  if (subtotal === undefined) issues.push("Resolve every saved product before obtaining a complete total.");
  const selected = addresses.status === "ready" ? addresses.addresses.find(address => address.addressId === addresses.selected?.addressId) : undefined;
  if (!selected) issues.push("Choose a saved delivery address before checkout.");
  if (!recipient.name?.trim() || !recipient.phoneNumber?.trim()) issues.push("Complete your name and phone number in Account before checkout.");
  if (selected && recipient.name?.trim() && recipient.phoneNumber?.trim()) {
    try { groceryOrderSubmission({ retail, address: selected, recipient: { name: recipient.name, phoneNumber: recipient.phoneNumber } }); }
    catch (issue) { issues.push(issue instanceof Error ? issue.message : "Review your Grocery details before checkout."); }
  }
  return <section ref={container} className="reimagined-grocery-billing" aria-label="Grocery Cart and billing review">
    <div className="reimagined-billing-steps" role="group" aria-label="Grocery review steps">
      <button type="button" aria-pressed={step === "items"} onClick={() => changeStep("items")}><span>1</span>Items</button>
      <button type="button" aria-pressed={step === "billing"} onClick={() => changeStep("billing")}><span>2</span>Delivery & billing</button>
    </div>
    <div hidden={step !== "items"} inert={step !== "items"} className="reimagined-billing-step-content">
      {items}
      <button className="reimagined-billing-next" type="button" onClick={() => changeStep("billing")}>Review delivery & billing<ArrowRight size={18} aria-hidden="true" /></button>
    </div>
    <div hidden={step !== "billing"} inert={step !== "billing"} className="reimagined-billing-step-content">
      <header className="reimagined-billing-heading" tabIndex={-1}><MapPin size={20} aria-hidden="true" /><h2>Delivery & billing</h2></header>
      {addressManager ?? <ReimaginedAddressPicker resource={addresses} online={online} accountUrl={accountUrl} compact />}
      <section className="reimagined-billing-recipient" aria-label="Delivery recipient"><h3>Recipient</h3>
        <dl><div><dt>Name</dt><dd>{recipient.name?.trim() || "Not provided"}</dd></div><div><dt>Phone</dt><dd>{recipient.phoneNumber?.trim() || "Not provided"}</dd></div></dl>
        {onEditRecipient ? <button type="button" onClick={onEditRecipient}>Edit recipient in Profile</button> : <a href={accountUrl}>Edit recipient in Account</a>}
      </section>
      <section className="reimagined-billing-estimate" aria-label="Billing estimate"><h3><ReceiptText size={18} aria-hidden="true" />Price review</h3>
        <dl><div><dt>Estimated items</dt><dd>{subtotal === undefined ? "Unavailable" : formatV1Price(subtotal)}</dd></div><div><dt>Delivery, fees & taxes</dt><dd>Awaiting checkout</dd></div><div><dt>Final payable amount</dt><dd>Not confirmed</dd></div></dl>
        <p>The item estimate is not a final bill. Stock, delivery eligibility and the payable amount are confirmed by the server.</p>
      </section>
      {issues.length ? <section className="reimagined-billing-checks" aria-label="Grocery checkout checks"><h3>Before checkout</h3><ul>{issues.map(issue => <li key={issue}>{issue}</li>)}</ul></section> : <p className="reimagined-billing-checks" role="status">Your saved address, recipient and Bucket pass local checks. Delivery and stock are not yet confirmed.</p>}
      {counter}
    </div>
  </section>;
}
