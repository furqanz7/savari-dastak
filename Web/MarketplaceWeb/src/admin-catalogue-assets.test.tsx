import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("Admin catalogue asset governance", () => {
  it("is integrated only inside the exact-SKU editor and uses privileged mutation reconciliation", () => {
    const catalogue = readFileSync(new URL("./AdminCataloguePanel.tsx", import.meta.url), "utf8");
    const assets = readFileSync(new URL("./AdminCatalogueAssets.tsx", import.meta.url), "utf8");
    expect(catalogue).toContain("<AdminCatalogueAssets auth={auth} sku={sku}");
    expect(assets).toContain("runAdminPrivilegedMutation");
    expect(assets).toContain("expectedAssetVersion: snapshot.sku.assetVersion");
    expect(assets).toContain("expectedPrimaryAssetId: primary?.id");
    expect(assets).toContain("validateDecodableImage(selected, 5 * 1024 * 1024)");
  });

  it("never offers direct primary deletion or a browser-selected object path", () => {
    const assets = readFileSync(new URL("./AdminCatalogueAssets.tsx", import.meta.url), "utf8");
    expect(assets).toContain('asset.role === "PRIMARY" || !asset.canRemove');
    expect(assets).not.toContain("storageObjectPath");
    expect(assets).not.toContain("service_role");
    expect(assets).not.toContain("SUPABASE_SERVICE_ROLE_KEY");
  });

  it("keeps the asset workspace responsive without horizontal overflow", () => {
    const styles = readFileSync(new URL("./design/v1-admin.css", import.meta.url), "utf8");
    expect(styles).toContain(".admin-asset-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(270px, 1fr))");
    expect(styles).toContain(".admin-asset-grid article { display: grid; grid-template-columns: 112px minmax(0, 1fr); min-width: 0; overflow: hidden;");
    expect(styles).toContain(".admin-asset-upload { grid-template-columns: 1fr;");
  });
});
