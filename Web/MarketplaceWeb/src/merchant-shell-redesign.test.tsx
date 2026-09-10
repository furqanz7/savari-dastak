// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { MerchantOrdersView } from "./MerchantOrdersView";
import { snapshotAccountProfile, updateAccountProfile } from "./accountProfile";
import { discoverDefaultMerchantBranches, merchantBranchStorageKey } from "./merchantBranchContext";

vi.mock("./merchantBranchContext", async (original) => ({ ...await original<typeof import("./merchantBranchContext")>(), discoverDefaultMerchantBranches: vi.fn() }));
vi.mock("./accountProfile", async (original) => ({ ...await original<typeof import("./accountProfile")>(), snapshotAccountProfile: vi.fn(), updateAccountProfile: vi.fn() }));
vi.mock("./useDastakWebPush", () => ({ useDastakWebPush: () => ({ status: "enabled", shouldPrompt: false, enable: vi.fn(), refresh: vi.fn(), dismiss: vi.fn() }) }));
vi.mock("./MerchantV1Opportunities", () => ({ MerchantV1Opportunities: ({ activeBranchId }: { activeBranchId: string }) => <div data-testid="orders-feed">Orders for {activeBranchId}</div> }));
vi.mock("./MerchantV1CommerceControl", () => ({ MerchantV1CommerceControl: ({ branch }: { branch: { id: string } }) => <div data-testid="store-editor">Store for {branch.id}</div> }));
vi.mock("./RoyaltyPanel", () => ({ RoyaltyPanel: () => <div data-testid="earnings">Earnings ledger</div> }));

let host: HTMLDivElement;
let root: Root;
const branches = [
  { id: "market", branchName: "Market Street", organizationName: "Dastak Stores", merchantType: "RETAIL" },
  { id: "cafe", branchName: "Station Cafe", organizationName: "Dastak Kitchen", merchantType: "RESTAURANT_CAFE" },
];
const signOut = vi.fn();
beforeEach(() => {
  (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  const storage = new Map<string, string>();
  vi.stubGlobal("localStorage", { getItem: (key: string) => storage.get(key) ?? null, setItem: (key: string, value: string) => storage.set(key, value), removeItem: (key: string) => storage.delete(key), clear: () => storage.clear() });
  vi.stubGlobal("scrollTo", vi.fn());
  vi.mocked(discoverDefaultMerchantBranches).mockResolvedValue({ branches, failures: [] });
  vi.mocked(snapshotAccountProfile).mockResolvedValue({ displayName: "Test Merchant", phoneNumber: "+919876543210" });
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); vi.restoreAllMocks(); vi.clearAllMocks(); });
async function mount(accountId = "merchant-one") {
  await act(async () => root.render(<MerchantOrdersView accessToken="test-token" accountId={accountId} client={{} as SupabaseClient} displayName="Test Merchant" email="test@example.com" supabaseUrl="https://example.supabase.co" publishableKey="public" webPushPublicKey="public-push" onSignOut={signOut} />));
}
function nav(label: string) { return [...host.querySelectorAll<HTMLButtonElement>(".merchant-navigation button")].find((item) => item.textContent === label)!; }
async function click(element: HTMLElement) { await act(async () => element.click()); }

describe("Merchant redesigned shell", () => {
  it("uses named operational navigation and unmounts inactive sections", async () => {
    await mount();
    expect([...host.querySelectorAll(".merchant-navigation button")].map((node) => node.textContent)).toEqual(["Orders", "Store", "Earnings", "Account"]);
    expect(nav("Orders").getAttribute("aria-current")).toBe("page");
    expect(host.querySelector('[data-testid="orders-feed"]')).not.toBeNull();
    await click(nav("Store"));
    expect(host.querySelector('[data-testid="orders-feed"]')).toBeNull();
    expect(host.querySelector('[data-testid="store-editor"]')).not.toBeNull();
    expect(document.activeElement?.id).toBe("merchant-content");
    expect(window.scrollTo).toHaveBeenCalledWith({ top: 0, behavior: "instant" });
    await click(nav("Earnings"));
    expect(host.querySelector('[data-testid="store-editor"]')).toBeNull();
    expect(host.querySelector('[data-testid="earnings"]')).not.toBeNull();
    expect(host.querySelector('[href="#merchant-content"]')?.textContent).toBe("Skip to content");
  });

  it("retains the selected authorized branch across Orders and Store, scoped to the account", async () => {
    localStorage.setItem(merchantBranchStorageKey("merchant-one"), "cafe");
    await mount();
    expect(host.querySelector('[data-testid="orders-feed"]')?.textContent).toBe("Orders for cafe");
    await click(nav("Store"));
    expect(host.querySelector('[data-testid="store-editor"]')?.textContent).toBe("Store for cafe");
    const select = host.querySelector<HTMLSelectElement>(".merchant-branch-context select")!;
    await act(async () => { select.value = "market"; select.dispatchEvent(new Event("change", { bubbles: true })); });
    expect(host.querySelector('[data-testid="store-editor"]')?.textContent).toBe("Store for market");
    expect(localStorage.getItem(merchantBranchStorageKey("merchant-one"))).toBe("market");
    expect(localStorage.getItem(merchantBranchStorageKey("another-account"))).toBeNull();
  });

  it("opens the shared polished profile form and returns keyboard focus on dismissal", async () => {
    await mount(); await click(nav("Account"));
    expect(host.querySelector('[data-testid="orders-feed"]')).toBeNull();
    expect(host.textContent).toContain("Your merchant account");
    expect(host.textContent).toContain("New-order alerts on");
    const edit = host.querySelector<HTMLButtonElement>('[aria-label="Edit merchant profile"]')!;
    edit.focus(); await click(edit);
    expect(host.querySelector(".merchant-profile-presentation .customer-profile-editor")).not.toBeNull();
    expect(document.activeElement?.id).toBe("customer-profile-name");
    expect(host.querySelector('output[aria-label="Phone number"]')?.textContent).toBe("+919876543210");
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    expect(host.querySelector('[role="dialog"]')).toBeNull();
    expect(document.activeElement).toBe(edit);
    expect(updateAccountProfile).not.toHaveBeenCalled();
  });

  it("keeps Merchant account details modal and sign-out explicitly confirmed", async () => {
    await mount(); await click(nav("Account"));
    const privacy = [...host.querySelectorAll<HTMLButtonElement>("button")].find((node) => node.textContent?.includes("Privacy and data"))!;
    privacy.focus(); await click(privacy);
    const dialog = host.querySelector('[role="dialog"]')!;
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    expect(dialog.contains(document.activeElement)).toBe(true);
    const done = [...dialog.querySelectorAll<HTMLButtonElement>("button")].find((node) => node.textContent === "Done")!;
    done.focus();
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true })));
    expect(document.activeElement?.getAttribute("aria-label")).toBe("Close");
    await click(done);
    expect(document.activeElement).toBe(privacy);
    const signOutButton = [...host.querySelectorAll<HTMLButtonElement>("button")].find((node) => node.querySelector("strong")?.textContent === "Sign out")!;
    await click(signOutButton);
    expect(host.querySelector('[role="alertdialog"]')).not.toBeNull();
    expect(signOut).not.toHaveBeenCalled();
  });
});
