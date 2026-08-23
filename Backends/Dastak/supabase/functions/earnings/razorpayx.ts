import {
  destinationFingerprint,
  normalizeDestination,
  type RazorpayXClient,
  type RazorpayXDestinationInput,
  safeDestinationPresentation,
  sha256,
} from "../_shared/razorpayx.ts";
import { PayoutGatewayError, type PayoutGatewayResult } from "../_shared/payout-gateway.ts";

type CallRPC = (rpc: string, args: Record<string, unknown>) => Promise<unknown>;

export async function registerRazorpayXDestination(input: {
  actorId: string;
  subjectType: "MERCHANT_ORGANIZATION" | "RIDER";
  subjectId: string;
  destination: RazorpayXDestinationInput;
  fingerprintSecret: string;
  client: RazorpayXClient;
  callRPC: CallRPC;
}) {
  const destination = normalizeDestination(input.destination);
  const context = object(
    await input.callRPC("dastak_v1_razorpayx_destination_context", {
      p_account_id: input.actorId,
      p_subject_type: input.subjectType,
      p_subject_id: input.subjectId,
    }),
  );
  const contactName = text(context.contactName);
  const referenceId = text(context.providerReferenceId);
  const existingContact = optionalText(context.providerContactReference);
  const contactId = existingContact ?? (await input.client.createContact({
    name: contactName,
    referenceId,
  })).id;
  const fundAccount = await input.client.createFundAccount(contactId, destination);
  const presentation = safeDestinationPresentation(destination);
  const fingerprint = await destinationFingerprint(input.fingerprintSecret, destination);
  return await input.callRPC("dastak_v1_finalize_razorpayx_payout_destination", {
    p_account_id: input.actorId,
    p_subject_type: input.subjectType,
    p_subject_id: input.subjectId,
    p_destination_type: destination.type,
    p_provider_contact_reference: contactId,
    p_provider_fund_account_reference: fundAccount.id,
    p_provider_reference_id: referenceId,
    p_contact_name: contactName,
    p_display_label: presentation.displayLabel,
    p_destination_fingerprint: fingerprint,
    p_safe_metadata: presentation.metadata,
  });
}

export async function executeRazorpayXWithdrawal(input: {
  actorId: string;
  withdrawalId: string;
  expectedVersion: number;
  client: {
    executePayout: (request: {
      withdrawalId: string;
      amountPaise: number;
      currency: "INR";
      fundAccountReference: string;
      idempotencyKey: string;
    }) => Promise<PayoutGatewayResult>;
  };
  callRPC: CallRPC;
  requestId?: () => string;
  now?: () => Date;
}) {
  const context = parseExecutionContext(
    await input.callRPC("dastak_v1_claim_razorpayx_withdrawal", {
      p_account_id: input.actorId,
      p_withdrawal_id: input.withdrawalId,
      p_expected_version: input.expectedVersion,
    }),
  );
  const requestId = input.requestId ? input.requestId() : crypto.randomUUID();
  const now = (input.now ?? (() => new Date()))();
  const operation = "PAYOUT_CREATE";
  const requestDigest = context.requestDigest;
  try {
    const payout = await input.client.executePayout({
      withdrawalId: context.withdrawalId,
      amountPaise: context.amountPaise,
      currency: "INR",
      fundAccountReference: context.fundAccountReference,
      idempotencyKey: context.payoutIdempotencyKey,
    });
    assertProviderPayoutMatches(payout, context);
    const safePayload = payoutMetadata(payout);
    await input.callRPC("dastak_v1_record_razorpayx_provider_request", {
      p_request_id: requestId,
      p_withdrawal_id: context.withdrawalId,
      p_attempt_id: context.attemptId,
      p_operation: operation,
      p_request_key: context.payoutIdempotencyKey,
      p_request_digest: requestDigest,
      p_outcome: "ACCEPTED",
      p_http_status: 200,
      p_provider_payout_reference: payout.providerPayoutReference,
      p_response_metadata: safePayload,
      p_occurred_at: now.toISOString(),
    });
    const responseDigest = await sha256(JSON.stringify(safePayload));
    return await input.callRPC("dastak_v1_apply_razorpayx_payout_status", {
      p_provider_event_id: `api:${requestId}`,
      p_source: "API_RESPONSE",
      p_withdrawal_id: context.withdrawalId,
      p_attempt_id: context.attemptId,
      p_provider_payout_reference: payout.providerPayoutReference,
      p_provider_event_type: operation.toLowerCase(),
      p_provider_status: payout.status,
      p_amount_paise: payout.amountPaise,
      p_currency_code: payout.currency,
      p_fund_account_reference: payout.fundAccountReference,
      p_request_digest: responseDigest,
      p_payload_metadata: safePayload,
      p_occurred_at: now.toISOString(),
      p_provider_created_at: payout.createdAt,
      p_utr: payout.utr ?? null,
      p_status_details: payout.statusDetails,
    });
  } catch (error) {
    if (!(error instanceof PayoutGatewayError)) throw error;
    await input.callRPC("dastak_v1_record_razorpayx_provider_request", {
      p_request_id: requestId,
      p_withdrawal_id: context.withdrawalId,
      p_attempt_id: context.attemptId,
      p_operation: operation,
      p_request_key: context.payoutIdempotencyKey,
      p_request_digest: requestDigest,
      p_outcome: error.ambiguous ? "UNKNOWN" : "REJECTED",
      p_http_status: error.status || null,
      p_provider_payout_reference: context.providerPayoutReference ?? null,
      p_response_metadata: error.safeMetadata,
      p_occurred_at: now.toISOString(),
    });
    if (
      error.code === "payout_ownership_mismatch" ||
      error.code === "idempotency_payload_mismatch" ||
      error.code === "invalid_provider_response" || error.code === "invalid_gateway_response"
    ) {
      return await input.callRPC("dastak_v1_mark_razorpayx_reconciliation_required", {
        p_withdrawal_id: context.withdrawalId,
        p_attempt_id: context.attemptId,
        p_request_id: requestId,
        p_reason: error.code.toUpperCase(),
      });
    }
    if (error.ambiguous || context.providerPayoutReference) {
      return {
        withdrawalId: context.withdrawalId,
        status: "PROCESSING",
        providerStatus: context.providerStatus,
        reconciliationState: "PENDING",
        retryable: true,
      };
    }
    return await input.callRPC("dastak_v1_mark_razorpayx_submission_retryable", {
      p_withdrawal_id: context.withdrawalId,
      p_attempt_id: context.attemptId,
      p_request_id: requestId,
      p_failure_code: `RAZORPAYX_${error.code.toUpperCase().replace(/[^A-Z0-9_]/g, "_")}`,
    });
  }
}

type ExecutionContext = {
  withdrawalId: string;
  attemptId: string;
  subjectType: "MERCHANT_ORGANIZATION" | "RIDER";
  subjectId: string;
  amountPaise: number;
  fundAccountReference: string;
  payoutMode: "IMPS" | "UPI";
  payoutIdempotencyKey: string;
  requestDigest: string;
  providerPayoutReference?: string;
  providerStatus: string;
  version: number;
};

function parseExecutionContext(value: unknown): ExecutionContext {
  const source = object(value);
  const subjectType = source.subjectType;
  const payoutMode = source.payoutMode;
  const providerPayoutReference = optionalText(source.providerPayoutReference);
  if (
    (subjectType !== "MERCHANT_ORGANIZATION" && subjectType !== "RIDER") ||
    (payoutMode !== "IMPS" && payoutMode !== "UPI") ||
    !uuid(source.withdrawalId) || !uuid(source.attemptId) || !uuid(source.subjectId) ||
    !money(source.amountPaise) || !providerId(source.fundAccountReference, "fa") ||
    source.payoutIdempotencyKey !== source.withdrawalId ||
    typeof source.requestDigest !== "string" || !/^[0-9a-f]{64}$/.test(source.requestDigest) ||
    (providerPayoutReference !== undefined && !providerId(providerPayoutReference, "pout")) ||
    typeof source.providerStatus !== "string" || !version(source.version)
  ) throw new Error("Invalid RazorpayX withdrawal execution context");
  return source as unknown as ExecutionContext;
}

function assertProviderPayoutMatches(payout: PayoutGatewayResult, context: ExecutionContext) {
  if (
    payout.withdrawalId !== context.withdrawalId ||
    payout.fundAccountReference !== context.fundAccountReference ||
    payout.amountPaise !== context.amountPaise || payout.currency !== "INR" ||
    payout.mode !== context.payoutMode ||
    (context.providerPayoutReference &&
      payout.providerPayoutReference !== context.providerPayoutReference)
  ) {
    throw new PayoutGatewayError(409, true, "payout_ownership_mismatch", {
      providerPayoutReference: payout.providerPayoutReference,
      providerStatus: payout.status,
      fundAccountReference: payout.fundAccountReference,
      amountPaise: payout.amountPaise,
      mode: payout.mode,
    });
  }
}

function payoutMetadata(payout: PayoutGatewayResult) {
  return {
    id: payout.providerPayoutReference,
    status: payout.status,
    amountPaise: payout.amountPaise,
    currency: payout.currency,
    mode: payout.mode,
    fundAccountReference: payout.fundAccountReference,
    createdAt: payout.createdAt,
    ...(payout.utr ? { utr: payout.utr } : {}),
    statusDetails: payout.statusDetails,
  };
}

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid RazorpayX response");
  }
  return value as Record<string, unknown>;
}

function text(value: unknown) {
  if (typeof value !== "string" || value.length < 1) throw new Error("Invalid RazorpayX response");
  return value;
}

function optionalText(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function uuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function providerId(value: unknown, prefix: "fa" | "pout") {
  return typeof value === "string" && new RegExp(`^${prefix}_[A-Za-z0-9]+$`).test(value);
}

function money(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 100;
}

function version(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}
