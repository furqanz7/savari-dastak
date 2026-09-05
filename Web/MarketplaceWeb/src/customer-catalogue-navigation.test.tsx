import type { ComponentProps } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { HomeSection } from "./DastakV1CustomerExperience";

const noop = () => undefined;
const props: ComponentProps<typeof HomeSection> = {
  supabaseUrl: "https://example.supabase.co",
  restaurants: [],
  categoryTypes: [{ id: "dairy", name: "Dairy, Bread & Eggs", slug: "dairy", sortOrder: 0, previewImageKeys: [], navigationSection: { key: "grocery", name: "Grocery & Kitchen", sortOrder: 0 } }],
  categories: [
    { id: "milk", categoryTypeId: "dairy", name: "Milk", slug: "milk", sortOrder: 0, previewImageKeys: [] },
    { id: "bread", categoryTypeId: "dairy", name: "Bread & Buns", slug: "bread", sortOrder: 1, previewImageKeys: [] },
  ],
  subcategories: [
    { id: "toned", categoryId: "milk", name: "Toned milk", slug: "toned", sortOrder: 0, previewImageKeys: [] },
    { id: "full", categoryId: "milk", name: "Full cream milk", slug: "full", sortOrder: 1, previewImageKeys: [] },
  ],
  skus: ["toned", "full"].map((id) => ({
    id, categoryId: "milk", subcategoryId: id, name: `${id} product`, slug: id,
    packSize: "500 ml", galleryImageKeys: [], attributes: {}, logisticsAttributes: {},
    listPricePaise: 3000, sellingPricePaise: 3000, currencyCode: "INR",
  })),
  loadingProducts: false,
  onCategoryType: noop, onCategory: noop, onSubcategory: noop, onOrders: noop,
  onParcel: noop, onAdd: noop, onRestaurant: noop, onWishlist: noop,
  wishlistIds: new Set(), wishlistUpdatingIds: new Set(),
};

describe("two-level customer catalogue", () => {
  it("shows broad category tiles under section headings", () => {
    const html = renderToStaticMarkup(<HomeSection {...props} />);
    expect(html).toContain("Grocery &amp; Kitchen");
    expect(html).toContain("Dairy, Bread &amp; Eggs");
    expect(html).not.toContain(">Milk<");
    expect(html).not.toContain("v1-category-browser");
  });

  it("shows products and sibling subcategories together with finer choices in a filter", () => {
    const html = renderToStaticMarkup(<HomeSection {...props} selectedCategoryType="dairy" selectedCategory="milk" />);
    expect(html).toContain("v1-category-browser");
    expect(html).not.toContain("v1-category-grid");
    expect(html).toContain(">Milk<");
    expect(html).toContain("Bread &amp; Buns");
    expect(html).toContain("toned product");
    expect(html).toContain("full product");
    expect(html).toContain('<option value="toned">Toned milk</option>');
    expect(html).toContain('aria-pressed="true"');
    expect(html).not.toContain("Everyday essentials");
  });

  it("filters products in place without changing the sibling rail", () => {
    const html = renderToStaticMarkup(<HomeSection {...props} selectedCategoryType="dairy" selectedCategory="milk" selectedSubcategory="toned" />);
    expect(html).toContain("toned product");
    expect(html).not.toContain("full product");
    expect(html).toContain("Bread &amp; Buns");
    expect(html).toContain('value="toned" selected=""');
  });
});
