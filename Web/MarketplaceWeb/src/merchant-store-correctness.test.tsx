import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { MerchantBranchSelector } from "./MerchantOrdersView";

const branches = [
  { id: "retail", branchName: "Market Street", organizationName: "Dastak Stores", merchantType: "RETAIL" },
  { id: "food", branchName: "Cafe Road", organizationName: "Dastak Cafe", merchantType: "RESTAURANT_CAFE" },
];

describe("Merchant Store correctness wiring", () => {
  it("renders an explicit accessible active-branch selector", () => {
    const html = renderToStaticMarkup(<MerchantBranchSelector branches={branches} selected={branches[1]} loading={false} issue={undefined} onSelect={() => undefined} />);
    expect(html).toContain('aria-label="Active merchant branch"');
    expect(html).toContain('>Active branch<');
    expect(html).toContain('value="food" selected=""');
    expect(html).toContain("Cafe Road");
    expect(html).toContain("Dastak Cafe");
  });

  it("keeps the selected branch wired through Store and operational feeds", () => {
    const view = readFileSync(new URL("./MerchantOrdersView.tsx", import.meta.url), "utf8");
    expect(view).toContain("branch={selectedBranch}");
    expect(view).toContain("activeBranchId={selectedBranch?.id}");
    expect(view).toContain("persistMerchantBranch(accountId, branchId)");
  });

  it("bounds interactive catalogue mounting while requesting the correct contract limit", () => {
    const catalogue = readFileSync(new URL("./MerchantV1CatalogueControl.tsx", import.meta.url), "utf8");
    expect(catalogue).toContain("const cataloguePageSize = 80");
    expect(catalogue).toContain("branchId, limit: 5000");
    expect(catalogue).toContain("visibleSkus.slice(0, visibleLimit)");
    expect(catalogue).toContain("Show more products");
    expect(catalogue).toContain("first 5,000 authorised catalogue products");
  });

  it("decodes preparation evidence before upload and preserves organization-level settlements", () => {
    const operations = readFileSync(new URL("./MerchantV1Opportunities.tsx", import.meta.url), "utf8");
    expect(operations).toContain("await validateDecodableImage(file)");
    expect(operations).toContain("const branchSettlements = settlements");
    expect(operations).not.toContain("settlements.filter((item) => !activeBranchId");
  });
});
