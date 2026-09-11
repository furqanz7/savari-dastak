// @vitest-environment jsdom
import { act, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DeliveryHistoryPanel } from "./DeliveryPartnerView";
import { getDeliveryPartnerWorkHistory } from "./delivery";
import { RoyaltyPanel } from "./RoyaltyPanel";
import { getRoyalty, type RoyaltySnapshot } from "./earnings";
import { RoleAccountView } from "./RoleAccountView";
import { snapshotAccountProfile, updateAccountProfile } from "./accountProfile";

vi.mock("./delivery", async (original) => ({ ...await original<typeof import("./delivery")>(), getDeliveryPartnerWorkHistory: vi.fn() }));
vi.mock("./earnings", async (original) => ({ ...await original<typeof import("./earnings")>(), getRoyalty: vi.fn() }));
vi.mock("./accountProfile", async (original) => ({ ...await original<typeof import("./accountProfile")>(), snapshotAccountProfile: vi.fn(), updateAccountProfile: vi.fn() }));
const auth = { accessToken: "test", supabaseUrl: "https://example.supabase.co", publishableKey: "public" };
const earnings: RoyaltySnapshot = { currency: "INR", availablePaise: 18000, balancePaise: 18000, lifetimeEarnedPaise: 18000, negativeBalancePaise: 0, payoutAvailability: { destinationRegistrationAvailable: false, withdrawalExecutionAvailable: false }, subjects: [{ subjectType: "RIDER", subjectId: "rider-1", currency: "INR", balancePaise: 18000, availablePaise: 18000, lifetimeEarnedPaise: 18000, negativeBalancePaise: 0, canWithdraw: false, entries: [], adjustments: [], withdrawals: [] }] };
let host: HTMLDivElement; let root: Root;
beforeEach(() => {
  (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.clearAllMocks(); });
async function render(node: ReactNode) { await act(async () => root.render(node)); }
async function click(target: HTMLElement) { await act(async () => target.click()); }

describe("Delivery History, Earnings and Account presentation", () => {
  it("keeps historical work visible after refresh failure and never invents missing earnings", async () => {
    vi.mocked(getDeliveryPartnerWorkHistory).mockResolvedValueOnce([{ kind: "RETURN", workId: "return-1", reference: "DSK-0001", status: "COMPLETED", startedAt: "2026-09-11T09:00:00Z", endedAt: "2026-09-11T10:00:00Z", packageCount: 2, payoutPaise: null, outcome: "RETURNED" }]).mockRejectedValueOnce(new Error("Connection unavailable"));
    const onOpenEarnings = vi.fn();
    await render(<DeliveryHistoryPanel auth={auth} onOpenEarnings={onOpenEarnings} onSessionExpired={() => false} />);
    expect(host.textContent).toContain("DSK-0001"); expect(host.textContent).toContain("Returned"); expect(host.textContent).not.toContain("₹0");
    await click(host.querySelector('[aria-label="Refresh delivery history"]')!);
    expect(host.textContent).toContain("Previously loaded history remains visible"); expect(host.textContent).toContain("DSK-0001"); expect(host.textContent).not.toContain("No completed work yet");
    await click(host.querySelector('.delivery-history-earnings')!); expect(onOpenEarnings).toHaveBeenCalledOnce();
  });

  it("does not show empty History when the first request failed", async () => {
    vi.mocked(getDeliveryPartnerWorkHistory).mockRejectedValueOnce(new Error("History unavailable"));
    await render(<DeliveryHistoryPanel auth={auth} onOpenEarnings={vi.fn()} onSessionExpired={() => false} />);
    expect(host.textContent).toContain("History couldn’t update"); expect(host.textContent).not.toContain("No completed work yet");
  });

  it("uses Earnings throughout the rider surface and respects unavailable payouts", async () => {
    vi.mocked(getRoyalty).mockResolvedValueOnce(earnings).mockRejectedValueOnce(new Error("Royalty is unavailable."));
    await render(<RoyaltyPanel auth={auth} kind="RIDER" />);
    expect(host.textContent).not.toContain("Royalty"); expect(host.querySelector('[aria-label="Earnings summary"]')).not.toBeNull();
    expect(host.textContent).toContain("Payout setup is not available yet");
    expect(host.querySelector<HTMLInputElement>('.royalty-withdraw-form input')?.disabled).toBe(true);
    await click(host.querySelector('[aria-label="Refresh earnings"]')!);
    expect(host.textContent).not.toContain("Royalty"); expect(host.textContent).toContain("Earnings couldn’t update"); expect(host.textContent).toContain("₹180");
  });

  it("leaves Merchant Earnings wording and labels unchanged", async () => {
    vi.mocked(getRoyalty).mockResolvedValueOnce(earnings);
    await render(<RoyaltyPanel auth={auth} kind="MERCHANT" />);
    expect(host.textContent).toContain("Your Royalty"); expect(host.querySelector('[aria-label="Royalty summary"]')).not.toBeNull();
    expect(host.querySelector('.merchant-quiet-refresh')?.textContent).toContain("Check balance");
  });

  it("reuses the polished profile editor with rider semantics and unchanged account data", async () => {
    vi.mocked(snapshotAccountProfile).mockResolvedValue({ displayName: "Test Rider", phoneNumber: "+919876543210" });
    await render(<RoleAccountView {...auth} displayName="Test Rider" roleName="Delivery Partner" persona="DELIVERY" notificationSurface={<p>Delivery alerts on</p>} onSignOut={vi.fn()} />);
    expect(host.textContent).toContain("Test Rider"); expect(host.querySelector('[aria-label="Browser delivery alerts"]')).not.toBeNull();
    const edit = host.querySelector<HTMLButtonElement>('[aria-label="Edit delivery profile"]')!;
    edit.focus(); await click(edit);
    expect(host.querySelector('.rider-profile-presentation .customer-profile-editor')).not.toBeNull();
    expect(document.activeElement?.id).toBe("customer-profile-name");
    expect(host.querySelector('output[aria-label="Phone number"]')?.textContent).toBe("+919876543210");
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    expect(document.activeElement).toBe(edit); expect(updateAccountProfile).not.toHaveBeenCalled();
  });
});
