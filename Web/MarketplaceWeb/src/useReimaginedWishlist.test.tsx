// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { beforeEach, afterEach, expect, it, vi } from "vitest";
import { useReimaginedWishlist } from "./useReimaginedWishlist";
import { getCustomerWishlist, setCustomerWishlistItem } from "./customerWishlist";
vi.mock("./customerWishlist", () => ({ getCustomerWishlist: vi.fn(), setCustomerWishlistItem: vi.fn() }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement; let resource: ReturnType<typeof useReimaginedWishlist>;
function Harness({ account = "a", online = true }: { account?: string; online?: boolean }) {
  resource = useReimaginedWishlist({ accountId: account, accessToken: account, supabaseUrl: "https://test.supabase.co", publishableKey: "public" }, online);
  return <p>{JSON.stringify({ items: resource.items, ready: resource.ready, busy: resource.busy })}</p>;
}
beforeEach(() => { vi.clearAllMocks(); vi.mocked(getCustomerWishlist).mockResolvedValue({ items: [] }); host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); });
it("loads existing saved identities and performs writes only on explicit actions", async () => {
  await act(async () => root.render(<Harness />)); expect(resource.ready).toBe(true); expect(setCustomerWishlistItem).not.toHaveBeenCalled();
  vi.mocked(setCustomerWishlistItem).mockResolvedValue({ items: [{ kind: "RETAIL_SKU", itemId: "sku", createdAt: "today" }] });
  await act(async () => resource.toggle("RETAIL_SKU", "sku"));
  expect(resource.saved("RETAIL_SKU", "sku")).toBe(true);
  expect(setCustomerWishlistItem).toHaveBeenCalledWith(expect.objectContaining({ itemKind: "RETAIL_SKU", itemId: "sku", wished: true, accessToken: "a" }));
});
it("retries an ambiguous write with the same intent and request key", async () => {
  await act(async () => root.render(<Harness />));
  vi.mocked(setCustomerWishlistItem).mockRejectedValueOnce(new Error("timeout")).mockResolvedValueOnce({ items: [] });
  await act(async () => resource.toggle("MENU_ITEM", "dish")); await act(async () => resource.toggle("MENU_ITEM", "dish"));
  const calls = vi.mocked(setCustomerWishlistItem).mock.calls;
  expect(calls[0][0].idempotencyKey).toBe(calls[1][0].idempotencyKey); expect(calls[1][0].wished).toBe(true);
});
it("blocks offline writes and ignores late account responses", async () => {
  let finish!: (value: { items: [] }) => void;
  vi.mocked(getCustomerWishlist).mockReturnValueOnce(new Promise(resolve => { finish = resolve; }));
  await act(async () => root.render(<Harness />));
  await act(async () => root.render(<Harness account="b" online={false} />));
  await act(async () => finish({ items: [] })); expect(resource.ready).toBe(false);
  await act(async () => resource.toggle("RETAIL_SKU", "sku")); expect(setCustomerWishlistItem).not.toHaveBeenCalled();
});
