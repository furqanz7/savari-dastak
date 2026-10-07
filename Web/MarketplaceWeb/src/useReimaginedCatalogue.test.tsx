// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useReimaginedCatalogue } from "./useReimaginedCatalogue";
import type { loadReimaginedCatalogue, ReimaginedCatalogue } from "./reimaginedCatalogue";
import { groceryFixture } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
const session = (accountId: string) => ({ accountId, accessToken: `${accountId}-token`, supabaseUrl: "https://example.supabase.co", publishableKey: "test" });
function deferred() { let resolve!: (data: ReimaginedCatalogue) => void; let reject!: (error: Error) => void; const promise = new Promise<ReimaginedCatalogue>((yes, no) => { resolve = yes; reject = no; }); return { resolve, reject, promise }; }
function Harness({ accountId, loader }: { accountId?: string; loader: typeof loadReimaginedCatalogue }) {
  const result = useReimaginedCatalogue(accountId ? session(accountId) : undefined, loader);
  return <><output>{JSON.stringify({ status: result.status, version: result.data?.catalogue.catalogueVersion })}</output><button onClick={result.retry}>Retry</button></>;
}
function mount(accountId: string, loader: typeof loadReimaginedCatalogue) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness accountId={accountId} loader={loader} />)); }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Reimagined authenticated catalogue ownership", () => {
  it("cancels requests and hides another account's late data on switch/sign-out", async () => {
    const first = deferred(); const second = deferred();
    const loader = vi.fn<typeof loadReimaginedCatalogue>().mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    mount("first", loader);
    act(() => root.render(<Harness accountId="second" loader={loader} />));
    expect(loader.mock.calls[0][1].aborted).toBe(true);
    await act(async () => first.resolve(groceryFixture));
    expect(host.textContent).toContain('"status":"loading"');
    await act(async () => second.resolve(groceryFixture));
    expect(host.textContent).toContain('"status":"ready"');
    act(() => root.render(<Harness loader={loader} />));
    expect(host.textContent).toContain('"status":"unavailable"');
    expect(host.textContent).not.toContain("2026-09-30");
  });
  it("surfaces failure and explicitly retries instead of returning stale data", async () => {
    const failed = deferred(); const retry = deferred();
    const loader = vi.fn<typeof loadReimaginedCatalogue>().mockReturnValueOnce(failed.promise).mockReturnValueOnce(retry.promise);
    mount("first", loader); await act(async () => failed.reject(new Error("offline")));
    expect(host.textContent).toContain('"status":"unavailable"');
    act(() => host.querySelector("button")!.click()); expect(host.textContent).toContain('"status":"loading"');
    await act(async () => retry.resolve(groceryFixture)); expect(host.textContent).toContain('"status":"ready"');
  });
});
