// @vitest-environment jsdom
import { act, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DastakCustomerView, ExistingDastakCustomerView } from "./DastakCustomerView";
import { DastakV1CustomerExperience } from "./DastakV1CustomerExperience";
import { ReimaginedCustomerRoot } from "./ReimaginedCustomerRoot";
vi.mock("./DastakV1CustomerExperience", () => ({ DastakV1CustomerExperience: vi.fn(() => <p>Existing catalogue</p>) }));
vi.mock("./ReimaginedCustomerRoot", () => ({ ReimaginedCustomerRoot: vi.fn(() => <p>Authenticated Reimagined root</p>) }));
vi.mock("./orderRealtime", () => ({ useOrderRealtime: () => "subscribed" }));
vi.mock("./useDastakWebPush", () => ({ useDastakWebPush: () => ({ shouldPrompt: false }) }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
const props: ComponentProps<typeof DastakCustomerView> = {
  accountId: "account", accessToken: "session-token", client: {} as ComponentProps<typeof DastakCustomerView>["client"],
  supabaseUrl: "https://example.supabase.co", publishableKey: "publishable", onSignOut: vi.fn(),
  legalLinks: { privacy: "/privacy", terms: "/terms", support: "/support" }, webPushPublicKey: "", deliveryPartnerUrl: "/delivery", merchantUrl: "/merchant",
};
async function mount(url: string) {
  window.history.replaceState(null, "", url);
  vi.stubGlobal("scrollTo", vi.fn());
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  await act(async () => { root.render(<DastakCustomerView {...props} />); });
}
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); vi.clearAllMocks(); vi.unstubAllGlobals(); });
describe("customer entry ownership", () => {
  it("mounts only Reimagined when explicitly opted in locally", async () => {
    await mount("/?reimagined=1");
    expect(host.textContent).toContain("Authenticated Reimagined root");
    expect(DastakV1CustomerExperience).not.toHaveBeenCalled();
    expect(ReimaginedCustomerRoot).toHaveBeenCalledWith(expect.objectContaining({ accountId: "account", accessToken: "session-token" }), undefined);
  });
  it("retains the current customer experience without opt-in", async () => {
    await mount("/#home");
    expect(host.textContent).toContain("Existing catalogue");
    expect(ReimaginedCustomerRoot).not.toHaveBeenCalled();
  });
  it("embeds real Orders without another shopping owner or duplicate navigation", async () => {
    window.history.replaceState(null, "", "/?reimagined=1"); vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const orderId = "11111111-1111-4111-8111-111111111111";
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded initialSection="orders" initialOrderId={orderId} />));
    expect(DastakV1CustomerExperience).toHaveBeenCalledWith(expect.objectContaining({ section: "orders", initialOrderId: orderId, onOrderAgainInExisting: expect.any(Function) }), undefined);
    expect(host.querySelector('[aria-label="Dastak"]')).toBeNull();
    expect(window.location.hash).toBe("");
  });
});
