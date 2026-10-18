export type MerchantDetailTarget = { kind: "FULFILMENT" | "OPPORTUNITY" | "RESTAURANT_REQUEST" | "RECOVERY" | "RETURN"; id: string; branchId: string };
export type MerchantDetailLine = { id: string; name: string; quantity: number; variant?: string; packSize?: string; subtotal?: number; options: string[] };
export type MerchantDetailRecord = {
  id: string; kind: string; status: string; version: number; lines: MerchantDetailLine[]; productValue?: number;
  prep?: number; packages?: number; prepStarted?: string; expectedReady?: string; ready?: string;
  offered?: string; responded?: string; responseReason?: string;
  evidence: Array<{ id: string; at: string }>;
  problems: Array<{ id: string; reason: string; at: string }>;
  recovery: Array<{ id: string; status: string; reason: string; opened: string; resolved?: string }>;
  delivery: { rider?: string; assigned: boolean; stop?: string; collected?: string };
};
export type MerchantOrderDetail = {
  target: MerchantDetailTarget; branch: string; order: { id: string; number: string; status: string; type: string; created: string };
  records: MerchantDetailRecord[];
  recoveryOffers: Array<{ id: string; name: string; quantity: number; pack: string; status: string; offered: string }>;
  returns: Array<{ id: string; status: string; packages: number; arrived?: string; completed?: string }>;
  settlements: Array<{ id: string; type: string; status: string; calculation: string; amount?: number; currency: string }>;
};

const object = (v: unknown): Record<string, unknown> => { if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error("Invalid Merchant detail"); return v as Record<string, unknown>; };
const array = (v: unknown): unknown[] => { if (!Array.isArray(v)) throw new Error("Invalid Merchant detail collection"); return v; };
const text = (v: unknown): string => { if (typeof v !== "string" || !v.trim()) throw new Error("Invalid Merchant detail text"); return v; };
const optional = (v: unknown) => v == null || (typeof v === "string" && !v.trim()) ? undefined : text(v);
const integer = (v: unknown): number => { if (typeof v !== "number" || !Number.isSafeInteger(v)) throw new Error("Invalid Merchant detail number"); return v; };
const money = (v: unknown) => { if (v == null) return undefined; const amount = integer(v); if (amount < 0) throw new Error("Invalid product value"); return amount; };
const uuid = (v: unknown) => { const value = text(v).toLowerCase(); if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)) throw new Error("Invalid Merchant detail ID"); return value; };
const equal = (a: unknown, b: string) => uuid(a) === uuid(b);

/** Allowlist into a display-only model. Never retain raw codes/contact/location. */
export function parseMerchantOrderDetail(value: unknown, requested: MerchantDetailTarget): MerchantOrderDetail {
  const root = object(value), target = object(root.target), branch = object(root.branch), order = object(root.order);
  if (target.kind !== requested.kind || !equal(target.id, requested.id) || !equal(target.branchId, requested.branchId) || !equal(branch.id, requested.branchId)) throw new Error("Merchant detail scope changed");
  const orderId = uuid(order.id);
  const records = array(root.records).map((value): MerchantDetailRecord => {
    const r = object(value), kind = text(r.kind), delivery = object(r.delivery);
    if (!["FULFILMENT", "OPPORTUNITY", "RESTAURANT_REQUEST"].includes(kind) || integer(r.version) < 1) throw new Error("Invalid Merchant record");
    return { id: uuid(r.id), kind, status: text(r.status), version: integer(r.version), productValue: money(r.productSubtotalPaise),
      prep: r.promisedPrepMinutes == null ? undefined : integer(r.promisedPrepMinutes), packages: r.packageCount == null ? undefined : integer(r.packageCount),
      prepStarted: optional(r.prepStartedAt), expectedReady: optional(r.estimatedReadyAt), ready: optional(r.actualReadyAt),
      offered: optional(r.offeredAt), responded: optional(r.respondedAt), responseReason: optional(r.responseReason),
      lines: array(r.lines).map((line): MerchantDetailLine => {
        const l = object(line), quantity = integer(l.quantity);
        if (quantity < 1) throw new Error("Invalid item quantity");
        const selection = l.selection == null ? undefined : object(l.selection);
        return { id: uuid(l.orderLineId), name: text(l.name), quantity, variant: optional(l.variant), packSize: optional(l.packSize), subtotal: money(l.lineSubtotalPaise),
          options: selection ? array(selection.options).map((option) => { const o = object(option); return `${text(o.groupName)}: ${text(o.name)}`; }) : [] };
      }),
      evidence: array(r.evidence).map((v) => { const p = object(v); return { id: uuid(p.id), at: text(p.capturedAt) }; }),
      problems: array(r.problems).map((v) => { const p = object(v); return { id: uuid(p.id), reason: text(p.reason), at: text(p.reportedAt) }; }),
      recovery: array(r.recovery).map((v) => { const p = object(v); return { id: uuid(p.id), status: text(p.status), reason: text(p.reason), opened: text(p.openedAt), resolved: optional(p.resolvedAt) }; }),
      delivery: { rider: optional(delivery.riderName), assigned: delivery.riderAssigned === true, stop: optional(delivery.stopStatus), collected: optional(delivery.pickedUpAt) },
    };
  });
  if (new Set(records.map((r) => `${r.kind}:${r.id}`)).size !== records.length) throw new Error("Duplicate Merchant record");
  const recoveryOffers = array(root.recoveryOffers).map((value) => {
    const offer = object(value), sku = object(offer.sku);
    if (!equal(offer.orderId, orderId) || !equal(object(offer.branch).id, requested.branchId) || integer(offer.requestedQuantity) < 1) throw new Error("Invalid recovery scope");
    return { id: uuid(offer.id), name: text(sku.name), quantity: integer(offer.requestedQuantity), pack: text(sku.packSize), status: text(offer.status), offered: text(offer.startedAt) };
  });
  if (requested.kind === "RECOVERY" ? !recoveryOffers.some((r) => r.id === requested.id.toLowerCase())
    : requested.kind === "RETURN" ? !array(root.returns).some((value) => equal(object(value).returnStopId, requested.id))
    : !records.some((r) => r.kind === requested.kind && r.id === requested.id.toLowerCase())) throw new Error("Requested record missing");
  return { target: requested, branch: text(branch.displayName), order: { id: orderId, number: text(order.displayOrderNumber), status: text(order.status), type: text(order.orderType), created: text(order.createdAt) }, records, recoveryOffers,
    returns: array(root.returns).map((v) => {
      const r = object(v); if (!equal(r.orderId, orderId) || !equal(object(r.branch).id, requested.branchId) || r.receiptCode != null) throw new Error("Invalid return scope");
      return { id: uuid(r.returnStopId), status: text(r.status), packages: integer(r.packageCount), arrived: optional(r.arrivedAt), completed: optional(r.completedAt) };
    }),
    settlements: array(root.settlements).map((v) => {
      const s = object(v); if (!equal(s.orderId, orderId)) throw new Error("Invalid settlement scope");
      return { id: uuid(s.id), type: text(s.entryType), status: text(s.status), calculation: text(s.calculationStatus), amount: s.amountPaise == null ? undefined : integer(s.amountPaise), currency: text(s.currency) };
    }),
  };
}
