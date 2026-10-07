// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { V1RestaurantMenu } from "./dastakV1";
import { useReimaginedFood } from "./useReimaginedFood";
import { foodMenuFixture } from "./reimaginedFood.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
type Loader = NonNullable<Parameters<typeof useReimaginedFood>[3]>;
let root: Root; let host: HTMLDivElement;
function Harness({ loader, enabled = true, online = true, token = "token", account = "a" }: { loader: Loader; enabled?: boolean; online?: boolean; token?: string; account?: string }) {
  const result = useReimaginedFood({ accountId: account, accessToken: token, supabaseUrl: "https://example.supabase.co", publishableKey: "test" }, enabled, online, loader);
  return <><output>{JSON.stringify({ status: result.status, count: result.data?.length })}</output><button onClick={result.retry}>Retry</button></>;
}
function mount(loader: Loader, enabled = true, online = true) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness loader={loader} enabled={enabled} online={online} />)); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Food session resource", () => {
  it("loads only on Food entry and reuses the same-session in-memory result", async () => {
    const loader = vi.fn().mockResolvedValue([foodMenuFixture()]); mount(loader, false); expect(loader).not.toHaveBeenCalled();
    await act(async () => root.render(<Harness loader={loader} />)); expect(loader).toHaveBeenCalledOnce();
    expect(loader).toHaveBeenCalledWith(expect.objectContaining({ accessToken: "token", limit: 100, signal: expect.any(AbortSignal) }));
    act(() => root.render(<Harness loader={loader} enabled={false} />));
    await act(async () => root.render(<Harness loader={loader} />)); expect(loader).toHaveBeenCalledOnce();
    expect(host.textContent).toContain('"count":1');
  });
  it("cancels unfinished requests on exit and rejects late account responses", async () => {
    let resolve!: (data: V1RestaurantMenu[]) => void;
    const loader = vi.fn().mockReturnValueOnce(new Promise<V1RestaurantMenu[]>(yes => { resolve = yes; })).mockResolvedValue([]);
    mount(loader); act(() => root.render(<Harness loader={loader} account="b" />)); expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
    await act(async () => resolve([foodMenuFixture()])); expect(host.textContent).toContain('"count":0');
    expect(host.textContent).not.toContain('"count":1');
  });
  it("hides previous menus immediately on token rotation", async () => {
    const loader = vi.fn().mockResolvedValueOnce([foodMenuFixture()]).mockReturnValue(new Promise(() => {}));
    mount(loader); await act(async () => {}); act(() => root.render(<Harness loader={loader} token="rotated" />));
    expect(host.textContent).not.toContain('"count":1'); expect(host.textContent).toContain("loading");
  });
  it("does not fetch offline and preserves cached menus for browsing", async () => {
    const loader = vi.fn().mockResolvedValue([foodMenuFixture()]); mount(loader, true, false); expect(loader).not.toHaveBeenCalled();
    await act(async () => root.render(<Harness loader={loader} />));
    act(() => root.render(<Harness loader={loader} online={false} />)); expect(host.textContent).toContain('"count":1'); expect(loader).toHaveBeenCalledOnce();
  });
  it("retries failure and rejects ambiguous catalogue data", async () => {
    const menu = foodMenuFixture(); const loader = vi.fn().mockResolvedValueOnce([menu, menu]).mockResolvedValue([]);
    mount(loader); await act(async () => {}); expect(host.textContent).toContain("unavailable");
    await act(async () => host.querySelector("button")!.click()); expect(host.textContent).toContain("ready"); expect(loader).toHaveBeenCalledTimes(2);
  });
  it("aborts a pending read when returning to Grocery", () => {
    const loader = vi.fn().mockReturnValue(new Promise(() => {})); mount(loader);
    act(() => root.render(<Harness loader={loader} enabled={false} />)); expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
  });
});
