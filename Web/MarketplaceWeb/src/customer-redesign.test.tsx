import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { CartSheet, ProductGrid, SearchSection } from "./DastakV1CustomerExperience";
import { CustomerNotice, CustomerSyncStatus } from "./CustomerUI";
import type { V1CatalogueSku } from "./dastakV1";

const noop = () => undefined;
const sku: V1CatalogueSku = {
  id: "product", categoryId: "milk", subcategoryId: "toned", name: "A particularly long product name with its full flavour and variant information",
  slug: "milk", packSize: "500 ml × 4", galleryImageKeys: [], attributes: {}, logisticsAttributes: {},
  imageKey: "catalogue/milk.png", listPricePaise: 12000, sellingPricePaise: 10000, currencyCode: "INR",
};
const productProps = { supabaseUrl: "https://example.supabase.co", skus: [sku],
  onAdd: noop, onWishlist: noop, wishlistIds: new Set<string>(), wishlistUpdatingIds: new Set<string>() };

describe("Customer Web design and presentation contracts", () => {
  it("gives product titles their own full-width control, separate from purchase and save controls", () => {
    const html = renderToStaticMarkup(<ProductGrid {...productProps} />);
    expect(html).toContain(`class="customer-product-title" title="${sku.name}"`);
    expect(html).toContain(`aria-label="Add ${sku.name}"`);
    expect(html).toContain("customer-product-price");
    expect(html).toContain("500 ml × 4");
    expect(html).toContain("17% off");
    expect(html).toContain('aria-pressed="false"');
    expect(html).toContain('role="status"');
  });

  it("keeps an empty search lightweight even if a previous result is still supplied", () => {
    const html = renderToStaticMarkup(<SearchSection {...productProps} query="  " onQuery={noop} searching={false} />);
    expect(html).toContain("Need a little inspiration?");
    expect(html).not.toContain("v1-product-grid");
    expect(html).not.toContain(sku.name);
  });

  it("does not offer checkout actions on an empty basket", () => {
    const html = renderToStaticMarkup(<CartSheet lines={[]} foodLines={[]} subtotal={0} busy={false}
      supabaseUrl={productProps.supabaseUrl} onDismiss={noop} onAdd={noop} onDecrement={noop}
      onAddFood={noop} onDecrementFood={noop} onAddress={noop} onSubmit={noop} />);
    expect(html).toContain("A little empty in here");
    expect(html).toContain('aria-modal="true"');
    expect(html).not.toContain("Place order");
    expect(html).not.toContain("Add address to continue");
  });

  it("keeps the populated basket authoritative and its error inside the dialog", () => {
    const html = renderToStaticMarkup(<CartSheet lines={[{ sku, quantity: 2 }]} foodLines={[]} subtotal={20000} busy={false}
      supabaseUrl={productProps.supabaseUrl} onDismiss={noop} onAdd={noop} onDecrement={noop}
      onAddFood={noop} onDecrementFood={noop} onAddress={noop} onSubmit={noop} error="Please check your address." />);
    expect(html).toContain("Your basket needs attention");
    expect(html).toContain("Please check your address.");
    expect(html).toContain("customer-cart-retail-line");
    expect(html).toContain("₹200.00");
    expect(html).toContain("Add address to continue");
    expect(html).toContain("No charge now");
  });

  it("uses quiet sync information, with recovery actions only on scoped failures", () => {
    const healthy = renderToStaticMarkup(<CustomerSyncStatus health="subscribed" />);
    const delayed = renderToStaticMarkup(<CustomerSyncStatus health="degraded" />);
    expect(healthy).toContain("Updates automatically");
    expect(healthy).not.toContain("<button");
    expect(delayed).toContain("Reconnecting");
    const notice = renderToStaticMarkup(<CustomerNotice title="Products couldn’t update" onRetry={noop}>Your loaded products are still available.</CustomerNotice>);
    expect(notice).toContain('role="alert"');
    expect(notice).toContain("Try again");
  });

  it("keeps narrow layouts bounded, inputs readable, motion optional, and styles Customer-scoped", () => {
    const css = readFileSync(new URL("./design/customer-experience.css", import.meta.url), "utf8");
    expect(css).toContain(".variant-dastak-customer,");
    expect(css).toContain("@media (max-width: 700px)");
    expect(css).toContain("@media (max-width: 370px)");
    expect(css).toContain("repeat(2, minmax(0, 1fr))");
    expect(css).toContain("overflow-wrap: anywhere");
    expect(css).toContain(".customer-experience :is(input, textarea, select) { font-size: 16px;");
    expect(css).toContain("prefers-reduced-motion: reduce");
    expect(css).toContain("prefers-color-scheme: dark");
    // Merchant and Delivery intentionally share exactly these token-only theme blocks.
    // Customer layout selectors must still never style another application.
    const sharedThemes = [...css.matchAll(/\.variant-dastak-merchant, \.variant-dastak-customer, \.variant-dastak-delivery \{([^}]+)\}/g)];
    expect(sharedThemes).toHaveLength(2);
    for (const [, declarations] of sharedThemes) {
      expect(declarations.split(";").map((line) => line.trim()).filter(Boolean).every((line) => line.startsWith("--"))).toBe(true);
    }
    const customerLayout = css.replace(/\.variant-dastak-merchant, \.variant-dastak-customer, \.variant-dastak-delivery \{[^}]+\}/g, "");
    expect(customerLayout).not.toMatch(/\.variant-dastak-(merchant|delivery|admin)/);
  });

  it("meets WCAG AA text contrast for the shared light and dark tokens", () => {
    const css = readFileSync(new URL("./design/customer-experience.css", import.meta.url), "utf8");
    const themes = [...css.matchAll(/\.variant-dastak-merchant, \.variant-dastak-customer, \.variant-dastak-delivery \{([^}]+)\}/g)];
    expect(themes).toHaveLength(2);
    for (const [, body] of themes) {
      const tokens = Object.fromEntries([...body.matchAll(/--([\w-]+):\s*(#[\da-f]{6})/g)].map(([, key, value]) => [key, value]));
      for (const surface of ["canvas", "surface", "surface-raised"]) {
        for (const text of ["text-primary", "text-secondary", "text-tertiary", "dastak-accent"]) {
          expect(contrast(tokens[text], tokens[surface]), `${text} on ${surface}`).toBeGreaterThanOrEqual(4.5);
        }
      }
      expect(contrast(tokens["primary-action-foreground"], tokens["primary-action"])).toBeGreaterThanOrEqual(4.5);
    }
  });
});

function contrast(a: string, b: string) {
  const luminance = (hex: string) => {
    const values = [1, 3, 5].map((offset) => parseInt(hex.slice(offset, offset + 2), 16) / 255)
      .map((channel) => channel <= .04045 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4);
    return values[0] * .2126 + values[1] * .7152 + values[2] * .0722;
  };
  const [lighter, darker] = [luminance(a), luminance(b)].sort((left, right) => right - left);
  return (lighter + .05) / (darker + .05);
}
