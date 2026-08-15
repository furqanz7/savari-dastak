import { describe, expect, it } from "vitest";
import {
  evidenceObjectPath,
  getMerchantApplicationSnapshot,
  isAcceptedEvidenceFile,
  MerchantApplicationRequestError,
  submitMerchantApplication,
} from "./merchant-application";

const accountId = "22222222-2222-4222-8222-222222222222";
const applicationId = "33333333-3333-4333-8333-333333333333";
const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

describe("merchant application", () => {
  it("builds an opaque account-owned evidence path", () => {
    expect(evidenceObjectPath(accountId, "application/pdf", "44444444-4444-4444-8444-444444444444"))
      .toBe(`merchant/${accountId}/44444444-4444-4444-8444-444444444444.pdf`);
  });

  it("accepts only supported evidence files up to 10 MB", () => {
    expect(isAcceptedEvidenceFile({ type: "image/jpeg", size: 10 * 1024 * 1024 })).toBe(true);
    expect(isAcceptedEvidenceFile({ type: "application/pdf", size: 10 * 1024 * 1024 + 1 })).toBe(false);
    expect(isAcceptedEvidenceFile({ type: "text/plain", size: 100 })).toBe(false);
  });

  it("submits normalized business details with idempotency", async () => {
    let request: RequestInit | undefined;
    const result = await submitMerchantApplication({
      ...auth,
      businessName: "  Corner   Store  ",
      businessAddress: "  12   Main Road  ",
      evidenceObjectPath: `merchant/${accountId}/evidence.pdf`,
      idempotencyKey: "merchant-submit-1",
    }, (_url, init) => {
      request = init;
      return Promise.resolve(new Response(JSON.stringify({ applicationId, status: "pending" }), { status: 200 }));
    });

    expect(result).toEqual({ applicationId, status: "pending" });
    expect(request?.headers).toMatchObject({ "X-Idempotency-Key": "merchant-submit-1" });
    expect(JSON.parse(String(request?.body))).toEqual({
      operation: "submit",
      businessName: "Corner Store",
      businessAddress: "12 Main Road",
      evidenceObjectPath: `merchant/${accountId}/evidence.pdf`,
    });
  });

  it("preserves safe application errors", async () => {
    await expect(submitMerchantApplication({
      ...auth,
      businessName: "Corner Store",
      businessAddress: "12 Main Road",
      evidenceObjectPath: `merchant/${accountId}/evidence.pdf`,
      idempotencyKey: "merchant-submit-2",
    }, () => Promise.resolve(new Response(JSON.stringify({
      error: { code: "merchant_application_pending", message: "A merchant application is already pending." },
    }), { status: 409 })))).rejects.toEqual(
      new MerchantApplicationRequestError(
        "merchant_application_pending",
        "A merchant application is already pending.",
        409,
      ),
    );
  });

  it("loads the authenticated merchant's rejected application", async () => {
    const snapshot = await getMerchantApplicationSnapshot(auth, (_url, init) => {
      expect(JSON.parse(String(init?.body))).toEqual({ operation: "selfSnapshot" });
      return Promise.resolve(new Response(JSON.stringify({
        onboardingState: "rejected",
        applicationId,
        businessName: "Corner Store",
        businessAddress: "12 Main Road",
        evidenceObjectPath: `merchant/${accountId}/evidence.pdf`,
        reviewReason: "Upload a clearer document.",
      }), { status: 200 }));
    });

    expect(snapshot.onboardingState).toBe("rejected");
    expect(snapshot.businessName).toBe("Corner Store");
    expect(snapshot.reviewReason).toBe("Upload a clearer document.");
  });
});
