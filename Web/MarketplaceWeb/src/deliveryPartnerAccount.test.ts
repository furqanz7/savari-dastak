import { describe, expect, it } from "vitest";
import { deliveryPartnerAccountPresentation } from "./deliveryPartnerAccount";

describe("delivery partner account presentation", () => {
  it("switches approved partners instead of asking them to apply", () => {
    const presentation = deliveryPartnerAccountPresentation("approved");

    expect(presentation.title).toBe("Switch to Delivery Partner mode");
    expect(presentation.status).toBe("Approved");
  });

  it("only offers a new application when the account has not applied", () => {
    expect(deliveryPartnerAccountPresentation("not_applied").title).toBe("Become a Delivery Partner");
    expect(deliveryPartnerAccountPresentation("pending").title).toBe("View your application");
    expect(deliveryPartnerAccountPresentation("rejected").title).toBe("Update your application");
    expect(deliveryPartnerAccountPresentation("unavailable").title).not.toContain("Become");
  });
});
