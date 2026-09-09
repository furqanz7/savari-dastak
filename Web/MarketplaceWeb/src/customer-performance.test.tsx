import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { shouldMountV1CustomerExperience } from "./customerNavigation";
import { SearchSection } from "./DastakV1CustomerExperience";

describe("Customer Web rendering boundaries", () => {
  it("unmounts the V1 catalogue experience for other major sections", () => {
    expect(shouldMountV1CustomerExperience("home")).toBe(true);
    expect(shouldMountV1CustomerExperience("search")).toBe(true);
    expect(shouldMountV1CustomerExperience("orders")).toBe(true);
    expect(shouldMountV1CustomerExperience("account")).toBe(false);
    expect(shouldMountV1CustomerExperience("parcel")).toBe(false);
  });

  it("does not mount a product grid before the customer enters a search", () => {
    const markup = renderToStaticMarkup(<SearchSection
      supabaseUrl="https://example.supabase.co"
      query=""
      onQuery={() => undefined}
      searching={false}
      skus={[]}
      onAdd={() => undefined}
      wishlistIds={new Set()}
      wishlistUpdatingIds={new Set()}
      onWishlist={() => undefined}
    />);
    expect(markup).toContain("Start typing to find a product");
    expect(markup).not.toContain("v1-product-grid");
  });
});
