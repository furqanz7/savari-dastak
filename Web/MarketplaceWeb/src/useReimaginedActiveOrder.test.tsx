// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { V1Order } from "./dastakV1";
import { activeOrderStorageKey, useReimaginedActiveOrder } from "./useReimaginedActiveOrder";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const id = "22222222-2222-4222-8222-222222222222";
const session = { accountId: "a", accessToken: "secret-token", supabaseUrl: "https://example.supabase.co", publishableKey: "test" };
const key = activeOrderStorageKey(session.accountId, session.supabaseUrl);
const incoming = { id, service: "grocery" as const };
const order = (status = "PREPARING", version = 4) => ({ id, status, version } as V1Order);
type Loader = typeof import("./dastakV1").getV1Order;
let root: Root; let host: HTMLDivElement;
function Harness({ loader, online = true, token = session.accessToken, account = "a", hint }: { loader: Loader; online?: boolean; token?: string; account?: string; hint?: typeof incoming }) {
  const result = useReimaginedActiveOrder({ ...session, accountId: account, accessToken: token }, hint, online, loader);
  return <><output>{JSON.stringify({ id: result.activeOrder?.id, label: result.label, issue: result.storageIssue })}</output><button onClick={result.retry}>Retry</button></>;
}
function mount(loader: Loader, hint?: typeof incoming, online = true) {
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  act(() => root.render(<Harness loader={loader} hint={hint} online={online} />));
}
beforeEach(() => {
  const values = new Map<string, string>();
  vi.stubGlobal("localStorage", { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => values.set(key, value), removeItem: (key: string) => values.delete(key) });
  vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
});
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe("persistent read-only active order", () => {
  it("saves only a versioned ID/service hint and recovers server status after remount", async () => {
    const loader = vi.fn().mockResolvedValue(order()); mount(loader, incoming); await act(async () => {});
    expect(host.textContent).toContain("Preparing your order");
    expect(JSON.parse(localStorage.getItem(key)!)).toEqual({ version: 1, order: incoming });
    expect(localStorage.getItem(key)).not.toContain("secret-token");
    act(() => root.unmount()); host.remove(); mount(loader); await act(async () => {});
    expect(loader).toHaveBeenCalledTimes(2); expect(host.textContent).toContain(id);
  });
  it("ignores malformed hints and does not request anything without a saved order", async () => {
    localStorage.setItem(key, JSON.stringify({ version: 1, order: { id: "bad", service: "grocery" } }));
    const loader = vi.fn(); mount(loader); await act(async () => {}); expect(loader).not.toHaveBeenCalled();
  });
  it("clears terminal hints without touching shopping", async () => {
    localStorage.setItem("dastak:v1-cart:a", "untouched");
    mount(vi.fn().mockResolvedValue(order("DELIVERED")), incoming); await act(async () => {});
    expect(host.textContent).not.toContain(id); expect(localStorage.getItem(key)).toBeNull();
    expect(localStorage.getItem("dastak:v1-cart:a")).toBe("untouched");
  });
  it("retains recovery on failure and offers an explicit retry", async () => {
    const loader = vi.fn().mockRejectedValueOnce(new Error("network")).mockResolvedValueOnce(order("OUT_FOR_DELIVERY"));
    mount(loader, incoming); await act(async () => {}); expect(host.textContent).toContain("Order status unavailable");
    expect(localStorage.getItem(key)).not.toBeNull();
    await act(async () => host.querySelector("button")!.click()); expect(host.textContent).toContain("Out for delivery");
  });
  it("pauses offline and hidden, aborting unfinished reads", async () => {
    const loader = vi.fn().mockReturnValue(new Promise(() => {})); mount(loader, incoming, false);
    expect(loader).not.toHaveBeenCalled();
    act(() => root.render(<Harness loader={loader} hint={incoming} />)); expect(loader).toHaveBeenCalledOnce();
    vi.spyOn(document, "visibilityState", "get").mockReturnValue("hidden");
    act(() => document.dispatchEvent(new Event("visibilitychange")));
    expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
  });
  it("discards late token/account responses", async () => {
    let resolve!: (value: V1Order) => void;
    const loader = vi.fn().mockReturnValueOnce(new Promise<V1Order>(yes => { resolve = yes; })).mockResolvedValue(order("OUT_FOR_DELIVERY"));
    mount(loader, incoming); act(() => root.render(<Harness loader={loader} token="new" />));
    expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
    await act(async () => resolve(order())); expect(host.textContent).not.toContain("Preparing");
    act(() => root.render(<Harness loader={loader} account="b" />)); expect(host.textContent).not.toContain(id);
  });
  it("polls at most once per minute, with no overlapping reads or version regression", async () => {
    vi.useFakeTimers(); const loader = vi.fn().mockResolvedValueOnce(order("OUT_FOR_DELIVERY", 5)).mockResolvedValue(order("PREPARING", 4));
    mount(loader, incoming); await act(async () => {});
    await act(async () => vi.advanceTimersByTimeAsync(59_999)); expect(loader).toHaveBeenCalledOnce();
    await act(async () => vi.advanceTimersByTimeAsync(1)); expect(loader).toHaveBeenCalledTimes(2);
    expect(host.textContent).toContain("Out for delivery");
  });
  it("reports storage failures without blocking server tracking", async () => {
    vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new Error("quota"); });
    mount(vi.fn().mockResolvedValue(order()), incoming); await act(async () => {});
    expect(host.textContent).toContain("could not be saved"); expect(host.textContent).toContain("Preparing");
  });
  it("rejects a mismatched server order without clearing the saved hint", async () => {
    mount(vi.fn().mockResolvedValue({ ...order("DELIVERED"), id: "different" }), incoming); await act(async () => {});
    expect(host.textContent).toContain("Order status unavailable"); expect(localStorage.getItem(key)).not.toBeNull();
  });
  it("follows another tab's hint and does not erase a newer saved order", async () => {
    let resolve!: (value: V1Order) => void;
    const loader = vi.fn().mockReturnValueOnce(new Promise<V1Order>(yes => { resolve = yes; })).mockResolvedValue(order("OUT_FOR_DELIVERY"));
    mount(loader, incoming);
    const next = { ...incoming, id: "33333333-3333-4333-8333-333333333333" };
    localStorage.setItem(key, JSON.stringify({ version: 1, order: next }));
    await act(async () => resolve(order("DELIVERED")));
    expect(JSON.parse(localStorage.getItem(key)!).order).toEqual(next);
    await act(async () => window.dispatchEvent(new StorageEvent("storage", { key })));
    expect(loader).toHaveBeenLastCalledWith(expect.objectContaining({ orderId: next.id }));
  });
  it("never overlaps slow reads", async () => {
    vi.useFakeTimers(); const loader = vi.fn().mockReturnValue(new Promise(() => {})); mount(loader, incoming);
    await act(async () => vi.advanceTimersByTimeAsync(180_000)); expect(loader).toHaveBeenCalledOnce();
  });
});
