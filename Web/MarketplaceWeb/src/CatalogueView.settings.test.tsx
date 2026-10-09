// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CatalogueView } from "./CatalogueView";
import { AccountProfileRequestError, exportAccountData, snapshotAccountProfile, snapshotCustomerIdentities } from "./accountProfile";
import type { DastakWebPushController } from "./useDastakWebPush";

vi.mock("./accountProfile", async original => ({ ...await original<typeof import("./accountProfile")>(), exportAccountData: vi.fn(), snapshotAccountProfile: vi.fn(), snapshotCustomerIdentities: vi.fn() }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let host: HTMLDivElement, root: Root;
const client = {} as SupabaseClient;
const noop = () => {};
const signOut = vi.fn();
function render(pane: "profile" | "settings" = "settings", token = "synthetic", webPush?: DastakWebPushController) {
  root.render(<CatalogueView accountId="synthetic" accessToken={token} client={client} displayName="Synthetic" phoneNumber="+919876543210" supabaseUrl="https://example.invalid" publishableKey="synthetic" orderRefreshToken={0} section="account" accountPane={pane} overlayPresentation="reimagined" onNavigate={noop} onOpenOrder={noop} onCloseOrder={noop} onOpenParcel={noop} onSignOut={signOut} deliveryPartnerUrl="#delivery" merchantUrl="#merchant" webPush={webPush} />);
}
function exportButton() { return [...host.querySelectorAll("button")].find(b => b.textContent?.includes("Download your data") || b.textContent?.includes("Preparing your data"))!; }
beforeEach(async () => {
  vi.clearAllMocks();
  vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Synthetic unavailable resource")));
  vi.mocked(snapshotAccountProfile).mockResolvedValue({ displayName: "Synthetic", phoneNumber: "+919876543210" });
  vi.mocked(snapshotCustomerIdentities).mockResolvedValue([]);
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  await act(async () => render());
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe("Settings export request lifetime", () => {
  it("deduplicates queued clicks and allows retry after a failure", async () => {
    let reject!: (reason: Error) => void;
    vi.mocked(exportAccountData).mockReturnValueOnce(new Promise((_, fail) => { reject = fail; }));
    const button = exportButton();
    act(() => { button.click(); button.click(); });
    expect(exportAccountData).toHaveBeenCalledOnce();
    expect(exportButton().disabled).toBe(true);
    await act(async () => reject(new Error("Synthetic export failure")));
    expect(exportButton().disabled).toBe(false);
    vi.mocked(exportAccountData).mockRejectedValueOnce(new Error("Synthetic retry failure"));
    await act(async () => exportButton().click());
    expect(exportAccountData).toHaveBeenCalledTimes(2);
  });
  it.each(["navigate", "rotate token", "unmount"])("ignores an old unauthorized export after %s", async action => {
    let reject!: (reason: Error) => void;
    vi.mocked(exportAccountData).mockReturnValueOnce(new Promise((_, fail) => { reject = fail; }));
    act(() => exportButton().click());
    await act(async () => {
      if (action === "unmount") root.render(null);
      else render(action === "navigate" ? "profile" : "settings", action === "rotate token" ? "rotated" : "synthetic");
    });
    await act(async () => reject(new AccountProfileRequestError("Synthetic expired export", 401, "AUTH_REQUIRED")));
    expect(signOut).not.toHaveBeenCalled();
  });
  it("still handles a genuine current unauthorized response", async () => {
    vi.mocked(exportAccountData).mockRejectedValueOnce(new AccountProfileRequestError("Synthetic expired export", 401, "AUTH_REQUIRED"));
    await act(async () => exportButton().click());
    expect(signOut).toHaveBeenCalledOnce();
  });
  it("downloads a current successful export once and removes the temporary link", async () => {
    const createObjectURL = vi.fn(() => "blob:synthetic");
    vi.stubGlobal("URL", Object.assign(class extends URL {}, { createObjectURL, revokeObjectURL: vi.fn() }));
    const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
    vi.mocked(exportAccountData).mockResolvedValueOnce({ filename: "synthetic.json", data: { profile: "synthetic" } });
    await act(async () => exportButton().click());
    expect(createObjectURL).toHaveBeenCalledOnce();
    expect(click).toHaveBeenCalledOnce();
    expect(host.textContent).toContain("Your Dastak data export was downloaded.");
    expect(document.querySelector('a[download="synthetic.json"]')).toBeNull();
    expect(exportButton().disabled).toBe(false);
  });
  it.each(["navigate", "rotate token", "unmount"])("does not download an old response after %s", async action => {
    const createObjectURL = vi.fn(() => "blob:synthetic");
    vi.stubGlobal("URL", Object.assign(class extends URL {}, { createObjectURL, revokeObjectURL: vi.fn() }));
    let resolve!: (data: { filename: string; data: object }) => void;
    vi.mocked(exportAccountData).mockReturnValueOnce(new Promise(done => { resolve = done; }));
    act(() => exportButton().click());
    await act(async () => {
      if (action === "unmount") root.render(null);
      else render(action === "navigate" ? "profile" : "settings", action === "rotate token" ? "rotated" : "synthetic");
    });
    await act(async () => resolve({ filename: "synthetic.json", data: {} }));
    expect(createObjectURL).not.toHaveBeenCalled();
  });
});

describe("Settings order alert presentation", () => {
  it("routes a notification retry to the supplied controller, using a mock only", async () => {
    const enable = vi.fn(async () => {});
    await act(async () => render("settings", "synthetic", { status: "error", message: "Synthetic notification failure", shouldPrompt: false, enable, dismiss: noop, refresh: async () => {} }));
    const alerts = [...host.querySelectorAll("button")].find(b => b.textContent?.includes("Order alerts"))!;
    expect(alerts.textContent).toContain("Synthetic notification failure");
    await act(async () => alerts.click());
    expect(enable).toHaveBeenCalledOnce();
  });
  it.each([
    ["checking", "Checking", true], ["enabling", "Checking", true],
    ["enabled", "On", false], ["dismissed", "Off", false],
    ["prompt", "Set up", false], ["error", "Retry", false],
    ["blocked", "Blocked", false], ["unsupported", "Unavailable", false],
  ] as const)("shows %s without requesting browser permission", async (status, label, disabled) => {
    const enable = vi.fn(async () => {});
    await act(async () => render("settings", "synthetic", { status, shouldPrompt: false, enable, dismiss: noop, refresh: async () => {} }));
    const alerts = [...host.querySelectorAll("button")].find(b => b.textContent?.includes("Order alerts"))!;
    expect(alerts.disabled).toBe(disabled);
    expect(alerts.querySelector("b")?.textContent).toBe(label);
    expect(enable).not.toHaveBeenCalled();
  });
});
