type AuthenticatedInput = {
  supabaseUrl: string;
  publishableKey: string;
  accessToken: string;
};

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export type CheckoutSession = {
  orderId: string;
  entityType: "merchant_order" | "parcel";
  providerOrderId: string;
  keyId: string;
  amountPaise: number;
  currency: "INR";
  receipt: string;
};

export type CheckoutResult = "success" | "failed" | "dismissed";

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

export async function openRazorpayCheckout(
  session: CheckoutSession,
  customer: { name?: string; email?: string; phoneNumber?: string },
): Promise<CheckoutResult> {
  const Razorpay = await loadRazorpayCheckout();
  return await new Promise((resolve) => {
    let completed = false;
    const finish = (result: CheckoutResult) => {
      if (completed) return;
      completed = true;
      resolve(result);
    };
    const checkout = new Razorpay({
      key: session.keyId,
      amount: session.amountPaise,
      currency: session.currency,
      name: "Dastak",
      description: session.entityType === "parcel" ? "Parcel delivery" : "Merchant order",
      order_id: session.providerOrderId,
      prefill: {
        name: customer.name,
        email: customer.email,
        contact: customer.phoneNumber,
      },
      retry: { enabled: true },
      modal: { ondismiss: () => finish("dismissed") },
      handler: () => finish("success"),
      theme: { color: "#166534" },
    });
    checkout.on("payment.failed", () => finish("failed"));
    checkout.open();
  });
}

type RazorpayConstructor = new (options: Record<string, unknown>) => {
  open: () => void;
  on: (event: string, handler: () => void) => void;
};

async function loadRazorpayCheckout(): Promise<RazorpayConstructor> {
  const existing = razorpayConstructor();
  if (existing) return existing;

  const scriptId = "razorpay-checkout-script";
  const present = document.getElementById(scriptId) as HTMLScriptElement | null;
  await new Promise<void>((resolve, reject) => {
    const script = present ?? document.createElement("script");
    const loaded = () => {
      script.dataset.loaded = "true";
      resolve();
    };
    const failed = () => {
      script.remove();
      reject(new PaymentRequestError(
        "checkout_unavailable",
        "Razorpay checkout could not be loaded.",
        0,
      ));
    };
    if (present?.dataset.loaded === "true") {
      reject(new PaymentRequestError("checkout_unavailable", "Razorpay checkout is unavailable.", 0));
      return;
    }
    script.addEventListener("load", loaded, { once: true });
    script.addEventListener("error", failed, { once: true });
    if (!present) {
      script.id = scriptId;
      script.src = "https://checkout.razorpay.com/v1/checkout.js";
      script.async = true;
      document.head.appendChild(script);
    }
  });
  const loaded = razorpayConstructor();
  if (!loaded) throw new PaymentRequestError("checkout_unavailable", "Razorpay checkout is unavailable.", 0);
  return loaded;
}

function razorpayConstructor() {
  return (window as unknown as { Razorpay?: RazorpayConstructor }).Razorpay;
}

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
  return {
    orderId: requiredUUID(source?.orderId),
    entityType,
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
