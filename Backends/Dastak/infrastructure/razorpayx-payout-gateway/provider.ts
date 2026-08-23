import type { PayoutGatewayRequest } from "../../supabase/functions/_shared/payout-gateway.ts";
import type { RazorpayXClient } from "../../supabase/functions/_shared/razorpayx.ts";

export async function executeRazorpayXPayout(
  provider: RazorpayXClient,
  payoutRequest: PayoutGatewayRequest,
) {
  const destinationType = await provider.fetchFundAccountType(
    payoutRequest.fundAccountReference,
  );
  const payout = await provider.createPayout({
    withdrawalId: payoutRequest.withdrawalId,
    fundAccountId: payoutRequest.fundAccountReference,
    amountPaise: payoutRequest.amountPaise,
    mode: destinationType === "UPI" ? "UPI" : "IMPS",
    idempotencyKey: payoutRequest.idempotencyKey,
  });
  return {
    withdrawalId: payoutRequest.withdrawalId,
    providerPayoutReference: payout.id,
    fundAccountReference: payout.fundAccountId,
    amountPaise: payout.amountPaise,
    currency: payout.currency,
    mode: payout.mode,
    status: payout.status,
    createdAt: payout.createdAt,
    ...(payout.utr ? { utr: payout.utr } : {}),
    statusDetails: payout.statusDetails,
  };
}
