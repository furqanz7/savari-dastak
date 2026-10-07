// @vitest-environment jsdom
import { act, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DastakCustomerView } from "./DastakCustomerView";
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
});
