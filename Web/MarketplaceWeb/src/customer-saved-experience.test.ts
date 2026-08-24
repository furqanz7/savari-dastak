import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("customer saved, payment and merchant-entry experience", () => {
  const experience = readFileSync(
    new URL("./DastakV1CustomerExperience.tsx", import.meta.url),
    "utf8",
  );
  const account = readFileSync(new URL("./CatalogueView.tsx", import.meta.url), "utf8");

  it("surfaces a real Wishlist for retail and Restaurant/Cafe items", () => {
    expect(experience).toContain("getCustomerWishlist");
    expect(experience).toContain('toggleWishlist("MENU_ITEM"');
    expect(experience).toContain('onWishlist("RETAIL_SKU"');
    expect(experience).toContain("Things worth remembering");
  });

  it("keeps payment settings truthful and provider-secured", () => {
    expect(experience).toContain("Razorpay-secured checkout");
    expect(experience).toContain("never stores your card number, UPI PIN or bank credentials");
    expect(experience).toContain("Recent payment activity");
    expect(experience).not.toContain("Saved Cards");
  });

  it("routes Sell on Dastak to the configured Merchant application", () => {
    expect(account).toContain("Sell on Dastak");
    expect(account).toContain("merchantUrl");
    expect(account).toContain("href={merchantUrl}");
  });
});
