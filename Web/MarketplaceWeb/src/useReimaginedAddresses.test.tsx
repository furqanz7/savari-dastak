// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { CustomerDeliveryAddressCollection } from "./customerAddresses";
import { useReimaginedAddresses } from "./useReimaginedAddresses";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
const collection: CustomerDeliveryAddressCollection = { addresses: ["home", "work"].map((id, index) => ({ addressId: id, label: id, address: id, building: "Building", details: "Details", displayAddress: `${id} address`, location: { latitude: 12, longitude: 77 }, isDefault: index === 0, updatedAt: "2026-09-30" })) };
type Loader = Parameters<typeof useReimaginedAddresses>[2];
function deferred() { let resolve!: (value: CustomerDeliveryAddressCollection) => void; const promise = new Promise<CustomerDeliveryAddressCollection>(yes => { resolve = yes; }); return { promise, resolve }; }
function Harness({ account = "a", token = "token", enabled = true, loader }: { account?: string; token?: string; enabled?: boolean; loader: Loader }) {
  const result = useReimaginedAddresses({ accountId: account, accessToken: token, supabaseUrl: "https://example.supabase.co", publishableKey: "test" }, enabled, loader);
  return <><output>{JSON.stringify({ status: result.status, selected: result.selected?.addressId, count: result.addresses.length })}</output><button onClick={() => result.select("work")}>Work</button><button onClick={result.retry}>Retry</button></>;
}
function mount(loader: Loader, enabled = true) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness loader={loader} enabled={enabled} />)); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Reimagined saved address boundary", () => {
  it("does not request addresses before the picker opens", async () => {
    const loader = vi.fn().mockResolvedValue(collection); mount(loader, false); expect(loader).not.toHaveBeenCalled();
    await act(async () => root.render(<Harness loader={loader} />)); expect(loader).toHaveBeenCalledOnce();
    expect(host.textContent).toContain('"selected":"home"');
    act(() => host.querySelector("button")!.click()); expect(host.textContent).toContain('"selected":"work"');
    expect(loader).toHaveBeenCalledOnce(); expect(collection.addresses[0].isDefault).toBe(true);
  });
  it("aborts and rejects a late response from another account", async () => {
    const first = deferred(); const second = deferred(); const loader = vi.fn().mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    mount(loader); act(() => root.render(<Harness loader={loader} account="b" />));
    expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
    await act(async () => first.resolve(collection)); expect(host.textContent).toContain('"count":0');
    await act(async () => second.resolve({ addresses: [] })); expect(host.textContent).toContain('"status":"ready"'); expect(host.textContent).not.toContain('"selected"');
  });
  it("hides previous addresses immediately on token rotation", async () => {
    const pending = deferred(); const loader = vi.fn().mockResolvedValueOnce(collection).mockReturnValueOnce(pending.promise);
    mount(loader); await act(async () => {}); expect(host.textContent).toContain('"count":2');
    act(() => root.render(<Harness loader={loader} token="rotated" />)); expect(host.textContent).toContain('"count":0');
    await act(async () => pending.resolve(collection)); expect(host.textContent).toContain('"count":2');
  });
  it("retries failures without retaining a stale address", async () => {
    const loader = vi.fn().mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce(collection);
    mount(loader); await act(async () => {}); expect(host.textContent).toContain('"status":"unavailable"');
    await act(async () => (host.querySelectorAll("button")[1] as HTMLButtonElement).click());
    expect(host.textContent).toContain('"status":"ready"'); expect(loader).toHaveBeenCalledTimes(2);
  });
  it("cancels an unfinished read when the picker closes", async () => {
    const pending = deferred(); const loader = vi.fn().mockReturnValue(pending.promise); mount(loader);
    act(() => root.render(<Harness loader={loader} enabled={false} />)); expect(loader.mock.calls[0][0].signal.aborted).toBe(true);
    await act(async () => pending.resolve(collection)); expect(host.textContent).toContain('"status":"idle"');
  });
});
