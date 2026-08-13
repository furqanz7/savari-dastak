export type EarningsSnapshot = { currency: "INR"; completedPaise: number; pendingPaise: number; thisWeekPaise: number };

export async function getEarnings(
  input: { supabaseUrl: string; publishableKey: string; accessToken: string },
  operation: "merchantSnapshot" | "deliveryPartnerSnapshot",
): Promise<EarningsSnapshot> {
  const response = await fetch(`${input.supabaseUrl}/functions/v1/earnings`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: input.publishableKey,
      authorization: `Bearer ${input.accessToken}`,
      "x-idempotency-key": crypto.randomUUID(),
    },
    body: JSON.stringify({ operation }),
  });
  const payload = await response.json().catch(() => undefined) as Record<string, unknown> | undefined;
  if (!response.ok || !payload || payload.currency !== "INR" || !validMoney(payload.completedPaise) || !validMoney(payload.pendingPaise) || !validMoney(payload.thisWeekPaise)) {
    throw new Error(typeof payload?.error === "object" && payload.error !== null && typeof (payload.error as Record<string, unknown>).message === "string" ? (payload.error as Record<string, string>).message : "Earnings are unavailable.");
  }
  return { currency: "INR", completedPaise: payload.completedPaise as number, pendingPaise: payload.pendingPaise as number, thisWeekPaise: payload.thisWeekPaise as number };
}

function validMoney(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}
