import type { RazorpayPaymentMode } from "../_shared/razorpay.ts";

export type RazorpayTestRehearsalOutcome = "SUCCESS" | "FAILURE";

export type RazorpayTestRehearsalContext = {
  orderId: string;
  attemptId: string;
  providerOrderId: string;
  providerMode: RazorpayPaymentMode;
  amountPaise: number;
  currency: "INR";
};

type RehearsalResult =
  | { responseStatus: 200; responseBody: Record<string, unknown> }
  | { responseStatus: 403 | 404 | 409; responseBody: { error: { code: string; message: string } } };

/**
 * Builds the provider TEST descriptor without mutating Dastak payment state.
 * The official Razorpay fixture VPA is selected only here, from a closed enum;
 * clients cannot provide an amount, order reference, mode, or payee.
 */
export function prepareRazorpayTestRehearsal(
  configuredMode: RazorpayPaymentMode,
  isOwner: boolean,
  context: RazorpayTestRehearsalContext,
  outcome: RazorpayTestRehearsalOutcome,
): RehearsalResult {
  if (configuredMode !== "TEST") {
    return rejected(404, "test_rehearsal_disabled", "Test payment rehearsal is not enabled.");
  }
  if (!isOwner) {
    return rejected(403, "test_rehearsal_forbidden", "This account cannot use payment rehearsal.");
  }
  if (
    context.providerMode !== "TEST" || context.currency !== "INR" ||
    !Number.isSafeInteger(context.amountPaise) || context.amountPaise <= 0 ||
    !/^order_[A-Za-z0-9]+$/.test(context.providerOrderId)
  ) {
    return rejected(
      409,
      "test_rehearsal_mode_mismatch",
      "The payment attempt does not belong to the Test provider environment.",
    );
  }

  return {
    responseStatus: 200,
    responseBody: {
      testRehearsal: true,
      outcome,
      orderId: context.orderId,
      paymentAttemptId: context.attemptId,
      providerMode: "TEST",
      providerOrderId: context.providerOrderId,
      amountPaise: context.amountPaise,
      currency: "INR",
      testVpa: outcome === "SUCCESS" ? "success@razorpay" : "failure@razorpay",
    },
  };
}

function rejected(
  responseStatus: 403 | 404 | 409,
  code: string,
  message: string,
): RehearsalResult {
  return { responseStatus, responseBody: { error: { code, message } } };
}
