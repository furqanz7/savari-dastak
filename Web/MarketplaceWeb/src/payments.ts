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
type PaymentMethod = "upi" | "card" | "netbanking" | "wallet" | "paylater";

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
  const method = await selectPaymentMethod();
  if (!method) return "dismissed";
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
      description: session.entityType === "parcel"
        ? "Parcel delivery"
        : session.entityType === "dastak_v1_order"
        ? "Secured Dastak basket"
        : "Merchant order",
      order_id: session.providerOrderId,
      prefill: {
        name: customer.name,
        email: customer.email,
        contact: customer.phoneNumber,
      },
      retry: { enabled: true },
      method: {
        upi: method === "upi",
        card: method === "card",
        netbanking: method === "netbanking",
        wallet: method === "wallet",
        paylater: method === "paylater",
      },
      modal: { ondismiss: () => finish("dismissed") },
      handler: () => finish("success"),
      theme: { color: "#166534" },
    });
    checkout.on("payment.failed", () => finish("failed"));
    checkout.open();
  });
}

function selectPaymentMethod(): Promise<PaymentMethod | undefined> {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.className = "payment-method-overlay";
    overlay.innerHTML = `
      <div class="payment-method-sheet" role="dialog" aria-modal="true" aria-labelledby="payment-method-title">
        <div class="payment-method-header"><div><p class="eyebrow">Dastak</p><h2 id="payment-method-title">Select payment method</h2><p>Choose how you want to pay. Razorpay securely completes the payment.</p></div><button class="icon-button" data-dismiss aria-label="Close">×</button></div>
        <section><h3>UPI</h3>
          <button class="payment-method-row selected" data-method="upi"><span class="payment-method-icon">↗</span><span><strong>UPI ID</strong><small>Enter your UPI ID</small></span><span class="payment-check">✓</span></button>
          ${["Google Pay", "Paytm", "PhonePe", "CRED", "POP", "super.money", "Jupiter", "JioFinance", "slice"].map((name) => `<button class="payment-method-row" data-method="upi"><span class="payment-method-icon">↗</span><span><strong>${name}</strong><small>Pay with the app if installed</small></span><span class="payment-check"></span></button>`).join("")}
        </section>
        <section><h3>Other payment methods</h3>
          <button class="payment-method-row" data-method="card"><span class="payment-method-icon">▣</span><span><strong>Credit or debit card</strong><small>Add a card securely at checkout</small></span><span class="payment-check"></span></button>
          <button class="payment-method-row" data-method="netbanking"><span class="payment-method-icon">▤</span><span><strong>Net banking</strong><small>Select your bank</small></span><span class="payment-check"></span></button>
          <button class="payment-method-row" data-method="wallet"><span class="payment-method-icon">▱</span><span><strong>Wallets</strong><small>Available wallets</small></span><span class="payment-check"></span></button>
          <button class="payment-method-row" data-method="paylater"><span class="payment-method-icon">◷</span><span><strong>Pay later</strong><small>Where supported by your account</small></span><span class="payment-check"></span></button>
        </section>
        <button class="primary-button payment-method-continue">Continue securely</button>
      </div>`;
    document.body.append(overlay);
    let selected: PaymentMethod = "upi";
    const close = (value?: PaymentMethod) => { overlay.remove(); resolve(value); };
    overlay.querySelectorAll<HTMLButtonElement>("[data-method]").forEach((button) => button.addEventListener("click", () => {
      selected = button.dataset.method as PaymentMethod;
      overlay.querySelectorAll(".payment-method-row").forEach((row) => row.classList.remove("selected"));
      button.classList.add("selected");
    }));
    overlay.querySelector("[data-dismiss]")?.addEventListener("click", () => close());
    overlay.querySelector(".payment-method-continue")?.addEventListener("click", () => close(selected));
    overlay.addEventListener("click", (event) => { if (event.target === overlay) close(); });
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
