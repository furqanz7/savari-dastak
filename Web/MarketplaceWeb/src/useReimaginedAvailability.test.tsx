// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useReimaginedAvailability } from "./useReimaginedAvailability";
import type { V1AreaAvailability, V1RestaurantLocation } from "./dastakV1";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const home = { addressId: fixtureId(70), updatedAt: "2026-10-08T00:00:00Z" };
const snapshot = (location = home): V1AreaAvailability => ({ addressId: location.addressId, addressVersion: location.updatedAt, checkedAt: location.updatedAt,
  groceryServiceable: true, foodServiceable: true, deliveryAvailable: true, stock: { [fixtureId(6)]: 3 }, restaurants: {} });
type Loader = NonNullable<Parameters<typeof useReimaginedAvailability>[3]>;
let root: Root; let host: HTMLDivElement;
function Harness({ location = home, loader, online = true, token = "a" }: { location?: V1RestaurantLocation; loader: Loader; online?: boolean; token?: string }) {
  const resource = useReimaginedAvailability({ accountId: "a", accessToken: token, supabaseUrl: "https://example.invalid", publishableKey: "public" }, location, online, loader);
  return <output>{JSON.stringify({ status: resource.status, address: resource.data?.addressId, quantity: resource.data?.stock[fixtureId(6)] })}</output>;
}
function mount() { host = document.createElement("div"); document.body.append(host); root = createRoot(host); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); vi.useRealTimers(); });
describe("availability resource", () => {
  it("rejects late old-address replies and hides old-session stock immediately", async () => {
    mount(); let resolve!: (value: V1AreaAvailability) => void;
    const office = { ...home, addressId: fixtureId(71) };
    const loader = vi.fn<Loader>().mockReturnValueOnce(new Promise(yes => { resolve = yes; })).mockResolvedValueOnce(snapshot(office)).mockReturnValue(new Promise(() => {}));
    act(() => root.render(<Harness loader={loader} />));
    await act(async () => root.render(<Harness loader={loader} location={office} />));
    await act(async () => resolve(snapshot(home)));
    expect(host.textContent).toContain(office.addressId); expect(host.textContent).not.toContain(home.addressId);
    act(() => root.render(<Harness loader={loader} location={office} token="b" />));
    expect(host.textContent).not.toContain('"quantity"');
    expect(loader.mock.calls[0][0].signal?.aborted).toBe(true);
  });
  it("keeps reads batched, expires a stalled refresh, and hides stock offline", async () => {
    vi.useFakeTimers(); mount();
    const loader = vi.fn<Loader>().mockResolvedValueOnce(snapshot()).mockReturnValue(new Promise(() => {}));
    await act(async () => root.render(<Harness loader={loader} />));
    expect(loader).toHaveBeenCalledTimes(1); expect(host.textContent).toContain('"quantity":3');
    act(() => vi.advanceTimersByTime(30000)); expect(loader).toHaveBeenCalledTimes(2);
    expect(host.textContent).toContain('"quantity":3'); // No loading flash during a timely refresh.
    act(() => vi.advanceTimersByTime(30000)); expect(host.textContent).not.toContain('"quantity"');
    act(() => root.render(<Harness loader={loader} online={false} />)); expect(host.textContent).not.toContain('"quantity"');
  });
});
