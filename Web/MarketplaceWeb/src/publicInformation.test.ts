import { describe, expect, it } from "vitest";
import { publicInformationKindForPath, publicInformationPages } from "./publicInformation";

describe("public Dastak information pages", () => {
  it("resolves only the three first-party public routes", () => {
    expect(publicInformationKindForPath("/privacy")).toBe("privacy");
    expect(publicInformationKindForPath("/terms/")).toBe("terms");
    expect(publicInformationKindForPath(" /support/ ")).toBe("support");
    expect(publicInformationKindForPath("/")).toBeUndefined();
    expect(publicInformationKindForPath("/account")).toBeUndefined();
  });

  it("publishes complete privacy, terms and support content", () => {
    expect(Object.keys(publicInformationPages)).toEqual(["privacy", "terms", "support"]);
    expect(publicInformationPages.privacy.sections.length).toBeGreaterThanOrEqual(7);
    expect(publicInformationPages.terms.sections.length).toBeGreaterThanOrEqual(8);
    expect(publicInformationPages.support.actions?.map((action) => action.href)).toEqual([
      "/#/orders",
      "/#/account",
      "/privacy",
    ]);
    expect(JSON.stringify(publicInformationPages.support)).not.toMatch(/mailto:/i);
  });

  it("describes retained diagnostics and distinguishes current doorstep payment from legacy online checkout", () => {
    const privacy = JSON.stringify(publicInformationPages.privacy);
    expect(privacy).toContain("request timestamps, IP addresses");
    expect(privacy).toContain("processing times");
    expect(privacy).toContain("may be linked to your account");
    expect(privacy).toContain("Pay via UPI/Cash on Delivery");
    expect(privacy).toContain("does not include Razorpay checkout");
    expect(privacy).toContain("older supported online-payment flow");
    expect(privacy).toContain("earnings, balances, withdrawals");
  });

  it("keeps Terms consistent with confirmation before doorstep collection", () => {
    const terms = JSON.stringify(publicInformationPages.terms);
    expect(terms).toContain("before order confirmation becomes available");
    expect(terms).toContain("Pay via UPI/Cash on Delivery");
    expect(terms).toContain("No payment is taken when you confirm");
    expect(terms).toContain("Use Cancel order while it is available before confirmation");
    expect(terms).toContain("does not offer Razorpay checkout");
    expect(terms).toContain("Older order history remains viewable");
    expect(terms).not.toMatch(/prepaid only|Cash on delivery, substitutions|before successful payment|before payment becomes available/);
  });

  it("covers Merchant collection without promising live payouts or anonymous support", () => {
    const page = publicInformationPages.privacy;
    const section = (title: string) => JSON.stringify(page.sections.find((entry) => entry.title === title));
    expect(page.summary).toContain("operate a Merchant store");
    expect(section("Merchant applications and store verification")).toContain("government identity or business-registration document");
    expect(section("Merchant applications and store verification")).toContain("precise coordinates");
    expect(section("Merchant applications and store verification")).toContain("not a continuous background location-tracking feature");
    expect(section("Operating a Merchant store")).toContain("Grocery catalogue search sends the search text");
    expect(section("Merchant earnings and payout information")).toContain("RazorpayX where used");
    expect(section("Merchant earnings and payout information")).toContain("does not guarantee that withdrawals are enabled");
    expect(section("Merchant data kept on your device")).toContain("device-only Keychain storage");
    expect(section("Exploring the Merchant demo")).toContain("simulated locally");
    expect(section("Exploring the Merchant demo")).toContain("Merchant support is disabled inside the sample");
    const support = section("Merchant support conversations");
    expect(support).toContain("https://dastak-merchant.vercel.app/merchant-support");
    expect(support).toContain("does not mean a message is anonymous");
    expect(support).toContain("hashes its secret before sending it to ticket storage");
    expect(support).toContain("We do not email replies or guarantee a response time");
    expect(support).toContain("cannot authorize account approval");
    expect(section("Merchant account and privacy choices")).toContain("does not by itself identify and erase every support conversation");
    expect(section("Retention and security")).toContain("no automatic conversation-expiry schedule");
    expect(section("Retention and security")).toContain("IP-derived network or approximate geographic information");
    expect(JSON.stringify(page)).not.toContain("Approval checklist");
  });

  it("preserves Customer/Delivery distinctions and dates the approved privacy publication separately", () => {
    const privacy = JSON.stringify(publicInformationPages.privacy);
    expect(privacy).toContain("delivery-partner onboarding");
    expect(privacy).toContain("rounds your nearby-area latitude and longitude to two decimal places");
    expect(privacy).toContain("does not retain weather-location fixes");
    expect(privacy).toContain("does not include Razorpay checkout");
    expect(publicInformationPages.privacy.updated).toBe("28 October 2026");
    expect(publicInformationPages.terms.updated).toBe("17 October 2026");
    expect(publicInformationPages.support.updated).toBe("17 October 2026");
  });

  it("provides current payment help without promising legacy retries or a fixed refund destination", () => {
    const support = JSON.stringify(publicInformationPages.support);
    expect(support).toContain("pay the assigned delivery partner by UPI or cash at the doorstep");
    expect(support).toContain("Check the recorded amount and collection status before paying again");
    expect(support).toContain("Online-payment retries for older orders are unavailable");
    expect(support).toContain("resolution, refund method and timing will be communicated for the case");
    expect(support).not.toMatch(/failed attempt can be retried|refunds go to the original payment method/);
    expect(JSON.stringify(publicInformationPages.terms)).not.toContain("Approved refunds are issued to the original payment method");
  });
});
