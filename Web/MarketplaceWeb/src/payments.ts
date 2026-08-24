type AuthenticatedInput = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
};

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export type CheckoutSession = {
  orderId: string;
  entityType: "merchant_order" | "parcel" | "dastak_v1_order";
  attemptId?: string;
  providerOrderId: string;
  keyId: string;
  amountPaise: number;
  currency: "INR";
  receipt: string;
};

export type CheckoutResult = "success" | "failed" | "dismissed";

export type RazorpayCustomCheckoutCompletion = {
  razorpay_payment_id: string;
  razorpay_order_id: string;
  razorpay_signature: string;
};

export type CustomCheckoutResult =
  | { status: "success"; completion: RazorpayCustomCheckoutCompletion }
  | { status: "failed"; message: string };

export type RazorpayMethodAvailability = {
  upi: boolean;
};

export type CustomUPIFlow = "intent" | "qr";

export class PaymentRequestError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
    this.name = "PaymentRequestError";
  }
}

export async function createCheckoutSession(
  input: AuthenticatedInput & { orderId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseCheckout(await call(input, {
    operation: "createCheckout",
    orderId: input.orderId,
  }, input.idempotencyKey, fetcher), "merchant_order");
}

export async function createParcelCheckoutSession(
  input: AuthenticatedInput & { parcelId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseCheckout(await call(input, {
    operation: "createCheckout",
    entityType: "parcel",
    parcelId: input.parcelId,
  }, input.idempotencyKey, fetcher), "parcel");
}

export async function createV1CheckoutSession(
  input: AuthenticatedInput & { orderId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  return parseCheckout(await call(input, {
    operation: "createCheckout",
    entityType: "dastak_v1_order",
    orderId: input.orderId,
  }, input.idempotencyKey, fetcher), "dastak_v1_order");
}

export async function reportV1CheckoutFailure(
  input: AuthenticatedInput & {
    orderId: string;
    paymentAttemptId: string;
    failureCode: "CHECKOUT_FAILED" | "CHECKOUT_DISMISSED";
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  return await call(input, {
    operation: "reportPaymentFailure",
    entityType: "dastak_v1_order",
    orderId: input.orderId,
    paymentAttemptId: input.paymentAttemptId,
    failureCode: input.failureCode,
  }, input.idempotencyKey, fetcher);
}

export async function completeV1CustomCheckout(
  input: AuthenticatedInput & {
    orderId: string;
    paymentAttemptId: string;
    completion: RazorpayCustomCheckoutCompletion;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
) {
  const payload = record(await call(input, {
    operation: "completeCustomCheckout",
    entityType: "dastak_v1_order",
    orderId: input.orderId,
    paymentAttemptId: input.paymentAttemptId,
    razorpay_order_id: input.completion.razorpay_order_id,
    razorpay_payment_id: input.completion.razorpay_payment_id,
    razorpay_signature: input.completion.razorpay_signature,
  }, input.idempotencyKey, fetcher));
  const state = payload?.state;
  if (state !== "PAID" && state !== "AWAITING_PROVIDER_CONFIRMATION" && state !== "RECONCILIATION_REQUIRED") invalid();
  return {
    orderId: requiredUUID(payload?.orderId),
    paymentAttemptId: requiredUUID(payload?.paymentAttemptId),
    providerPaymentId: requiredText(payload?.providerPaymentId, 200),
    state,
    duplicate: payload?.duplicate === true,
  };
}

export async function processOrderRefund(
  input: AuthenticatedInput & { orderId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  const payload = record(await call(input, {
    operation: "processRefund",
    orderId: input.orderId,
  }, input.idempotencyKey, fetcher));
  const orderId = requiredUUID(payload?.orderId);
  const refundState = payload?.refundState;
  if (refundState !== "pending" && refundState !== "processed") invalid();
  return { orderId, refundState };
}

export async function processParcelRefund(
  input: AuthenticatedInput & { parcelId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  const payload = record(await call(input, {
    operation: "processRefund",
    entityType: "parcel",
    parcelId: input.parcelId,
  }, input.idempotencyKey, fetcher));
  const parcelId = requiredUUID(payload?.entityId ?? payload?.orderId);
  const refundState = payload?.refundState;
  if (refundState !== "pending" && refundState !== "processed") invalid();
  return { parcelId, refundState };
}

export async function processV1Refund(
  input: AuthenticatedInput & { orderId: string; refundId: string; idempotencyKey: string },
  fetcher: Fetcher = fetch,
) {
  const payload = record(await call(input, {
    operation: "processRefund",
    entityType: "dastak_v1_order",
    orderId: input.orderId,
    refundId: input.refundId,
  }, input.idempotencyKey, fetcher));
  const refundId = requiredUUID(payload?.refundId ?? input.refundId);
  const refundState = payload?.refundState;
  if (refundState !== "pending" && refundState !== "processed") invalid();
  return { refundId, refundState };
}

export async function openRazorpayCheckout(
  session: CheckoutSession,
  customer: { name?: string; email?: string; phoneNumber?: string },
): Promise<CheckoutResult> {
  const methods = await discoverRazorpayMethods(session.keyId);
  if (!methods.upi) return "failed";
  const result = await launchRazorpayCustomUPI(session, customer, isMobileWeb() ? "intent" : "qr");
  return result.status;
}

type RazorpayCustomInstance = {
  once: (event: "ready", handler: (response: { methods?: Record<string, unknown> }) => void) => void;
  on: (event: "payment.success" | "payment.error", handler: (response: unknown) => void) => void;
  createPayment: (data: Record<string, unknown>) => void;
};

type RazorpayCustomConstructor = new (options: { key: string }) => RazorpayCustomInstance;

export async function discoverRazorpayMethods(keyId: string): Promise<RazorpayMethodAvailability> {
  const Razorpay = await loadRazorpayCustomCheckout();
  return await new Promise((resolve, reject) => {
    const razorpay = new Razorpay({ key: keyId });
    const timeout = window.setTimeout(() => reject(new PaymentRequestError(
      "method_discovery_timeout",
      "Available payment methods could not be loaded. Try again.",
      0,
    )), 8_000);
    razorpay.once("ready", (response) => {
      window.clearTimeout(timeout);
      resolve({ upi: response.methods?.upi === true || record(response.methods?.upi)?.enabled === true });
    });
  });
}

export async function launchRazorpayCustomUPI(
  session: CheckoutSession,
  customer: { name?: string; email?: string; phoneNumber?: string },
  flow: CustomUPIFlow,
): Promise<CustomCheckoutResult> {
  const Razorpay = await loadRazorpayCustomCheckout();
  return await new Promise((resolve) => {
    let completed = false;
    const finish = (value: CustomCheckoutResult) => {
      if (completed) return;
      completed = true;
      resolve(value);
    };
    const razorpay = new Razorpay({ key: session.keyId });
    razorpay.on("payment.success", (response) => {
      const completion = parseCustomCheckoutCompletion(response, session.providerOrderId);
      if (!completion) {
        finish({ status: "failed", message: "Payment returned without verifiable provider details. Dastak is reconciling it securely." });
        return;
      }
      finish({ status: "success", completion });
    });
    razorpay.on("payment.error", (response) => {
      const source = record(response);
      const error = record(source?.error);
      const reason = optionalText(error?.reason, 100)?.toLowerCase();
      const description = optionalText(error?.description, 300);
      finish({
        status: "failed",
        message: reason === "payment_cancelled" || reason === "user_cancelled"
          ? "Payment was cancelled. Your secured basket remains reserved."
          : description ?? "Payment could not be completed. Try again while your basket remains reserved.",
      });
    });
    try {
      razorpay.createPayment({
        amount: session.amountPaise,
        currency: session.currency,
        order_id: session.providerOrderId,
        email: customer.email,
        contact: customer.phoneNumber,
        method: "upi",
        "_[flow]": flow,
      });
    } catch {
      finish({ status: "failed", message: "The selected UPI authorization could not be opened." });
    }
  });
}

function parseCustomCheckoutCompletion(
  value: unknown,
  expectedOrderId: string,
): RazorpayCustomCheckoutCompletion | undefined {
  const source = record(value);
  const paymentId = optionalText(source?.razorpay_payment_id, 200);
  const orderId = optionalText(source?.razorpay_order_id, 200);
  const signature = optionalText(source?.razorpay_signature, 200);
  if (!paymentId || !orderId || !signature || orderId !== expectedOrderId) return undefined;
  return { razorpay_payment_id: paymentId, razorpay_order_id: orderId, razorpay_signature: signature };
}

async function loadRazorpayCustomCheckout(): Promise<RazorpayCustomConstructor> {
  const existing = razorpayCustomConstructor();
  if (existing) return existing;

  const scriptId = "razorpay-custom-checkout-script";
  const present = document.getElementById(scriptId) as HTMLScriptElement | null;
  await new Promise<void>((resolve, reject) => {
    const script = present ?? document.createElement("script");
    const loaded = () => {
      script.dataset.loaded = "true";
      resolve();
    };
    const failed = () => {
      script.remove();
      reject(new PaymentRequestError("checkout_unavailable", "Razorpay Custom Checkout could not be loaded.", 0));
    };
    if (present?.dataset.loaded === "true") {
      if (razorpayCustomConstructor()) resolve();
      else reject(new PaymentRequestError("checkout_unavailable", "Razorpay Custom Checkout is unavailable.", 0));
      return;
    }
    script.addEventListener("load", loaded, { once: true });
    script.addEventListener("error", failed, { once: true });
    if (!present) {
      script.id = scriptId;
      script.src = RAZORPAY_CUSTOM_CHECKOUT_SCRIPT;
      script.async = true;
      document.head.appendChild(script);
    }
  });
  const loaded = razorpayCustomConstructor();
  if (!loaded) throw new PaymentRequestError("checkout_unavailable", "Razorpay Custom Checkout is unavailable.", 0);
  return loaded;
}

function razorpayCustomConstructor() {
  return (window as unknown as { Razorpay?: RazorpayCustomConstructor }).Razorpay;
}

export function isMobileWeb(userAgent = navigator.userAgent) {
  return /android|iphone|ipad|ipod|mobile/i.test(userAgent);
}

export const RAZORPAY_CUSTOM_CHECKOUT_SCRIPT = "https://checkout.razorpay.com/v1/razorpay.js";

async function call(
  auth: AuthenticatedInput,
  body: unknown,
  idempotencyKey: string,
  fetcher: Fetcher,
) {
  let response: Response;
  try {
    response = await fetcher(`${auth.supabaseUrl.replace(/\/$/, "")}/functions/v1/dastak-payments`, {
      method: "POST",
      headers: {
        apikey: auth.publishableKey,
        authorization: `Bearer ${auth.accessToken}`,
        "content-type": "application/json",
        "X-Idempotency-Key": idempotencyKey,
      },
      body: JSON.stringify(body),
    });
  } catch {
    throw new PaymentRequestError("network_error", "Dastak could not reach the payment service.", 0);
  }
  const payload = await response.json().catch(() => undefined);
  if (!response.ok) {
    const error = record(record(payload)?.error);
    throw new PaymentRequestError(
      optionalText(error?.code, 80) ?? "payment_unavailable",
      optionalText(error?.message, 300) ?? "Payment is unavailable right now.",
      response.status,
    );
  }
  return payload;
}

function parseCheckout(value: unknown, entityType: CheckoutSession["entityType"]): CheckoutSession {
  const source = record(value);
  const keyId = requiredText(source?.keyId, 100);
  const providerOrderId = requiredText(source?.providerOrderId, 200);
  const receipt = requiredText(source?.receipt, 40);
  const amountPaise = source?.amountPaise;
  if (
    !/^rzp_(test|live)_[A-Za-z0-9]+$/.test(keyId) || !/^order_[A-Za-z0-9]+$/.test(providerOrderId) ||
    typeof amountPaise !== "number" || !Number.isSafeInteger(amountPaise) ||
    amountPaise <= 0 || amountPaise > 100_000_000 || source?.currency !== "INR"
  ) invalid();
  const attemptId = source?.attemptId === null || source?.attemptId === undefined
    ? undefined
    : requiredUUID(source.attemptId);
  if (entityType === "dastak_v1_order" && !attemptId) invalid();
  return {
    orderId: requiredUUID(source?.orderId),
    entityType,
    attemptId,
    providerOrderId,
    keyId,
    amountPaise,
    currency: "INR",
    receipt,
  };
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function optionalText(value: unknown, maximum: number) {
  return typeof value === "string" && value.length >= 1 && value.length <= maximum ? value : undefined;
}

function requiredText(value: unknown, maximum: number) {
  const result = optionalText(value, maximum);
  if (!result) invalid();
  return result;
}

function requiredUUID(value: unknown) {
  if (typeof value !== "string" || !uuidPattern.test(value)) invalid();
  return value.toLowerCase();
}

function invalid(): never {
  throw new PaymentRequestError("invalid_response", "Dastak received an invalid payment response.", 502);
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
