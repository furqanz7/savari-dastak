// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useReimaginedFoodSearch } from "./useReimaginedFoodSearch";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
import type { V1RestaurantPage } from "./dastakV1";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
type Loader = NonNullable<Parameters<typeof useReimaginedFoodSearch>[5]>;
const home = { addressId: fixtureId(70), updatedAt: "2026-10-09T00:00:00Z" };
let root: Root; let host: HTMLDivElement;
function Harness({ loader, query = "rice", enabled = true, online = true, token = "t", account = "a", address = home.addressId, version = home.updatedAt, backend = "https://example.supabase.co", located = true }: { loader: Loader; query?: string; enabled?: boolean; online?: boolean; token?: string; account?: string; address?: string; version?: string; backend?: string; located?: boolean }) {
  const result = useReimaginedFoodSearch({ accountId: account, accessToken: token, supabaseUrl: backend, publishableKey: "test" }, query, enabled, online, located ? { addressId: address, updatedAt: version } : undefined, loader);
  return <><output>{JSON.stringify({ ids: result.menus?.map(menu => menu.restaurant.branchId), more: result.more, loading: result.loading, error: Boolean(result.error) })}</output><button onClick={result.retry}>Retry</button></>;
}
const page = (): V1RestaurantPage => ({ restaurants: [foodMenuFixture(fixtureId(999))], ordering: "NEAREST", nextCursor: { name: "Next", branchId: fixtureId(998) } });
function render(props: Parameters<typeof Harness>[0]) { act(() => root.render(<Harness {...props} />)); }
async function tick(ms = 300) { await act(async () => { await vi.advanceTimersByTimeAsync(ms); }); }
beforeEach(() => { vi.useFakeTimers(); host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); vi.useRealTimers(); });
describe("regional Food typing search", () => {
  it("debounces rapid typing into one bounded regional request without fetching more pages", async () => {
    const loader = vi.fn().mockResolvedValue(page());
    render({ loader, query: "r" }); await tick(200); render({ loader, query: "ri" }); await tick(200); render({ loader, query: " rice " }); await tick(299);
    expect(loader).not.toHaveBeenCalled(); await tick(1);
    expect(loader).toHaveBeenCalledOnce(); expect(loader).toHaveBeenCalledWith(expect.objectContaining({ query: "rice", limit: 8, location: home, signal: expect.any(AbortSignal) }));
    expect(loader.mock.calls[0][0].cursor).toBeUndefined(); expect(host.textContent).toContain(fixtureId(999)); expect(host.textContent).toContain('"more":true');
  });
  it("cancels old-query replies even when the loader ignores its abort signal", async () => {
    let finish!: (result: V1RestaurantPage) => void;
    const loader = vi.fn().mockReturnValueOnce(new Promise<V1RestaurantPage>(resolve => { finish = resolve; })).mockResolvedValue({ restaurants: [], ordering: "NEAREST" });
    render({ loader }); await tick(); render({ loader, query: "coffee" }); expect(loader.mock.calls[0][0].signal.aborted).toBe(true); await tick();
    await act(async () => finish(page())); expect(host.textContent).toContain('"ids":[]'); expect(host.textContent).not.toContain(fixtureId(999));
  });
  it.each([
    { account: "b" }, { token: "new" }, { backend: "https://other.supabase.co" }, { address: fixtureId(71) }, { version: "2026-10-10T00:00:00Z" },
  ])("hides cached results immediately across owner or region changes: %j", async change => {
    const loader = vi.fn().mockResolvedValueOnce(page()).mockReturnValue(new Promise(() => {})); render({ loader }); await tick();
    expect(host.textContent).toContain(fixtureId(999)); render({ loader, ...change }); expect(host.textContent).not.toContain(fixtureId(999)); await tick();
    expect(loader).toHaveBeenCalledTimes(2);
  });
  it("aborts an old-address reply and does not publish it into the new region", async () => {
    let finish!: (result: V1RestaurantPage) => void;
    const loader = vi.fn().mockReturnValueOnce(new Promise<V1RestaurantPage>(resolve => { finish = resolve; })).mockResolvedValue({ restaurants: [], ordering: "NEAREST" });
    render({ loader }); await tick(); render({ loader, address: fixtureId(71) }); await tick();
    expect(loader.mock.calls[0][0].signal.aborted).toBe(true); await act(async () => finish(page())); expect(host.textContent).toContain('"ids":[]');
  });
  it("does no reads while closed, offline, unlocated or blank and aborts on exit", async () => {
    const loader = vi.fn().mockReturnValue(new Promise(() => {}));
    for (const options of [{ enabled: false }, { online: false }, { located: false }, { query: " " }]) { render({ loader, ...options }); await tick(); }
    expect(loader).not.toHaveBeenCalled(); render({ loader }); await tick(); render({ loader, enabled: false }); expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
  });
  it("reuses fresh queries, expires them after a minute and evicts beyond eight queries", async () => {
    const loader = vi.fn().mockResolvedValue(page()); render({ loader }); await tick(); render({ loader, query: "coffee" }); await tick(); render({ loader }); await tick(); expect(loader).toHaveBeenCalledTimes(2);
    await tick(60_001); render({ loader, enabled: false }); render({ loader }); await tick(); expect(loader).toHaveBeenCalledTimes(3);
    for (let index = 0; index < 8; index++) { render({ loader, query: `dish${index}` }); await tick(); }
    render({ loader }); await tick(); expect(loader).toHaveBeenCalledTimes(12);
  });
  it("rejects ambiguous or unverified menus, supports retry and bounds query length", async () => {
    const menu = foodMenuFixture(); const loader = vi.fn().mockResolvedValueOnce({ restaurants: [menu], ordering: undefined }).mockResolvedValueOnce({ restaurants: [menu, menu], ordering: "NEAREST" }).mockResolvedValue(page());
    render({ loader }); await tick(); expect(host.textContent).toContain('"error":true'); act(() => host.querySelector("button")!.click()); await tick(); expect(host.textContent).toContain('"error":true');
    act(() => host.querySelector("button")!.click()); await tick(); expect(host.textContent).toContain(fixtureId(999)); render({ loader, query: "x".repeat(81) }); await tick(); expect(loader).toHaveBeenCalledTimes(3); expect(host.textContent).toContain('"error":true');
  });
});
