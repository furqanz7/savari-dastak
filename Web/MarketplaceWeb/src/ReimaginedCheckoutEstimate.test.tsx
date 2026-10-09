// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ReimaginedCheckoutEstimate } from "./ReimaginedCheckoutEstimate";
import { useCheckoutEstimate } from "./useCheckoutEstimate";
import type { V1CheckoutQuote } from "./dastakV1";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const home = { addressId: fixtureId(70), updatedAt: "2026-10-09T00:00:00Z" };
const auth = { accessToken: "test", supabaseUrl: "https://example.invalid", publishableKey: "public" };
const snapshot = (): V1CheckoutQuote => ({ kind: "ESTIMATE", currencyCode: "INR", checkedAt: new Date().toISOString(),
  validUntil: new Date(Date.now()+45000).toISOString(), subtotalPaise: 10000, deliveryFeePaise: 1500,
  platformFeePaise: 230, taxPaise: 0, discountPaise: 0, totalPaise: 11730, deliveryAvailable: false });
type Loader = NonNullable<Parameters<typeof useCheckoutEstimate>[6]>;
let root: Root; let host: HTMLDivElement;
function Harness({ loader, location = home, token = "test", quantity = 1, online = true, enabled = true }: {
  loader: Loader; location?: typeof home; token?: string; quantity?: number; online?: boolean; enabled?: boolean;
}) {
  const resource = useCheckoutEstimate({ ...auth, accessToken: token }, location,
    [{ lineType: "RETAIL_SKU", skuId: fixtureId(6), quantity }], undefined, online, enabled, loader);
  return <><output>{JSON.stringify({ status: resource.status, total: resource.data?.totalPaise })}</output><button onClick={resource.retry}>Retry</button></>;
}
function mount() { vi.useFakeTimers(); host = document.createElement("div"); document.body.append(host); root = createRoot(host); }
async function tick(ms = 250) { await act(async () => { vi.advanceTimersByTime(ms); }); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); vi.useRealTimers(); vi.unstubAllGlobals(); });
describe("checkout estimate lifecycle", () => {
  it("debounces a whole basket and never fetches while hidden, offline or unconfigured", async () => {
    mount(); const loader = vi.fn<Loader>().mockResolvedValue(snapshot());
    act(() => root.render(<Harness loader={loader} enabled={false} />)); await tick(1000); expect(loader).not.toHaveBeenCalled();
    act(() => root.render(<Harness loader={loader} />)); await tick(100);
    act(() => root.render(<Harness loader={loader} quantity={2} />)); await tick();
    expect(loader).toHaveBeenCalledTimes(1); expect(loader.mock.calls[0][0].lines[0].quantity).toBe(2);
    act(() => root.render(<Harness loader={loader} online={false} />)); expect(host.textContent).not.toContain('"total"');
    await tick(1000); expect(loader).toHaveBeenCalledTimes(1);
  });
  it("aborts and rejects late replies after cart, address/version or session changes", async () => {
    mount(); let resolve!: (value: V1CheckoutQuote) => void;
    const loader = vi.fn<Loader>().mockReturnValueOnce(new Promise(yes => { resolve = yes; })).mockReturnValue(new Promise(() => {}));
    act(() => root.render(<Harness loader={loader} />)); await tick();
    act(() => root.render(<Harness loader={loader} location={{ ...home, updatedAt: "2026-10-09T00:01:00Z" }} />));
    expect(loader.mock.calls[0][0].signal?.aborted).toBe(true);
    await act(async () => resolve(snapshot())); expect(host.textContent).not.toContain('"total"');
    await tick(); act(() => root.render(<Harness loader={loader} token="other-account" />)); expect(host.textContent).not.toContain('"total"');
  });
  it("expires successful estimates and recovers failed estimates with one explicit retry", async () => {
    mount(); const loader = vi.fn<Loader>().mockResolvedValueOnce(snapshot()).mockRejectedValueOnce(new Error("offline")).mockImplementation(async () => snapshot());
    act(() => root.render(<Harness loader={loader} />)); await tick(); expect(host.textContent).toContain('"total":11730');
    await tick(45000); expect(host.textContent).not.toContain('"total"'); expect(host.textContent).toContain("unavailable");
    act(() => host.querySelector("button")!.click()); await tick(); expect(host.textContent).toContain("unavailable");
    act(() => host.querySelector("button")!.click()); await tick(); expect(host.textContent).toContain('"total":11730');
    expect(loader).toHaveBeenCalledTimes(3);
  });
  it("renders separate numeric fees and total, while keeping missing fees distinct from zero", async () => {
    mount(); const now = new Date().toISOString(); const lines = [{ lineType: "RETAIL_SKU" as const, skuId: fixtureId(6), quantity: 1 }];
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ ...snapshot(), addressId: home.addressId, addressVersion: home.updatedAt,
      lines, restaurantBranchId: null, pricingVersion: 1, deliveryDistanceMeters: 1000, checkedAt: now })));
    act(() => root.render(<ReimaginedCheckoutEstimate auth={auth} location={home} lines={lines} online />));
    expect(host.textContent).toContain("Not confirmed"); expect(host.textContent).not.toContain("₹0.00");
    expect(host.textContent).toContain("Platform fee"); expect(host.textContent).not.toContain("2%");
    await tick();
    expect(host.textContent).toContain("Delivery₹15.00"); expect(host.textContent).toContain("Platform fee₹2.30");
    expect(host.textContent).toContain("Estimated total₹117.30"); expect(host.textContent).toContain("No delivery partner");
    expect(host.querySelector("p")?.textContent).toBe("Tax is included");
    expect(host.textContent).not.toContain("2%"); expect(host.textContent).not.toContain("merchant pickup locations");
    expect(host.textContent).not.toContain("secured order bill");
  });
});
