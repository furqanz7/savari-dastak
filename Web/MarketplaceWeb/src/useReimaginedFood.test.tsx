// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { V1RestaurantLocation, V1RestaurantMenu, V1RestaurantPage } from "./dastakV1";
import { useReimaginedFood } from "./useReimaginedFood";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
type Loader = NonNullable<Parameters<typeof useReimaginedFood>[3]>;
let root: Root; let host: HTMLDivElement;
const page = (restaurants: V1RestaurantMenu[], nextCursor?: V1RestaurantPage["nextCursor"]) => ({ restaurants, nextCursor });
function Harness({ loader, enabled = true, online = true, token = "token", account = "a", query = "", location }: { loader: Loader; enabled?: boolean; online?: boolean; token?: string; account?: string; query?: string; location?: V1RestaurantLocation }) {
  const result = useReimaginedFood({ accountId: account, accessToken: token, supabaseUrl: "https://example.supabase.co", publishableKey: "test" }, enabled, online, loader, query, location);
  return <><output>{JSON.stringify({ status: result.status, count: result.data?.length, more: result.hasMore, matches: result.searchData?.length })}</output><button onClick={result.retry}>Retry</button><button onClick={() => void result.loadMore?.()}>More</button><button onClick={() => result.rememberRestaurant?.(foodMenuFixture(fixtureId(999)))}>Remember</button></>;
}
function mount(loader: Loader, enabled = true, online = true) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness loader={loader} enabled={enabled} online={online} />)); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Food session resource", () => {
  it("retains a selected server menu for details and cart without changing the current page or fetching again", async () => {
    const loader = vi.fn().mockResolvedValue(page([foodMenuFixture()])); mount(loader); await act(async () => {});
    act(() => host.querySelectorAll('button')[2].click());
    expect(host.textContent).toContain('"count":2'); expect(host.textContent).toContain('"matches":1'); expect(loader).toHaveBeenCalledOnce();
    act(() => root.render(<Harness loader={loader} token="other" enabled={false} />));
    act(() => host.querySelectorAll('button')[2].click()); expect(host.textContent).not.toContain('"count":2');
  });
  it("scopes distance reads and cursors to the selected address, rejecting late old-location replies", async () => {
    const home = { addressId: fixtureId(70), updatedAt: "2026-10-08T00:00:00Z" };
    const office = { ...home, addressId: fixtureId(71) };
    let resolve!: (data: V1RestaurantPage) => void;
    const cursor = { name: "Cafe", branchId: fixtureId(30), addressId: office.addressId, addressVersion: office.updatedAt, distanceMeters: 800 };
    const loader = vi.fn().mockResolvedValueOnce(page([])).mockReturnValueOnce(new Promise<V1RestaurantPage>(yes => { resolve = yes; }))
      .mockResolvedValue({ ...page([foodMenuFixture(fixtureId(999))], cursor), ordering: "NEAREST" });
    mount(loader); await act(async () => {});
    act(() => root.render(<Harness loader={loader} location={home} />));
    await act(async () => root.render(<Harness loader={loader} location={office} />));
    expect(loader.mock.calls[1][0].signal.aborted).toBe(true);
    await act(async () => resolve({ ...page([foodMenuFixture(), foodMenuFixture(fixtureId(800))]), ordering: "NEAREST" }));
    expect(host.textContent).toContain('"count":1');
    await act(async () => host.querySelectorAll('button')[1].click());
    expect(loader.mock.calls[3][0]).toMatchObject({ location: office, cursor });
    expect(loader.mock.calls[3][0]).not.toHaveProperty("latitude");
    expect(loader.mock.calls[3][0]).not.toHaveProperty("longitude");
    await act(async () => root.render(<Harness loader={loader} location={{ ...office, updatedAt: "2026-10-09T00:00:00Z" }} />));
    expect(loader.mock.calls[4][0].cursor).toBeUndefined();
  });
  it("does not label an unverified alphabetical response as nearest", async () => {
    const loader = vi.fn().mockResolvedValue(page([foodMenuFixture()])); mount(loader, false);
    await act(async () => root.render(<Harness loader={loader} location={{ addressId: fixtureId(70), updatedAt: "2026-10-08T00:00:00Z" }} />));
    expect(host.textContent).toContain("unavailable"); expect(host.textContent).not.toContain('"count":1');
  });
  it("loads only on Food entry and reuses the same-session in-memory result", async () => {
    const loader = vi.fn().mockResolvedValue(page([foodMenuFixture()])); mount(loader, false); expect(loader).not.toHaveBeenCalled();
    await act(async () => root.render(<Harness loader={loader} />)); expect(loader).toHaveBeenCalledOnce();
    expect(loader).toHaveBeenCalledWith(expect.objectContaining({ accessToken: "token", limit: 100, signal: expect.any(AbortSignal) }));
    act(() => root.render(<Harness loader={loader} enabled={false} />));
    await act(async () => root.render(<Harness loader={loader} />)); expect(loader).toHaveBeenCalledOnce();
    expect(host.textContent).toContain('"count":1');
  });
  it("cancels unfinished requests on exit and rejects late account responses", async () => {
    let resolve!: (data: V1RestaurantPage) => void;
    const loader = vi.fn().mockReturnValueOnce(new Promise<V1RestaurantPage>(yes => { resolve = yes; })).mockResolvedValue(page([]));
    mount(loader); act(() => root.render(<Harness loader={loader} account="b" />)); expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
    await act(async () => resolve(page([foodMenuFixture()]))); expect(host.textContent).toContain('"count":0');
    expect(host.textContent).not.toContain('"count":1');
  });
  it("hides previous menus immediately on token rotation", async () => {
    const loader = vi.fn().mockResolvedValueOnce(page([foodMenuFixture()])).mockReturnValue(new Promise(() => {}));
    mount(loader); await act(async () => {}); act(() => root.render(<Harness loader={loader} token="rotated" />));
    expect(host.textContent).not.toContain('"count":1'); expect(host.textContent).toContain("loading");
  });
  it("does not fetch offline and preserves cached menus for browsing", async () => {
    const loader = vi.fn().mockResolvedValue(page([foodMenuFixture()])); mount(loader, true, false); expect(loader).not.toHaveBeenCalled();
    await act(async () => root.render(<Harness loader={loader} />));
    act(() => root.render(<Harness loader={loader} online={false} />)); expect(host.textContent).toContain('"count":1'); expect(loader).toHaveBeenCalledOnce();
  });
  it("retries failure and rejects ambiguous catalogue data", async () => {
    const menu = foodMenuFixture(); const loader = vi.fn().mockResolvedValueOnce(page([menu, menu])).mockResolvedValue(page([]));
    mount(loader); await act(async () => {}); expect(host.textContent).toContain("unavailable");
    await act(async () => host.querySelector("button")!.click()); expect(host.textContent).toContain("ready"); expect(loader).toHaveBeenCalledTimes(2);
  });
  it("aborts a pending read when returning to Grocery", () => {
    const loader = vi.fn().mockReturnValue(new Promise(() => {})); mount(loader);
    act(() => root.render(<Harness loader={loader} enabled={false} />)); expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
  });
  it("loads beyond 100 only on explicit paging and retains loaded menus on a failed page", async () => {
    const menus = Array.from({ length: 100 }, (_, i) => foodMenuFixture(fixtureId(i + 100)));
    const cursor = { name: "Test", branchId: menus[99].restaurant.branchId };
    const loader = vi.fn().mockResolvedValueOnce(page(menus, cursor)).mockRejectedValueOnce(new Error("network")).mockResolvedValueOnce(page([foodMenuFixture(fixtureId(999))]));
    mount(loader); await act(async () => {}); expect(loader).toHaveBeenCalledOnce(); expect(host.textContent).toContain('"count":100');
    await act(async () => host.querySelectorAll('button')[1].click()); expect(host.textContent).toContain('"count":100');
    await act(async () => host.querySelectorAll('button')[1].click()); expect(host.textContent).toContain('"count":101');
    expect(loader.mock.calls[1][0].cursor).toEqual(cursor); expect(loader.mock.calls[2][0].cursor).toEqual(cursor);
  });
  it("submits global search queries, caches query pages and rejects non-advancing cursors", async () => {
    const cursor = { name: "Cafe", branchId: fixtureId(30) };
    const loader = vi.fn().mockResolvedValueOnce(page([foodMenuFixture()])).mockResolvedValue(page([foodMenuFixture()], cursor));
    mount(loader); await act(async () => {});
    await act(async () => root.render(<Harness loader={loader} query="cappuccino" />));
    expect(loader.mock.calls[1][0].query).toBe("cappuccino");
    await act(async () => host.querySelectorAll('button')[1].click()); expect(host.textContent).toContain('"count":1');
    await act(async () => root.render(<Harness loader={loader} />)); expect(loader).toHaveBeenCalledTimes(3);
  });
});
