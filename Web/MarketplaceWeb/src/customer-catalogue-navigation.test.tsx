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
    expect(html).not.toContain("sku-packshot.png");
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
    expect(html).toContain("Toned milk</strong>");
    expect(html).toContain('aria-pressed="true"');
    expect(html).not.toContain("Everyday essentials");
  });

  it("filters products in place without changing the sibling rail", () => {
    const html = renderToStaticMarkup(<HomeSection {...props} selectedCategoryType="dairy" selectedCategory="milk" selectedSubcategory="toned" />);
    expect(html).toContain("toned product");
    expect(html).not.toContain("full product");
    expect(html).toContain("Bread &amp; Buns");
    expect(html).toMatch(/class="selected" aria-pressed="true"[^>]*>.*?<strong>Toned milk<\/strong>/);
  });

  it("keeps a Masalas rail target under its canonical Masalas heading", () => {
    const html = renderToStaticMarkup(<HomeSection
      {...props}
      categoryTypes={[
        { id: "masalas", name: "Masala & Cooking", slug: "masala-cooking", sortOrder: 0, previewImageKeys: [] },
        { id: "staples", name: "Staples & Pantry", slug: "staples-pantry", sortOrder: 1, previewImageKeys: [] },
      ]}
      categories={[{ id: "sugar", categoryTypeId: "masalas", name: "Sugar and Jaggery", slug: "sugar-sweeteners", sortOrder: 0, previewImageKeys: [] }]}
      subcategories={[]}
      skus={[]}
      selectedCategoryType="masalas"
      selectedCategory="sugar"
      selectedRailLabel="Sugar and Jaggery"
    />);
    expect(html).toContain("<h2>Masalas</h2>");
    expect(html).toContain("<h3>Sugar and Jaggery</h3>");
    expect(html).toContain("0 products");
    expect(html).toContain("Sugar and Jaggery</strong>");
    expect(html).not.toContain("Atta, Flour &amp; Dal");
  });

  it("does not turn a display label into a global subcategory filter", () => {
    const html = renderToStaticMarkup(<HomeSection {...props} selectedCategoryType="dairy" selectedCategory="milk" selectedRailLabel="Toned milk" />);
    expect(html).toContain("toned product");
    expect(html).toContain("full product");
  });

  it("shows unresolved reference rails as empty instead of matching an unrelated category", () => {
    const html = renderToStaticMarkup(<HomeSection
      {...props}
      categoryTypes={[{ id: "masalas", name: "Masala & Cooking", slug: "masala-cooking", sortOrder: 0, previewImageKeys: [] }]}
      categories={[{ id: "leafy", categoryTypeId: "fresh", name: "Leafy and Seasonings", slug: "leafy-greens-herbs", sortOrder: 0, previewImageKeys: [] }]}
      subcategories={[]}
      selectedCategoryType="masalas"
      selectedRailLabel="Herbs & Seasoning"
      selectedCategory={undefined}
    />);
    expect(html).toContain("Herbs &amp; Seasoning</strong>");
    expect(html).toMatch(/<button[^>]*disabled=""[^>]*>[\s\S]*?Herbs &amp; Seasoning<\/strong>/);
    expect(html).toContain("Cold Grind</strong>");
    expect(html).toContain("<h3>Herbs &amp; Seasoning</h3>");
    expect(html).toContain("0 products");
    expect(html).not.toContain("toned product");
  });

  it("does not repeat Basmati SKUs in the broad Rice rail", () => {
    const riceProps = {
      ...props,
      categoryTypes: [{ id: "staples", name: "Staples & Pantry", slug: "staples-pantry", sortOrder: 0, previewImageKeys: [] }],
      categories: [{ id: "rice", categoryTypeId: "staples", name: "Rice", slug: "rice", sortOrder: 0, previewImageKeys: [] }],
      subcategories: [
        { id: "basmati", categoryId: "rice", name: "Basmati Rice", slug: "basmati-rice", sortOrder: 0, previewImageKeys: [] },
        { id: "ponni", categoryId: "rice", name: "Ponni Rice", slug: "ponni-rice", sortOrder: 1, previewImageKeys: [] },
      ],
      skus: props.skus.map((sku, index) => ({ ...sku, categoryId: "rice", subcategoryId: index ? "ponni" : "basmati", name: index ? "Ponni bag" : "Basmati bag" })),
      selectedCategoryType: "staples",
      selectedCategory: "rice",
    };
    const broad = renderToStaticMarkup(<HomeSection {...riceProps} selectedRailLabel="Rice" />);
    expect(broad).toContain("Ponni bag");
    expect(broad).not.toContain("Basmati bag");
    const basmati = renderToStaticMarkup(<HomeSection {...riceProps} selectedRailLabel="Basmati Rice" selectedSubcategory="basmati" />);
    expect(basmati).toContain("Basmati bag");
    expect(basmati).not.toContain("Ponni bag");
  });

  it("opens Oils and Ghee as its own department with both categories", () => {
    const html = renderToStaticMarkup(<HomeSection
      {...props}
      categoryTypes={[{ id: "oils-type", name: "Oils and Ghee", slug: "oils-ghee", sortOrder: 0, previewImageKeys: [] }]}
      categories={[
        { id: "oils", categoryTypeId: "oils-type", name: "Cooking Oils", slug: "cooking-oils", sortOrder: 0, previewImageKeys: [] },
        { id: "ghee", categoryTypeId: "oils-type", name: "Ghee", slug: "ghee", sortOrder: 1, previewImageKeys: [] },
      ]}
      subcategories={[{ id: "sunflower", categoryId: "oils", name: "Sunflower Oil", slug: "sunflower-oil", sortOrder: 0, previewImageKeys: [] }]}
      skus={[]}
      selectedCategoryType="oils-type"
      selectedCategory="oils"
      selectedHomeTile={{ label: "Oils and Ghee" }}
    />);
    expect(html).toContain("<h2>Oils and Ghee</h2>");
    expect(html).toContain("<h3>Cooking Oils</h3>");
    expect(html).toContain("Sunflower Oil</strong>");
    expect(html).toContain("Ghee</strong>");
    expect(html).not.toContain("Basmati Rice</strong>");
  });
});
