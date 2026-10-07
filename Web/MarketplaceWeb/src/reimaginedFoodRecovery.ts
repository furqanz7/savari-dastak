import type { DastakV1Auth, V1Order, V1OrderSubmission } from "./dastakV1";
import type { PersistedFoodCartLine } from "./customerCartPersistence";
import { foodCheckoutAcknowledged } from "./customerCartPersistence";
import { browserCheckoutLock, checkoutFingerprint, type CheckoutLock, type CheckoutStorage } from "./reimaginedCheckoutJournal";
import { canConfirmGroceryOrder, type CheckoutClients } from "./reimaginedCheckout";
import { prepareFoodCheckout } from "./reimaginedFoodCheckoutPreparation";
import type { ReimaginedAction } from "./reimaginedState";

type Record = { version: 1; fingerprint: string; food: PersistedFoodCartLine[]; submitKey: string; commitKey: string; orderId?: string; orderVersion?: number; commitVersion?: number };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const identity = (itemId: string, options: string[]) => JSON.stringify([itemId, [...options].sort()]);

export function foodRecoveryJournal(accountId: string, url: string, storage: CheckoutStorage, lock: CheckoutLock = browserCheckoutLock) {
  const key = `dastak:reimagined-food-checkout:v1:${encodeURIComponent(url.replace(/\/$/, ""))}:${encodeURIComponent(accountId)}`;
  return {
    exclusive<T>(operation: () => Promise<T>) { return lock(key, operation); },
    read(): Record | undefined {
      const value = JSON.parse(storage.getItem(key) ?? "null") as Record | null;
      if (value === null) return undefined;
      if (value.version !== 1 || !/^[0-9a-f]{64}$/.test(value.fingerprint) || !Array.isArray(value.food) || !value.food.length
        || value.food.some(line => !line || !uuid.test(line.branchId) || !uuid.test(line.itemId) || !Array.isArray(line.optionIds) || line.optionIds.some(id => !uuid.test(id)) || new Set(line.optionIds).size !== line.optionIds.length || !Number.isSafeInteger(line.quantity) || line.quantity < 1 || line.quantity > 99)
        || new Set(value.food.map(line => line.branchId)).size !== 1 || new Set(value.food.map(line => identity(line.itemId, line.optionIds))).size !== value.food.length
        || [value.submitKey, value.commitKey].some(id => typeof id !== "string" || !id.length || id.length > 200)
        || (value.orderId !== undefined && (!uuid.test(value.orderId) || !Number.isSafeInteger(value.orderVersion) || value.orderVersion! < 1))
        || (value.commitVersion !== undefined && (!Number.isSafeInteger(value.commitVersion) || value.commitVersion < 1))) throw new Error("Food checkout recovery data is invalid. Review Orders; no new request was sent.");
      return { version: 1, fingerprint: value.fingerprint, food: value.food.map(line => ({ branchId: line.branchId, itemId: line.itemId, optionIds: [...line.optionIds].sort(), quantity: line.quantity })), submitKey: value.submitKey, commitKey: value.commitKey, orderId: value.orderId, orderVersion: value.orderVersion, commitVersion: value.commitVersion };
    },
    write(record: Record) { storage.setItem(key, JSON.stringify(record)); },
    clear() { storage.setItem(key, "null"); },
    acknowledged(orderId: string) { return foodCheckoutAcknowledged(accountId, orderId, storage); },
  };
}
type Journal = ReturnType<typeof foodRecoveryJournal>;
const committed = (order: V1Order) => ["PAID", "PREPARING", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY", "DELIVERED"].includes(order.status) && order.launchPayment?.reservationState === "COMMITTED" && ["PAYMENT_DUE_AT_DELIVERY", "COLLECTION_RETRY_NEEDED", "PAYMENT_COLLECTED"].includes(order.launchPayment.state);

// Clients must be supplied explicitly; the customer root keeps writes disabled.
export class ReimaginedFoodRecovery {
  private attempt?: Record;
  private snapshot?: V1Order;
  private issue?: string;
  private controller?: AbortController;
  private operating = false;
  private epoch = 0;
  constructor(private readonly auth: DastakV1Auth, private readonly api: CheckoutClients, private readonly journal: Journal, private readonly newKey: () => string = () => crypto.randomUUID(), private readonly now = () => Date.now()) {
    try { this.attempt = journal.read(); } catch (error) { this.issue = String(error); }
  }
  get order() { return this.snapshot; }
  get busy() { return this.operating; }
  get committed() { return Boolean(this.snapshot && committed(this.snapshot)); }
  get recoveryIssue() { return this.issue; }
  get recoverableOrderId() { return this.attempt?.orderId; }
  get hasPendingAttempt() { return Boolean(this.attempt); }
  cancelRequests() { this.epoch++; this.controller?.abort(); }
  private async exclusive<T>(operation: () => Promise<T>) {
    if (this.operating) throw new Error("Food checkout is already running.");
    this.operating = true; const epoch = this.epoch;
    try { return await this.journal.exclusive(async () => {
      if (epoch !== this.epoch) throw new DOMException("Checkout session changed", "AbortError");
      if (this.issue) throw new Error(this.issue);
      const saved = this.journal.read();
      if (saved?.submitKey !== this.attempt?.submitKey || saved?.orderVersion !== this.attempt?.orderVersion) this.snapshot = undefined;
      this.attempt = saved;
      return operation();
    }); } finally { this.operating = false; }
  }
  private async request(operation: (signal: AbortSignal) => Promise<V1Order>) {
    const controller = new AbortController(); this.controller = controller;
    this.snapshot = undefined; // A failed/mismatched refresh cannot leave an old order confirmable.
    try {
      const order = await operation(controller.signal);
      if (controller.signal.aborted) throw new DOMException("Checkout session changed", "AbortError");
      const attempt = this.attempt!;
      const expected = new Map(attempt.food.map(line => [identity(line.itemId, line.optionIds), line.quantity]));
      const returned = new Map<string, number>();
      for (const line of order.lines) {
        const options = line.foodSelection?.options.map(option => option.id) ?? [];
        const key = identity(line.menuItemId ?? "", options);
        if (line.lineType !== "FOOD_MENU_ITEM" || !line.menuItemId || new Set(options).size !== options.length || returned.has(key)) throw new Error("Server Food selections do not match the saved cart.");
        returned.set(key, line.quantity);
      }
      if (order.orderType !== "FOOD_ONLY" || order.restaurant?.branchId !== attempt.food[0].branchId || returned.size !== expected.size || [...expected].some(([key, quantity]) => returned.get(key) !== quantity) || !uuid.test(order.id) || !Number.isSafeInteger(order.version) || order.version < 1 || (attempt.orderId && attempt.orderId !== order.id) || (attempt.orderVersion && order.version < attempt.orderVersion)) throw new Error("Server Food order does not match the saved reservation.");
      const next = { ...attempt, orderId: order.id, orderVersion: order.version };
      this.journal.write(next); this.attempt = next; this.snapshot = order;
      return order;
    } finally { if (this.controller === controller) this.controller = undefined; }
  }
  reserve(input: Parameters<typeof prepareFoodCheckout>[0]) { return this.exclusive(async () => {
    const preparation = prepareFoodCheckout(input);
    if (!preparation.submission) throw new Error(preparation.issues.join(" "));
    const submission: V1OrderSubmission = preparation.submission;
    const epoch = this.epoch; const fingerprint = await checkoutFingerprint(submission);
    if (epoch !== this.epoch) throw new DOMException("Checkout session changed", "AbortError");
    if (this.attempt?.orderId && this.journal.acknowledged(this.attempt.orderId)) {
      this.journal.clear(); this.attempt = undefined; this.snapshot = undefined;
    }
    if (this.attempt && this.attempt.fingerprint !== fingerprint) throw new Error("A previous Food attempt is unresolved. Restore its exact items, options, recipient and address or recover it in Orders.");
    if (!this.attempt) this.attempt = { version: 1, fingerprint, food: submission.lines.map(line => ({ branchId: submission.restaurantBranchId!, itemId: line.lineType === "FOOD_MENU_ITEM" ? line.menuItemId : "", optionIds: line.lineType === "FOOD_MENU_ITEM" ? [...line.optionIds] : [], quantity: line.quantity })), submitKey: this.newKey(), commitKey: this.newKey() };
    this.journal.write(this.attempt);
    if (this.attempt.orderId) return this.read();
    return this.request(signal => this.api.submit({ ...this.auth, order: submission, idempotencyKey: this.attempt!.submitKey, signal }));
  }); }
  private read() {
    if (!this.attempt?.orderId) throw new Error("Retry the original Food submission to recover an unknown reservation.");
    return this.request(signal => this.api.read({ ...this.auth, orderId: this.attempt!.orderId!, signal }));
  }
  refresh() { return this.exclusive(() => this.read()); }
  confirm(acknowledge: (action: ReimaginedAction) => void) { return this.exclusive(async () => {
    if (!this.snapshot) throw new Error("Refresh the saved Food reservation before confirmation.");
    if (this.journal.acknowledged(this.snapshot.id)) return;
    if (!committed(this.snapshot)) {
      if (!canConfirmGroceryOrder(this.snapshot, this.now())) throw new Error("Food reservation is not ready or has expired. Refresh its status.");
      this.attempt!.commitVersion ??= this.snapshot.version;
      this.journal.write(this.attempt!);
      const order = await this.request(signal => this.api.commit({ ...this.auth, orderId: this.attempt!.orderId!, expectedVersion: this.attempt!.commitVersion!, idempotencyKey: this.attempt!.commitKey, signal }));
      if (!committed(order)) throw new Error("Food commitment is not confirmed. The cart is retained.");
    }
    acknowledge({ type: "checkoutSucceeded", service: "food", orderId: this.snapshot!.id, purchased: { retail: {}, food: this.attempt!.food.map(line => ({ ...line, optionIds: [...line.optionIds] })) } });
    if (!this.journal.acknowledged(this.snapshot!.id)) throw new Error("Food commitment succeeded, but cart acknowledgement is unresolved. Recover before starting another order.");
  }); }
  restartAfterTerminalReservation() { return this.exclusive(async () => {
    const order = await this.read();
    if (!["PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT"].includes(order.status) || order.launchPayment?.reservationState !== "EXPIRED" || order.launchPayment.state !== "RESERVATION_EXPIRED") throw new Error("Server has not closed this unpaid Food reservation.");
    this.journal.clear(); this.attempt = undefined; this.snapshot = undefined;
  }); }
}
