type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export type RazorpayOrder = {
  id: string;
  amount: number;
  currency: "INR";
  receipt: string;
  status: "created" | "attempted" | "paid";
};

export type RazorpayRefund = {
  id: string;
  amount: number;
  currency: "INR";
  paymentId: string;
  receipt: string;
  status: "pending" | "processed";
};

export class RazorpayApiError extends Error {
  constructor(public readonly status: number) {
    super("Razorpay API request failed");
    this.name = "RazorpayApiError";
  }
}

export class RazorpayClient {
  private readonly authorization: string;

  constructor(
    public readonly keyId: string,
    keySecret: string,
    private readonly fetcher: Fetcher = fetch,
  ) {
    if (!/^rzp_(test|live)_[A-Za-z0-9]+$/.test(keyId) || keySecret.length < 8) {
      throw new Error("Valid Razorpay credentials are required");
    }
    this.authorization = `Basic ${btoa(`${keyId}:${keySecret}`)}`;
  }

  async resolveOrder(
    input: { amountPaise: number; currency: "INR"; receipt: string; orderId: string },
  ) {
    const existing = await this.findOrderByReceipt(input.receipt);
    if (existing) {
      assertOrderMatches(existing, input);
      return existing;
    }

    const created = parseOrder(
      await this.request("/orders", {
        method: "POST",
        body: JSON.stringify({
          amount: input.amountPaise,
          currency: input.currency,
          receipt: input.receipt,
          partial_payment: false,
          notes: { dastak_order_id: input.orderId },
        }),
      }),
    );
    assertOrderMatches(created, input);
    return created;
  }

  async fetchOrder(providerOrderId: string) {
    return parseOrder(await this.request(`/orders/${encodeURIComponent(providerOrderId)}`));
  }

  async resolveRefund(input: {
    providerPaymentId: string;
    amountPaise: number;
    currency: "INR";
    receipt: string;
    orderId: string;
  }) {
    const existing = await this.findRefundByReceipt(input.providerPaymentId, input.receipt);
    if (existing) {
      assertRefundMatches(existing, input);
      return existing;
    }

    const created = parseRefund(
      await this.request(
        `/payments/${encodeURIComponent(input.providerPaymentId)}/refund`,
        {
          method: "POST",
          body: JSON.stringify({
            amount: input.amountPaise,
            receipt: input.receipt,
            notes: { dastak_order_id: input.orderId },
          }),
        },
      ),
    );
    assertRefundMatches(created, input);
    return created;
  }

  private async findOrderByReceipt(receipt: string) {
    const payload = record(
      await this.request(`/orders?receipt=${encodeURIComponent(receipt)}&count=1`),
    );
    if (!payload || !Array.isArray(payload.items)) throw new RazorpayApiError(502);
    return payload.items.length === 0 ? undefined : parseOrder(payload.items[0]);
  }

  private async findRefundByReceipt(providerPaymentId: string, receipt: string) {
    const payload = record(
      await this.request(
        `/payments/${encodeURIComponent(providerPaymentId)}/refunds?count=100`,
      ),
    );
    if (!payload || !Array.isArray(payload.items)) throw new RazorpayApiError(502);
    const match = payload.items.find((item) => record(item)?.receipt === receipt);
    return match === undefined ? undefined : parseRefund(match);
  }

  private async request(path: string, init: RequestInit = {}) {
    let response: Response;
    try {
      response = await this.fetcher(`https://api.razorpay.com/v1${path}`, {
        ...init,
        headers: {
          authorization: this.authorization,
          accept: "application/json",
          ...(init.body ? { "content-type": "application/json" } : {}),
        },
      });
    } catch {
      throw new RazorpayApiError(502);
    }
    const payload = await response.json().catch(() => undefined);
    if (!response.ok || payload === undefined) throw new RazorpayApiError(response.status || 502);
    return payload;
  }
}

export { RazorpayClient as RazorpayTestClient };

function parseOrder(value: unknown): RazorpayOrder {
  const source = record(value);
  const status = source?.status;
  if (
    !source || typeof source.id !== "string" || !/^order_[A-Za-z0-9]+$/.test(source.id) ||
    !validMoney(source.amount) || source.currency !== "INR" ||
    typeof source.receipt !== "string" || source.receipt.length < 1 || source.receipt.length > 40 ||
    (status !== "created" && status !== "attempted" && status !== "paid")
  ) throw new RazorpayApiError(502);
  return { id: source.id, amount: source.amount, currency: "INR", receipt: source.receipt, status };
}

function parseRefund(value: unknown): RazorpayRefund {
  const source = record(value);
  const status = source?.status;
  if (
    !source || typeof source.id !== "string" || !/^rfnd_[A-Za-z0-9]+$/.test(source.id) ||
    !validMoney(source.amount) || source.currency !== "INR" ||
    typeof source.payment_id !== "string" || !/^pay_[A-Za-z0-9]+$/.test(source.payment_id) ||
    typeof source.receipt !== "string" || source.receipt.length < 1 || source.receipt.length > 40 ||
    (status !== "pending" && status !== "processed")
  ) throw new RazorpayApiError(502);
  return {
    id: source.id,
    amount: source.amount,
    currency: "INR",
    paymentId: source.payment_id,
    receipt: source.receipt,
    status,
  };
}

function assertOrderMatches(
  order: RazorpayOrder,
  expected: { amountPaise: number; currency: "INR"; receipt: string },
) {
  if (
    order.amount !== expected.amountPaise || order.currency !== expected.currency ||
    order.receipt !== expected.receipt
  ) {
    throw new RazorpayApiError(409);
  }
}

function assertRefundMatches(
  refund: RazorpayRefund,
  expected: { providerPaymentId: string; amountPaise: number; currency: "INR"; receipt: string },
) {
  if (
    refund.paymentId !== expected.providerPaymentId || refund.amount !== expected.amountPaise ||
    refund.currency !== expected.currency || refund.receipt !== expected.receipt
  ) throw new RazorpayApiError(409);
}

function validMoney(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 &&
    value <= 100_000_000;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}
