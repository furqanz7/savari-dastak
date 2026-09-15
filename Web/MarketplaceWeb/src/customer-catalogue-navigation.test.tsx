import type { ComponentProps } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { HomeSection } from "./DastakV1CustomerExperience";

const noop = () => undefined;
const props: ComponentProps<typeof HomeSection> = {
  supabaseUrl: "https://example.supabase.co",
  restaurants: [],
  categoryTypes: [{ id: "dairy", name: "Dairy, Bread & Eggs", slug: "dairy", sortOrder: 0, imageKey: "canonical/taxonomy/category_type/dairy.webp", previewImageKeys: ["catalogue/sku-packshot.png"], navigationSection: { key: "grocery", name: "Grocery & Kitchen", sortOrder: 0 } }],
  categories: [
    { id: "milk", categoryTypeId: "dairy", name: "Milk", slug: "milk", sortOrder: 0, previewImageKeys: ["catalogue/milk.webp"] },
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
  onAdd: noop, onRestaurant: noop, onWishlist: noop,
  wishlistIds: new Set(), wishlistUpdatingIds: new Set(),
};

describe("two-level customer catalogue", () => {
  it("uses an initial skeleton, and keeps existing categories visible during a scoped refresh failure", () => {
    const loading = renderToStaticMarkup(<HomeSection {...props} loadingCatalogue />);
    expect(loading).toContain("Opening Dastak catalogue");
    expect(loading).not.toContain("v1-product-grid");
    const failed = renderToStaticMarkup(<HomeSection {...props} catalogueIssue="Connection unavailable" onRetryCatalogue={noop} />);
    expect(failed).toContain("Products couldn’t update");
    expect(failed).toContain("Try again");
    expect(failed).toContain("Grocery &amp; Kitchen");
  });
  it("shows broad category tiles under section headings", () => {
    const html = renderToStaticMarkup(<HomeSection {...props} />);
    expect(html).toContain('aria-label="Shop by service"');
    expect(html).toContain(">Food<");
    expect(html).toContain(">Grocery<");
    expect(html).toContain(">Parcel<");
    expect(html).toContain(">Print<");
    expect(html).toContain("Grocery &amp; Kitchen");
    expect(html).toContain("Dairy, Bread &amp; Eggs");
    expect(html).toContain("canonical/taxonomy/category_type/dairy.webp");
    expect(html).toContain("sku-packshot.png");
    expect(html).not.toContain(">Milk<");
    expect(html).not.toContain("v1-category-browser");
  });

  it("keeps Food focused on restaurant discovery and Parcel and Print honest", () => {
    const food = renderToStaticMarkup(<HomeSection {...props} mode="food" />);
    expect(food).toContain("FOOD, MADE NEARBY");
    expect(food).not.toContain("SHOP DASTAK");
    expect(food).not.toContain("Everyday essentials");
    const parcel = renderToStaticMarkup(<HomeSection {...props} mode="parcel" />);
    expect(parcel).toContain("COMING SOON");
    expect(parcel).toContain("Send it with Dastak");
    const print = renderToStaticMarkup(<HomeSection {...props} mode="print" />);
    expect(print).toContain("Print, without the errand");
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
    expect(html).toContain("catalogue/milk.webp");
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
