import { submitV1Order, commitV1LaunchPayment, getV1Order, type DastakV1Auth, type V1Order, type V1OrderSubmission } from "./dastakV1";
import type { CustomerDeliveryAddress } from "./customerAddresses";
import type { PersistedCustomerCart } from "./customerCartPersistence";
import type { ReimaginedAction } from "./reimaginedState";
import { checkoutFingerprint, type CheckoutJournal } from "./reimaginedCheckoutJournal";

export type GroceryCheckoutDraft = {
  retail: Record<string, number>; address: CustomerDeliveryAddress;
  recipient: { name: string; phoneNumber: string };
};
export type CheckoutClients = { submit: typeof submitV1Order; commit: typeof commitV1LaunchPayment; read: typeof getV1Order };
const clients: CheckoutClients = { submit: submitV1Order, commit: commitV1LaunchPayment, read: getV1Order };
const committedStatuses = new Set(["PAID", "PREPARING", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY", "DELIVERED"]);

export function groceryOrderSubmission(draft: GroceryCheckoutDraft): V1OrderSubmission {
  const entries = Object.entries(draft.retail).sort(([left], [right]) => left.localeCompare(right));
  if (!entries.length || entries.some(([id, quantity]) => !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id) || !Number.isInteger(quantity) || quantity < 1 || quantity > 99)) throw new Error("Review the Grocery quantities before checkout.");
  if (!draft.recipient.name.trim() || !draft.recipient.phoneNumber.trim()) throw new Error("Complete your name and phone number in Account before checkout.");
  const address = draft.address;
  if (!address.address.trim() || !Number.isFinite(address.location.latitude) || Math.abs(address.location.latitude) > 90 || !Number.isFinite(address.location.longitude) || Math.abs(address.location.longitude) > 180) throw new Error("Choose a valid saved delivery address.");
  return {
    recipient: { name: draft.recipient.name.trim(), phoneNumber: draft.recipient.phoneNumber.trim() },
    deliveryAddress: { label: address.label, line1: address.address, line2: [address.building, address.floor].filter(Boolean).join(", ") || undefined, landmark: address.landmark, countryCode: "IN", latitude: address.location.latitude, longitude: address.location.longitude, instructions: address.deliveryNotes },
    lines: entries.map(([skuId, quantity]) => ({ lineType: "RETAIL_SKU", skuId, quantity })),
  };
}

export function canConfirmGroceryOrder(order: V1Order, now = Date.now()): boolean {
  const launch = order.launchPayment;
  const expiry = launch?.reservationExpiresAt;
  return order.status === "AWAITING_PAYMENT" && launch?.state === "READY_TO_CONFIRM" && launch.canCommit
    && launch.reservationState === "ACTIVE" && launch.noChargeNow && launch.payAtDoorstep
    && Boolean(expiry && Number.isFinite(Date.parse(expiry)) && Date.parse(expiry) > now);
}

function isCommitted(order: V1Order) {
  return committedStatuses.has(order.status) && order.launchPayment?.reservationState === "COMMITTED"
    && ["PAYMENT_DUE_AT_DELIVERY", "COLLECTION_RETRY_NEEDED", "PAYMENT_COLLECTED"].includes(order.launchPayment.state);
}

// One attempt freezes its request and keys. Never replace an ambiguous attempt with a new order.
// Journal stores request hashes and identifiers only, never auth/recipient/address text.
export class ReimaginedGroceryCheckout {
  private attempt?: { submission?: V1OrderSubmission; fingerprint?: string; purchased: PersistedCustomerCart; submitKey: string; commitKey: string; commitVersion?: number; orderId?: string; orderVersion?: number; order?: V1Order };
  private controller?: AbortController;
  private acknowledged = false;
  private epoch = 0;
  private recoveryError?: string;
  private operating = false;
  constructor(private readonly auth: DastakV1Auth, private readonly api: CheckoutClients = clients, private readonly uuid: () => string = () => crypto.randomUUID(), private readonly now = () => Date.now(), private readonly journal?: CheckoutJournal) {
    try {
      const saved = journal?.read();
      if (saved) this.attempt = { ...saved, purchased: { retail: saved.retail, food: [] } };
    } catch (error) { this.recoveryError = error instanceof Error ? error.message : "Checkout recovery is unavailable."; }
  }
  get order() { return this.attempt?.order; }
  get recoveryIssue() { return this.recoveryError; }
  get hasPendingAttempt() { return Boolean(this.attempt); }
  get recoverableOrderId() { return this.attempt?.orderId; }
  get committed() { return Boolean(this.order && isCommitted(this.order)); }
  get busy() { return this.operating || Boolean(this.controller); }
  private async exclusive<T>(operation: () => Promise<T>) {
    if (this.busy) throw new Error("A checkout request is already running.");
    const epoch = this.epoch;
    this.operating = true;
    try {
      const run = async () => {
        if (epoch !== this.epoch) throw new DOMException("Checkout session changed", "AbortError");
        if (this.recoveryError) throw new Error(this.recoveryError);
        if (this.journal) {
          const saved = this.journal.read();
          const previous = this.attempt;
          this.attempt = saved ? { ...saved, purchased: { retail: saved.retail, food: [] },
            order: previous?.submitKey === saved.submitKey && previous.orderVersion === saved.orderVersion ? previous.order : undefined } : undefined;
        }
        return operation();
      };
      return await (this.journal ? this.journal.exclusive(run) : run());
    } finally { this.operating = false; }
  }
  cancelRequests() { this.epoch += 1; this.controller?.abort(); }
  private persist(patch: Partial<NonNullable<typeof this.attempt>> = {}) {
    if (!this.journal) return;
    const attempt = { ...this.attempt!, ...patch };
    this.journal.write({ version: 1, fingerprint: attempt.fingerprint!, retail: attempt.purchased.retail, submitKey: attempt.submitKey, commitKey: attempt.commitKey, commitVersion: attempt.commitVersion, orderId: attempt.orderId, orderVersion: attempt.orderVersion });
  }
  private assertSnapshot(order: V1Order) {
    const requested = this.attempt!.purchased.retail;
    const returned = new Map<string, number>();
    for (const line of order.lines) {
      if (line.lineType !== "RETAIL_SKU" || !line.skuId || returned.has(line.skuId)) throw new Error("The server order does not match this Grocery Bucket. Open Orders to review it.");
      returned.set(line.skuId, line.quantity);
    }
    if (returned.size !== Object.keys(requested).length || Object.entries(requested).some(([id, quantity]) => returned.get(id) !== quantity)) throw new Error("The server order does not match this Grocery Bucket. Open Orders to review it.");
  }
  private async request(operation: (signal: AbortSignal) => Promise<V1Order>) {
    if (this.recoveryError) throw new Error(this.recoveryError);
    if (this.controller) throw new Error("A checkout request is already running.");
    const controller = new AbortController(); this.controller = controller;
    try {
      const order = await operation(controller.signal);
      if (controller.signal.aborted) throw new DOMException("Checkout session changed", "AbortError");
      this.assertSnapshot(order);
      if (this.attempt!.orderId && order.id !== this.attempt!.orderId) throw new Error("The server returned a different order. Open Orders to review it.");
      if (this.attempt!.orderVersion && order.version < this.attempt!.orderVersion) throw new Error("The server returned an older order version. Refresh its status.");
      this.persist({ orderId: order.id, orderVersion: order.version });
      this.attempt!.orderId = order.id; this.attempt!.orderVersion = order.version;
      this.attempt!.order = order;
      return order;
    } finally { if (this.controller === controller) this.controller = undefined; }
  }
  reserve(draft: GroceryCheckoutDraft) { return this.exclusive(() => this.reserveInside(draft)); }
  private async reserveInside(draft: GroceryCheckoutDraft) {
    if (this.recoveryError) throw new Error(this.recoveryError);
    if (this.attempt?.orderId && this.journal?.acknowledged(this.attempt.orderId)) {
      this.journal.clear(); this.attempt = undefined; this.acknowledged = false;
    }
    const submission = groceryOrderSubmission(draft);
    const epoch = this.epoch;
    const fingerprint = this.journal ? await checkoutFingerprint(submission) : undefined;
    if (epoch !== this.epoch) throw new DOMException("Checkout session changed", "AbortError");
    if (this.attempt && (this.journal ? fingerprint !== this.attempt.fingerprint : JSON.stringify(submission) !== JSON.stringify(this.attempt.submission))) throw new Error("A previous checkout attempt is unresolved. Review it in Orders before starting another.");
    if (!this.attempt) this.attempt = { submission, fingerprint, purchased: { retail: { ...draft.retail }, food: [] }, submitKey: this.uuid(), commitKey: this.uuid() };
    this.attempt.submission = submission;
    this.persist(); // Must succeed before any order write, including a retry.
    if (this.attempt.order) return this.attempt.order;
    if (this.attempt.orderId) return this.refreshInside();
    return this.request(signal => this.api.submit({ ...this.auth, signal, order: submission, idempotencyKey: this.attempt!.submitKey }));
  }
  refresh() { return this.exclusive(() => this.refreshInside()); }
  private async refreshInside() {
    if (!this.attempt?.orderId) throw new Error("There is no reserved order to refresh.");
    const orderId = this.attempt.orderId;
    return this.request(signal => this.api.read({ ...this.auth, signal, orderId }));
  }
  confirm(acknowledge?: (action: ReimaginedAction) => void): Promise<ReimaginedAction | undefined> {
    return this.exclusive(async () => {
      const action = await this.confirmInside();
      if (action) acknowledge?.(action); // Cart acknowledgement stays within the checkout lock.
      return action;
    });
  }
  private async confirmInside(): Promise<ReimaginedAction | undefined> {
    const order = this.order;
    if (!order) throw new Error(this.recoverableOrderId ? "The saved reservation changed or needs recovery. Refresh its server status before confirmation." : "Reserve your Grocery order first.");
    if (this.journal?.acknowledged(order.id) || (!this.journal && this.acknowledged)) return undefined;
    if (!isCommitted(order)) {
      if (!canConfirmGroceryOrder(order, this.now())) throw new Error("This order is not ready to confirm, or its reservation expired. Refresh its status.");
      this.attempt!.commitVersion ??= order.version;
      this.persist(); // Keep the original version/key pair across reloads and renewals.
      const committed = await this.request(signal => this.api.commit({ ...this.auth, signal, orderId: order.id, expectedVersion: this.attempt!.commitVersion!, idempotencyKey: this.attempt!.commitKey }));
      if (!isCommitted(committed)) throw new Error("The server has not confirmed this order. Your Bucket is retained. Refresh its status.");
    }
    if (!this.journal) this.acknowledged = true;
    return { type: "checkoutSucceeded", service: "grocery", orderId: order.id, purchased: { retail: { ...this.attempt!.purchased.retail }, food: [] } };
  }
  restartAfterTerminalReservation() {
    return this.exclusive(async () => {
      // A local timer, old quote or transient failure cannot prove an order is terminal.
      const order = await this.refreshInside();
      if (!["PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT"].includes(order.status)
        || order.launchPayment?.reservationState !== "EXPIRED"
        || order.launchPayment.state !== "RESERVATION_EXPIRED") throw new Error("The server has not closed this unpaid reservation. Your Bucket and checkout attempt are retained.");
      this.journal?.clear();
      this.attempt = undefined; this.acknowledged = false;
      // This only forgets a server-closed attempt. A new reservation requires a new explicit click.
    });
  }
}
