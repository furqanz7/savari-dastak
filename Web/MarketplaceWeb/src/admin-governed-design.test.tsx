// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { AdminCatalogueAssets } from "./AdminCatalogueAssets";
import { AdminCustomerRecoveryPanel } from "./AdminCustomerRecoveryPanel";
import { DastakV1RequestError, type V1AdminCataloguePageSku } from "./dastakV1";

const calls = vi.hoisted(() => ({ assets: vi.fn(), customers: vi.fn(), promote: vi.fn(), remove: vi.fn(), revoke: vi.fn() }));
vi.mock("./dastakV1", async (original) => ({ ...await original<typeof import("./dastakV1")>(),
  getV1AdminCatalogueAssets: calls.assets, getV1AdminCustomerRecoveryPage: calls.customers,
  promoteV1AdminCataloguePrimary: calls.promote, removeV1AdminCatalogueAsset: calls.remove,
  revokeV1AdminCustomerSessions: calls.revoke,
}));
(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
const auth = { accessToken: "test", supabaseUrl: "https://example.test", publishableKey: "test" };
const sku = { id: "sku-exact", name: "Exact long product name with a reviewed family variant", packSize: "500 g × 2" } as V1AdminCataloguePageSku;
let host: HTMLDivElement;
let root: Root;
beforeEach(() => { vi.clearAllMocks(); vi.useFakeTimers(); host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.useRealTimers(); });
const button = (text: string) => [...host.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent?.trim() === text)!;

it("asset disclosure preserves exact-SKU review and never removes the protected primary", async () => {
  calls.assets.mockResolvedValue({ sku: { ...sku, assetVersion: 4 }, assets: [
    { id: "primary-one", skuId: sku.id, role: "PRIMARY", status: "VERIFIED", rightsStatus: "CLEARED", imageKey: "one.png", sourceType: "MANUFACTURER", canRemove: false },
    { id: "gallery-two", skuId: sku.id, role: "GALLERY", status: "VERIFIED", rightsStatus: "CLEARED", imageKey: "two.png", sourceType: "MANUFACTURER", canRemove: true },
  ] });
  await act(async () => root.render(<AdminCatalogueAssets auth={auth} sku={sku} onCatalogueChanged={async () => undefined} />));
  expect(calls.assets.mock.calls[0][0].skuId).toBe("sku-exact");
  expect(host.querySelector("details")?.open).toBe(false);
  expect(host.querySelectorAll('input[type="file"]')).toHaveLength(1);
  expect(host.querySelector("article.primary")?.textContent).not.toContain("Remove");
  await act(async () => button("Make primary").click());
  expect(host.querySelector('[role="alertdialog"]')?.textContent).toContain(sku.name);
  expect(host.querySelector('[role="alertdialog"]')?.textContent).toContain("primary-one");
  expect(calls.promote).not.toHaveBeenCalled();
  await act(async () => button("Cancel").click());
  expect(host.querySelector('[role="alertdialog"]')).toBeNull();
  expect(calls.promote).not.toHaveBeenCalled();
  expect(calls.remove).not.toHaveBeenCalled();
});

it("permission-denied imagery shows a truthful restricted state without upload controls", async () => {
  calls.assets.mockRejectedValue(new DastakV1RequestError("access_denied", "Restricted", 403));
  await act(async () => root.render(<AdminCatalogueAssets auth={auth} sku={sku} onCatalogueChanged={async () => undefined} />));
  expect(host.textContent).toContain("Image management is restricted");
  expect(host.querySelector('input[type="file"]')).toBeNull();
  expect(host.textContent).not.toContain("No governed imagery");
});

it("customer progressive disclosure retains reviewed session controls and deliberate confirmation", async () => {
  calls.customers.mockResolvedValue({ customers: [{ account: { accountId: "customer-one", displayName: "Reviewed Customer", maskedPhoneNumber: "•••• 0123", currentPhoneNumber: "+919876540123", accountState: "ACTIVE" }, phoneClaim: { version: 3, state: "CLAIMED" }, identityProviders: ["apple"], activeSessionCount: 1, sessions: [{ sessionId: "session-reviewed", deviceName: "Reviewed browser", platform: "web", appName: "Customer", lastSeenAt: "2026-09-13T09:00:00Z" }], updatedAt: "2026-09-13T09:00:00Z" }], hasMore: false });
  await act(async () => { root.render(<AdminCustomerRecoveryPanel auth={auth} />); });
  await act(async () => vi.advanceTimersByTimeAsync(300));
  const details = host.querySelector("details")!;
  expect(details.open).toBe(false);
  await act(async () => details.querySelector("summary")!.click());
  expect(details.open).toBe(true);
  await act(async () => button("Revoke").click());
  const confirmation = host.querySelector('[role="alertdialog"]')!;
  expect(confirmation.textContent).toContain("Reviewed Customer");
  expect(confirmation.textContent).toContain("session-reviewed");
  expect(confirmation.textContent).toContain("authenticate again");
  expect(calls.revoke).not.toHaveBeenCalled();
  await act(async () => button("Cancel").click());
  expect(calls.revoke).not.toHaveBeenCalled();
  expect(details.open).toBe(true);
});
