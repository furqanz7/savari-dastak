import { parseCustomerOrderSupportCase } from "./orders";
import type { CustomerOrderActions, CustomerOrderSupportCase, CustomerOrderSupportCategory } from "./orders";

export type ParcelDeliveryMethod = "walking" | "bicycle" | "bike" | "auto";
export type ParcelStatus = "payment_pending" | "paid" | "assigned" | "en_route_to_pickup" | "picked_up" | "in_transit" | "delivered" | "cancelled";
export type ParcelPoint = { latitude: number; longitude: number; address: string };
export type ParcelMoney = { currency: "INR"; paise: number };

export type ParcelQuote = {
  quoteId: string;
  deliveryMethod: ParcelDeliveryMethod;
  routeDistanceMeters: number;
  routeDurationSeconds: number;
  deliveryFee: ParcelMoney;
  courierPayout: ParcelMoney;
  expiresAt: string;
};

export type ParcelDelivery = {
  parcelId: string;
  status: ParcelStatus;
  paymentStatus: "pending" | "paid" | "failed" | "refund_pending" | "refunded" | "cancelled";
  refundStatus: "not_requested" | "pending" | "completed" | "not_eligible";
  deliveryMethod: ParcelDeliveryMethod;
  pickup: ParcelPoint;
  dropoff: ParcelPoint;
  recipient: { name: string; phoneNumber: string | null };
  declaredContents: string;
  declaredValue: ParcelMoney;
  deliveryFee: ParcelMoney;
  courierPayout: ParcelMoney;
  courier?: {
    displayName: string;
    phoneNumber: string;
    deliveryMethod: ParcelDeliveryMethod;
    location: { latitude: number; longitude: number } | null;
    lastSeenAt: string | null;
  };
  timeline?: {
    createdAt: string;
    paymentCapturedAt?: string;
    assignedAt?: string;
    enRouteToPickupAt?: string;
    pickedUpAt?: string;
    inTransitAt?: string;
    deliveredAt?: string;
    cancelledAt?: string;
  };
  stateVersion?: number;
  createdAt?: string;
  updatedAt?: string;
  handoffCode: { purpose: "pickup" | "delivery"; code: string; expiresAt: string } | null;
  customerActions?: CustomerOrderActions;
  supportCases?: CustomerOrderSupportCase[];
};

export type CustomerParcelDelivery = ParcelDelivery & {
  audience: "sender" | "recipient";
  customerActions?: CustomerOrderActions;
  supportCases?: CustomerOrderSupportCase[];
};

export type ParcelAssignment = {
  assignmentId: string;
  assignmentStatus: "offered" | "acknowledged";
  offeredAt: string;
  respondBy: string;
  acknowledgedAt: string | null;
  distanceMeters: number;
  parcel: ParcelDelivery;
};

export type ParcelPartnerSnapshot = { offer: ParcelAssignment | null; currentJob: ParcelAssignment | null };

type AuthenticatedInput = { supabaseUrl: string; publishableKey: string; accessToken: string };
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class ParcelRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "ParcelRequestError";
  }
}

export async function quoteParcel(
  input: AuthenticatedInput & { deliveryMethod: ParcelDeliveryMethod; pickup: ParcelPoint; dropoff: ParcelPoint; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseParcelQuote(await call(input, {
    operation: "quote",
    deliveryMethod: input.deliveryMethod,
    pickup: input.pickup,
    dropoff: input.dropoff,
  }, input.idempotencyKey, fetcher));
}

export async function createParcel(
  input: AuthenticatedInput & {
    quoteId: string;
    recipientName: string;
    recipientPhoneNumber: string;
    declaredContents: string;
    declaredValuePaise: number;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return parseParcel(await call(input, {
    operation: "createParcel",
    quoteId: input.quoteId,
    recipientName: input.recipientName,
    recipientPhoneNumber: input.recipientPhoneNumber,
    declaredContents: input.declaredContents,
    declaredValuePaise: input.declaredValuePaise,
  }, input.idempotencyKey, fetcher));
}

export async function getCustomerParcels(input: AuthenticatedInput, fetcher: Fetcher = fetch) {
  const payload = await call(input, { operation: "customerSnapshot" }, undefined, fetcher);
  if (!Array.isArray(payload)) invalid();
  return payload.map((value): CustomerParcelDelivery => {
    const source = record(value);
    if (!source || (source.audience !== "sender" && source.audience !== "recipient")) invalid();
    return { ...parseParcel(source), audience: source.audience };
  });
}

export async function getParcelSnapshot(
  input: AuthenticatedInput & { parcelId: string },
  fetcher: Fetcher = fetch,
) {
  return parseParcel(await call(input, { operation: "parcelSnapshot", parcelId: input.parcelId }, undefined, fetcher));
}

export async function getCustomerParcelDetail(
  input: AuthenticatedInput & { parcelId: string },
  fetcher: Fetcher = fetch,
) {
  const source = record(await call(input, { operation: "parcelSnapshot", parcelId: input.parcelId }, undefined, fetcher));
  if (!source || (source.audience !== "sender" && source.audience !== "recipient")) invalid();
  return { ...parseParcel(source), audience: source.audience } as CustomerParcelDelivery;
}

export async function createParcelSupport(
  input: AuthenticatedInput & { parcelId: string; category: CustomerOrderSupportCategory; message: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  const payload = record(await call(input, {
    operation: "customerSupport",
    parcelId: input.parcelId,
    category: input.category,
    message: input.message,
  }, input.idempotencyKey, fetcher));
  if (!payload) invalid();
  return parseCustomerOrderSupportCase(payload.supportCase);
}

export async function cancelParcel(
  input: AuthenticatedInput & { parcelId: string; reason: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseParcel(await call(input, {
    operation: "cancelParcel",
    parcelId: input.parcelId,
    reason: input.reason,
  }, input.idempotencyKey, fetcher));
}

export async function getParcelPartnerSnapshot(input: AuthenticatedInput, fetcher: Fetcher = fetch) {
  return parsePartnerSnapshot(await call(input, { operation: "partnerSnapshot" }, undefined, fetcher));
}

export async function mutateParcelAssignment(
  input: AuthenticatedInput & {
    operation: "acknowledgeAssignment" | "declineAssignment" | "startToPickup" | "confirmPickup" | "startDelivery" | "completeDelivery";
    assignmentId: string;
    reason?: string;
    verificationCode?: string;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return parsePartnerSnapshot(await call(input, {
    operation: input.operation,
    assignmentId: input.assignmentId,
    reason: input.reason,
    verificationCode: input.verificationCode,
  }, input.idempotencyKey, fetcher));
}

export function parcelStatusLabel(status: ParcelStatus) {
  return ({
    payment_pending: "Payment pending",
    paid: "Finding a delivery partner",
    assigned: "Partner assigned",
    en_route_to_pickup: "Partner heading to pickup",
    picked_up: "Parcel picked up",
    in_transit: "On the way",
    delivered: "Delivered",
    cancelled: "Cancelled",
  } as const)[status];
}

export function canCancelParcel(status: ParcelStatus) {
  return ["payment_pending", "paid", "assigned", "en_route_to_pickup"].includes(status);
}

function parseParcelQuote(value: unknown): ParcelQuote {
  const source = record(value);
  if (!source) invalid();
  return {
    quoteId: uuid(source.quoteId),
    deliveryMethod: method(source.deliveryMethod),
    routeDistanceMeters: positiveInteger(source.routeDistanceMeters),
    routeDurationSeconds: positiveInteger(source.routeDurationSeconds),
    deliveryFee: money(source.deliveryFee),
    courierPayout: money(source.courierPayout, true),
    expiresAt: dateText(source.expiresAt),
  };
}

export function parseParcel(value: unknown): ParcelDelivery {
  const source = record(value);
  const recipient = record(source?.recipient);
  const handoff = source?.handoffCode === null ? null : record(source?.handoffCode);
  const status = source?.status;
  const paymentStatus = source?.paymentStatus;
  const refundStatus = source?.refundStatus;
  if (!source || !recipient || typeof status !== "string" || typeof paymentStatus !== "string" ||
    typeof refundStatus !== "string" || !parcelStatuses.has(status) ||
    !paymentStatuses.has(paymentStatus) || !refundStatuses.has(refundStatus)) invalid();
  return {
    parcelId: uuid(source.parcelId),
    status: status as ParcelStatus,
    paymentStatus: paymentStatus as ParcelDelivery["paymentStatus"],
    refundStatus: refundStatus as ParcelDelivery["refundStatus"],
    deliveryMethod: method(source.deliveryMethod),
    pickup: point(source.pickup),
    dropoff: point(source.dropoff),
    recipient: {
      name: requiredText(recipient.name, 80),
      phoneNumber: recipient.phoneNumber === null ? null : phone(recipient.phoneNumber),
    },
    declaredContents: requiredText(source.declaredContents, 300),
    declaredValue: money(source.declaredValue, true),
    deliveryFee: money(source.deliveryFee),
    courierPayout: money(source.courierPayout, true),
    courier: courier(source.courier),
    timeline: timeline(source.timeline),
    stateVersion: optionalPositiveInteger(source.stateVersion),
    createdAt: optionalDateText(source.createdAt),
    updatedAt: optionalDateText(source.updatedAt),
    handoffCode: handoff ? {
      purpose: handoff.purpose === "pickup" || handoff.purpose === "delivery" ? handoff.purpose : invalid(),
      code: code(handoff.code),
      expiresAt: dateText(handoff.expiresAt),
    } : null,
    customerActions: customerActions(source.customerActions),
    supportCases: source.supportCases === null || source.supportCases === undefined
      ? undefined
      : Array.isArray(source.supportCases)
        ? source.supportCases.map(parseCustomerOrderSupportCase)
        : invalid(),
  };
}

function customerActions(value: unknown): CustomerOrderActions | undefined {
  const source = record(value);
  if (!source) return undefined;
  const cancellationMode = source.cancellationMode;
  if (!["cancel", "request_review", "pending_review", "none"].includes(String(cancellationMode))) invalid();
  const boolean = (key: string) => typeof source[key] === "boolean" ? source[key] as boolean : invalid();
  return {
    canPay: boolean("canPay"),
    cancellationMode: cancellationMode as CustomerOrderActions["cancellationMode"],
    canTrack: boolean("canTrack"),
    canContactStore: boolean("canContactStore"),
    canContactCourier: boolean("canContactCourier"),
    canRequestSupport: boolean("canRequestSupport"),
  };
}

function parsePartnerSnapshot(value: unknown): ParcelPartnerSnapshot {
  const source = record(value);
  if (!source) invalid();
  return {
    offer: source.offer === null ? null : assignment(source.offer),
    currentJob: source.currentJob === null ? null : assignment(source.currentJob),
  };
}

function assignment(value: unknown): ParcelAssignment {
  const source = record(value);
  if (!source || (source.assignmentStatus !== "offered" && source.assignmentStatus !== "acknowledged")) invalid();
  const distanceMeters = source.distanceMeters;
  if (typeof distanceMeters !== "number" || !Number.isFinite(distanceMeters) || distanceMeters < 0) invalid();
  return {
    assignmentId: uuid(source.assignmentId),
    assignmentStatus: source.assignmentStatus,
    offeredAt: dateText(source.offeredAt),
    respondBy: dateText(source.respondBy),
    acknowledgedAt: source.acknowledgedAt === null ? null : dateText(source.acknowledgedAt),
    distanceMeters,
    parcel: parseParcel(source.parcel),
  };
}

async function call(auth: AuthenticatedInput, body: unknown, idempotencyKey: string | undefined, fetcher: Fetcher) {
  let response: Response;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/parcel-deliveries`, {
      method: "POST",
      headers: {
        apikey: auth.publishableKey,
        authorization: `Bearer ${auth.accessToken}`,
        "content-type": "application/json",
        ...(idempotencyKey ? { "x-idempotency-key": idempotencyKey } : {}),
      },
      body: JSON.stringify(body),
    });
  } catch {
    throw new ParcelRequestError("network_error", "Dastak could not reach parcel delivery.", 0);
  }
  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    throw new ParcelRequestError(
      optionalText(error?.code, 80) ?? "parcel_unavailable",
      optionalText(error?.message, 300) ?? "Parcel delivery is unavailable right now.",
      response.status,
    );
  }
  return payload;
}

function point(value: unknown): ParcelPoint {
  const source = record(value);
  if (!source || typeof source.latitude !== "number" || typeof source.longitude !== "number" ||
    !Number.isFinite(source.latitude) || source.latitude < -90 || source.latitude > 90 ||
    !Number.isFinite(source.longitude) || source.longitude < -180 || source.longitude > 180) invalid();
  return { latitude: source.latitude, longitude: source.longitude, address: requiredText(source.address, 300) };
}

function geoPoint(value: unknown) {
  const source = record(value);
  if (!source || typeof source.latitude !== "number" || typeof source.longitude !== "number" ||
    !Number.isFinite(source.latitude) || source.latitude < -90 || source.latitude > 90 ||
    !Number.isFinite(source.longitude) || source.longitude < -180 || source.longitude > 180) invalid();
  return { latitude: source.latitude, longitude: source.longitude };
}

function courier(value: unknown): ParcelDelivery["courier"] {
  if (value === null || value === undefined) return undefined;
  const source = record(value);
  if (!source) invalid();
  return {
    displayName: requiredText(source.displayName, 100),
    phoneNumber: phone(source.phoneNumber),
    deliveryMethod: method(source.deliveryMethod),
    location: source.location === null || source.location === undefined ? null : geoPoint(source.location),
    lastSeenAt: source.lastSeenAt === null || source.lastSeenAt === undefined ? null : dateText(source.lastSeenAt),
  };
}

function timeline(value: unknown): ParcelDelivery["timeline"] {
  if (value === null || value === undefined) return undefined;
  const source = record(value);
  if (!source) invalid();
  return {
    createdAt: dateText(source.createdAt),
    paymentCapturedAt: optionalDateText(source.paymentCapturedAt),
    assignedAt: optionalDateText(source.assignedAt),
    enRouteToPickupAt: optionalDateText(source.enRouteToPickupAt),
    pickedUpAt: optionalDateText(source.pickedUpAt),
    inTransitAt: optionalDateText(source.inTransitAt),
    deliveredAt: optionalDateText(source.deliveredAt),
    cancelledAt: optionalDateText(source.cancelledAt),
  };
}

function money(value: unknown, allowZero = false): ParcelMoney {
  const source = record(value);
  const paise = source?.paise;
  if (!source || source.currency !== "INR" || typeof paise !== "number" || !Number.isSafeInteger(paise) || paise < (allowZero ? 0 : 1) || paise > 100_000_000) invalid();
  return { currency: "INR", paise };
}

function method(value: unknown): ParcelDeliveryMethod {
  if (value !== "walking" && value !== "bicycle" && value !== "bike" && value !== "auto") invalid();
  return value;
}

function positiveInteger(value: unknown) {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) invalid();
  return value;
}

function optionalPositiveInteger(value: unknown) {
  if (value === null || value === undefined) return undefined;
  return positiveInteger(value);
}

function dateText(value: unknown) {
  const result = requiredText(value, 50);
  if (Number.isNaN(Date.parse(result))) invalid();
  return result;
}

function optionalDateText(value: unknown) {
  return value === null || value === undefined ? undefined : dateText(value);
}

function phone(value: unknown) {
  const result = requiredText(value, 16);
  if (!/^\+[1-9][0-9]{7,14}$/.test(result)) invalid();
  return result;
}

function code(value: unknown) {
  const result = requiredText(value, 6);
  if (!/^[0-9]{6}$/.test(result)) invalid();
  return result;
}

function uuid(value: unknown) {
  if (typeof value !== "string" || !uuidPattern.test(value)) invalid();
  return value.toLowerCase();
}

function requiredText(value: unknown, maximum: number) {
  const result = optionalText(value, maximum);
  if (!result) invalid();
  return result;
}

function optionalText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length >= 1 && value.length <= maximum ? value : undefined;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}

function invalid(): never {
  throw new ParcelRequestError("invalid_response", "Dastak received an invalid parcel response.", 502);
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const parcelStatuses = new Set(["payment_pending", "paid", "assigned", "en_route_to_pickup", "picked_up", "in_transit", "delivered", "cancelled"]);
const paymentStatuses = new Set(["pending", "paid", "failed", "refund_pending", "refunded", "cancelled"]);
const refundStatuses = new Set(["not_requested", "pending", "completed", "not_eligible"]);
