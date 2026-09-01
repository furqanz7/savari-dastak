import { userFacingError } from "./userFacingError";

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
  providerMode: RazorpayPaymentMode;
  providerOrderId: string;
  keyId: string;
  amountPaise: number;
  currency: "INR";
  receipt: string;
  testRehearsalAvailable: boolean;
};

export type RazorpayPaymentMode = "TEST" | "LIVE";

export type RazorpayTestRehearsalOutcome = "SUCCESS" | "FAILURE";

export type RazorpayTestRehearsalDescriptor = {
  testRehearsal: true;
  outcome: RazorpayTestRehearsalOutcome;
  orderId: string;
  paymentAttemptId: string;
  providerMode: "TEST";
  providerOrderId: string;
  amountPaise: number;
  currency: "INR";
  testVpa: "success@razorpay" | "failure@razorpay";
};

export const RAZORPAY_TEST_UPI_LIMITATION_MESSAGE =
  "External UPI authorization is unavailable in this rehearsal build. Live payments remain disabled until Dastak explicitly returns to live mode.";

export type CheckoutResult = "success" | "failed" | "dismissed";

export type RazorpayCustomCheckoutCompletion = {
  razorpay_payment_id: string;
  razorpay_order_id: string;
  razorpay_signature: string;
};

export type CustomCheckoutResult =
  | { status: "success"; completion: RazorpayCustomCheckoutCompletion }
  | { status: "cancelled"; message: string }
  | { status: "failed"; message: string }
  | { status: "not_launched"; message: string };

export type CustomCheckoutLifecycle = {
  onLaunched?: () => void;
  onQrCode?: (qr: { uri: string; expiresAt?: number }) => void;
};

export type RazorpayMethodAvailability = {
  upi: boolean;
  upiApps: MobileUPIOption[];
};

export type RazorpayMobileUPIApp = "gpay" | "phonepe" | "paytm" | "any";

export type CustomUPITarget =
  | { kind: "intent"; app: RazorpayMobileUPIApp }
  | { kind: "qr" };

export type MobileUPIOption = {
  id: RazorpayMobileUPIApp;
  label: string;
};

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

export async function prepareV1TestRehearsal(
  input: AuthenticatedInput & {
    orderId: string;
    paymentAttemptId: string;
    outcome: RazorpayTestRehearsalOutcome;
    idempotencyKey: string;
  },
  fetcher: Fetcher = fetch,
): Promise<RazorpayTestRehearsalDescriptor> {
  const payload = record(await call(input, {
    operation: "prepareTestRehearsal",
    entityType: "dastak_v1_order",
    orderId: input.orderId,
    paymentAttemptId: input.paymentAttemptId,
    testOutcome: input.outcome,
  }, input.idempotencyKey, fetcher));
  const outcome = payload?.outcome;
  const testVpa = payload?.testVpa;
  if (
    payload?.testRehearsal !== true || payload?.providerMode !== "TEST" ||
    (outcome !== "SUCCESS" && outcome !== "FAILURE") ||
    (testVpa !== "success@razorpay" && testVpa !== "failure@razorpay") ||
    (outcome === "SUCCESS" && testVpa !== "success@razorpay") ||
    (outcome === "FAILURE" && testVpa !== "failure@razorpay")
  ) invalid();
  const amountPaise = payload?.amountPaise;
  if (typeof amountPaise !== "number" || !Number.isSafeInteger(amountPaise) || amountPaise <= 0 || payload?.currency !== "INR") invalid();
  return {
    testRehearsal: true,
    outcome,
    orderId: requiredUUID(payload?.orderId),
    paymentAttemptId: requiredUUID(payload?.paymentAttemptId),
    providerMode: "TEST",
    providerOrderId: requiredText(payload?.providerOrderId, 200),
    amountPaise,
    currency: "INR",
    testVpa,
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
  assertCheckoutProviderMode(session);
  if (session.providerMode === "TEST") return "failed";
  const methods = await discoverRazorpayMethods(session.keyId);
  if (!methods.upi) return "failed";
  const target = isMobileWeb() ? defaultMobileUPITarget(methods) : { kind: "qr" as const };
  if (!target) return "failed";
  const result = await launchRazorpayCustomUPI(
    session,
    customer,
    target,
  );
  if (result.status === "success") return "success";
  return result.status === "cancelled" ? "dismissed" : "failed";
}

type RazorpayCustomInstance = {
  once: (event: "ready", handler: (response: { methods?: Record<string, unknown> }) => void) => void;
  on: (
    event: "payment.success" | "payment.error" | "payment.cancel" | "payment.upi.qr",
    handler: (response: unknown) => void,
  ) => void;
  createPayment: (
    data: Record<string, unknown>,
    options?: { app: RazorpayMobileUPIApp; flow?: "qr" },
  ) => unknown;
  getSupportedUpiIntentApps?: () => Promise<unknown>;
};

type RazorpayCustomConstructor = new (options: {
  key: string;
}) => RazorpayCustomInstance;

export async function discoverRazorpayMethods(
  keyId: string,
  userAgent = navigator.userAgent,
): Promise<RazorpayMethodAvailability> {
  const Razorpay = await loadRazorpayCustomCheckout();
  return await new Promise((resolve, reject) => {
    const razorpay = new Razorpay({ key: keyId });
    let settled = false;
    const timeout = window.setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new PaymentRequestError(
        "method_discovery_timeout",
        "Available payment methods could not be loaded. Try again.",
        0,
      ));
    }, 8_000);
    const finish = (availability: RazorpayMethodAvailability) => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeout);
      resolve(availability);
    };
    razorpay.once("ready", async (response) => {
      const upi = response.methods?.upi === true || record(response.methods?.upi)?.enabled === true;
      if (!upi || !isMobileWeb(userAgent) || !razorpay.getSupportedUpiIntentApps) {
        finish({ upi, upiApps: [] });
        return;
      }
      try {
        const discoveredApps = await razorpay.getSupportedUpiIntentApps();
        finish({ upi, upiApps: mobileUPIOptions(discoveredApps, userAgent) });
      } catch {
        finish({ upi, upiApps: [] });
      }
    });
  });
}

export function launchRazorpayCustomUPI(
  session: CheckoutSession,
  customer: { name?: string; email?: string; phoneNumber?: string },
  target: CustomUPITarget,
  lifecycle: CustomCheckoutLifecycle = {},
): Promise<CustomCheckoutResult> {
  try {
    assertCheckoutProviderMode(session);
  } catch (modeError) {
    return Promise.resolve({
      status: "failed",
      message: userFacingError(modeError, "Payment configuration does not match this build."),
    });
  }
  if (session.providerMode === "TEST") {
    return Promise.resolve({ status: "not_launched", message: RAZORPAY_TEST_UPI_LIMITATION_MESSAGE });
  }
  const email = customer.email?.trim();
  const contact = customer.phoneNumber?.trim();
  if (!email) {
    return Promise.resolve({ status: "failed", message: "Your signed-in email is unavailable. Sign out and sign in again before payment." });
  }
  if (!contact) {
    return Promise.resolve({ status: "failed", message: "Add a delivery phone number to your Dastak profile before payment." });
  }
  // Method discovery loads razorpay.js before the customer can select a method.
  // Do not await script work here: mobile browsers require createPayment to run
  // synchronously in the original tap stack or they can block the UPI-app handoff.
  const Razorpay = razorpayCustomConstructor();
  if (!Razorpay) {
    return Promise.resolve({
      status: "not_launched",
      message: "Secure payment options are still loading. Check again, then choose a UPI app.",
    });
  }
  return new Promise((resolve) => {
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
      const description = optionalText(error?.description, 300)?.toLowerCase();
      const cancelled = reason === "payment_cancelled" || reason === "user_cancelled" || description?.includes("cancel") === true;
      finish(cancelled
        ? { status: "cancelled", message: "Payment was cancelled. Your secured basket remains reserved." }
        : { status: "failed", message: "Payment could not be completed. Try again while your basket remains reserved." });
    });
    razorpay.on("payment.cancel", () => finish({
      status: "cancelled",
      message: "Payment was cancelled. Your secured basket remains reserved.",
    }));
    razorpay.on("payment.upi.qr", (response) => {
      const source = record(response);
      const uri = optionalText(source?.qr_url, 20_000);
      const expiresAt = typeof source?.expires_on === "number" && Number.isFinite(source.expires_on)
        ? source.expires_on
        : undefined;
      if (uri && isSafeUpiQrUri(uri)) lifecycle.onQrCode?.({ uri, expiresAt });
    });
    try {
      const request: Record<string, unknown> = {
        amount: session.amountPaise,
        currency: session.currency,
        order_id: session.providerOrderId,
        email,
        contact,
        method: "upi",
      };
      const launchOptions = target.kind === "intent"
        ? { app: target.app }
        : { app: "any" as const, flow: "qr" as const };
      const launchResult = razorpay.createPayment(request, launchOptions);
      if (launchResult === false) {
        finish({ status: "not_launched", message: "The selected UPI app could not be opened. Choose it again to retry." });
        return;
      }
      if (!completed && target.kind === "intent") lifecycle.onLaunched?.();
    } catch {
      finish({ status: "not_launched", message: "The selected UPI app could not be opened. Choose it again to retry." });
    }
  });
}

/**
 * Owner-only TEST harness. The server mints the fixture descriptor after
 * checking owner entitlement and the authoritative Dastak payment attempt.
 * This deliberately never substitutes for the normal Customer payment path.
 */
export async function launchRazorpayTestUPI(
  session: CheckoutSession,
  customer: { name?: string; email?: string; phoneNumber?: string },
  descriptor: RazorpayTestRehearsalDescriptor,
): Promise<CustomCheckoutResult> {
  try {
    assertCheckoutProviderMode(session);
    if (
      session.providerMode !== "TEST" || !session.testRehearsalAvailable ||
      descriptor.testRehearsal !== true || descriptor.providerMode !== "TEST" ||
      descriptor.orderId !== session.orderId || descriptor.paymentAttemptId !== session.attemptId ||
      descriptor.providerOrderId !== session.providerOrderId ||
      descriptor.amountPaise !== session.amountPaise || descriptor.currency !== session.currency ||
      (descriptor.outcome === "SUCCESS" && descriptor.testVpa !== "success@razorpay") ||
      (descriptor.outcome === "FAILURE" && descriptor.testVpa !== "failure@razorpay")
    ) {
      throw new PaymentRequestError(
        "test_rehearsal_mismatch",
        "This Test rehearsal does not match the secured payment attempt.",
        409,
      );
    }
  } catch (modeError) {
    return {
      status: "failed",
      message: userFacingError(modeError, "Test payment rehearsal is unavailable."),
    };
  }

  const email = customer.email?.trim();
  const contact = customer.phoneNumber?.trim();
  if (!email || !contact) {
    return {
      status: "failed",
      message: "A signed-in email and delivery phone number are required for Test rehearsal.",
    };
  }
  let Razorpay: RazorpayCustomConstructor;
  try {
    Razorpay = await loadRazorpayCustomCheckout();
  } catch {
    return { status: "not_launched", message: "Test payment tools could not be loaded." };
  }

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
      finish(completion
        ? { status: "success", completion }
        : { status: "failed", message: "Test provider completion could not be verified." });
    });
    razorpay.on("payment.error", (response) => {
      const source = record(response);
      const error = record(source?.error);
      const description = optionalText(error?.description, 300) ?? "The simulated Test payment failed as requested.";
      finish({ status: "failed", message: description });
    });
    razorpay.on("payment.cancel", () => finish({
      status: "cancelled",
      message: "The Test rehearsal was cancelled. The secured basket remains reserved.",
    }));
    try {
      const launched = razorpay.createPayment({
        amount: session.amountPaise,
        currency: session.currency,
        order_id: session.providerOrderId,
        email,
        contact,
        method: "upi",
        vpa: descriptor.testVpa,
      });
      if (launched === false) finish({ status: "not_launched", message: "The Test provider did not start." });
    } catch {
      finish({ status: "not_launched", message: "The Test provider did not start." });
    }
  });
}

export function mobileUPIOptions(
  discoveredApps: unknown,
  userAgent = navigator.userAgent,
): MobileUPIOption[] {
  if (!isMobileWeb(userAgent)) return [];
  const identifiers = discoveredUpiAppIdentifiers(discoveredApps);
  const supported = new Set<RazorpayMobileUPIApp>(["gpay", "phonepe", "paytm", "any"]);
  const labels: Record<RazorpayMobileUPIApp, string> = {
    gpay: "Google Pay",
    phonepe: "PhonePe",
    paytm: "Paytm",
    any: "Other UPI apps",
  };
  const seen = new Set<RazorpayMobileUPIApp>();
  return identifiers.flatMap((identifier) => {
    const normalized = normalizeMobileUpiApp(identifier);
    if (!normalized || !supported.has(normalized) || seen.has(normalized)) return [];
    if (normalized === "any" && !/android/i.test(userAgent)) return [];
    seen.add(normalized);
    return [{ id: normalized, label: labels[normalized] }];
  });
}

function discoveredUpiAppIdentifiers(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value.flatMap((entry) => {
      if (typeof entry === "string") return [entry];
      const source = record(entry);
      return [source?.app, source?.id, source?.shortcode, source?.name]
        .filter((candidate): candidate is string => typeof candidate === "string");
    });
  }
  const source = record(value);
  if (!source) return [];
  const nested = source.apps ?? source.supported_apps ?? source.supportedApps;
  if (nested !== undefined) return discoveredUpiAppIdentifiers(nested);
  return Object.entries(source)
    .filter(([, available]) => available === true || record(available)?.enabled === true)
    .map(([identifier]) => identifier);
}

function normalizeMobileUpiApp(value: string): RazorpayMobileUPIApp | undefined {
  switch (value.trim().toLowerCase().replace(/[\s_-]+/g, "")) {
    case "gpay":
    case "googlepay": return "gpay";
    case "phonepe": return "phonepe";
    case "paytm": return "paytm";
    case "any":
    case "other":
    case "otherupiapps": return "any";
    default: return undefined;
  }
}

function defaultMobileUPITarget(methods: RazorpayMethodAvailability): CustomUPITarget | undefined {
  const app = methods.upiApps[0]?.id;
  return app ? { kind: "intent", app } : undefined;
}

function isSafeUpiQrUri(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === "upi:" && url.hostname.toLowerCase() === "pay";
  } catch {
    return false;
  }
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
      reject(new PaymentRequestError("checkout_unavailable", "Secure payment options could not be loaded.", 0));
    };
    if (present?.dataset.loaded === "true") {
      if (razorpayCustomConstructor()) resolve();
      else reject(new PaymentRequestError("checkout_unavailable", "Secure payment options are unavailable.", 0));
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
  if (!loaded) throw new PaymentRequestError("checkout_unavailable", "Secure payment options are unavailable.", 0);
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
  const explicitMode = source?.providerMode;
  const inferredMode: RazorpayPaymentMode | undefined = keyId.startsWith("rzp_test_")
    ? "TEST"
    : keyId.startsWith("rzp_live_") ? "LIVE" : undefined;
  const providerMode = explicitMode === "TEST" || explicitMode === "LIVE"
    ? explicitMode
    : entityType === "dastak_v1_order" ? undefined : inferredMode;
  const providerOrderId = requiredText(source?.providerOrderId, 200);
  const receipt = requiredText(source?.receipt, 40);
  const amountPaise = source?.amountPaise;
  if (
    !providerMode || providerMode !== inferredMode ||
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
    providerMode,
    providerOrderId,
    keyId,
    amountPaise,
    currency: "INR",
    receipt,
    testRehearsalAvailable: source?.testRehearsalAvailable === true,
  };
}

export function configuredRazorpayPaymentMode(
  raw = import.meta.env.VITE_RAZORPAY_PAYMENT_MODE,
): RazorpayPaymentMode | undefined {
  const normalized = raw?.trim().toUpperCase();
  return normalized === "TEST" || normalized === "LIVE" ? normalized : undefined;
}

export function assertCheckoutProviderMode(
  session: CheckoutSession,
  configuredMode = configuredRazorpayPaymentMode(),
) {
  const keyMode: RazorpayPaymentMode | undefined = session.keyId.startsWith("rzp_test_")
    ? "TEST"
    : session.keyId.startsWith("rzp_live_") ? "LIVE" : undefined;
  if (!keyMode || keyMode !== session.providerMode) {
    throw new PaymentRequestError("payment_mode_mismatch", "Payment configuration does not match this checkout.", 409);
  }
  if (configuredMode && configuredMode !== session.providerMode) {
    throw new PaymentRequestError("payment_mode_mismatch", "Payment configuration does not match this build.", 409);
  }
  if (!configuredMode && import.meta.env.PROD) {
    throw new PaymentRequestError("payment_mode_missing", "Payment mode is not configured for this build.", 503);
  }
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
