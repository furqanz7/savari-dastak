// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, describe, expect, it, vi } from "vitest";
import { CatalogueView } from "./CatalogueView";
import { snapshotAccountProfile } from "./accountProfile";
vi.mock("./accountProfile", async original => ({ ...await original<typeof import("./accountProfile")>(), snapshotAccountProfile: vi.fn() }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

describe("real Profile loading and recovery", () => {
  it("does not edit stale seed details and makes a failed profile read retryable", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Synthetic unavailable resource")));
    let fail!: (error: Error) => void;
    vi.mocked(snapshotAccountProfile).mockReturnValueOnce(new Promise((_, reject) => { fail = reject; }));
    const host = document.createElement("div"); document.body.append(host); const root = createRoot(host);
    const noop = () => {};
    try {
      await act(async () => root.render(<CatalogueView accountId="synthetic" accessToken="synthetic" client={{} as SupabaseClient} displayName="Stale seed" phoneNumber="+919876543210" supabaseUrl="https://example.invalid" publishableKey="synthetic" orderRefreshToken={0} section="account" accountPane="profile" overlayPresentation="reimagined" onNavigate={noop} onOpenOrder={noop} onCloseOrder={noop} onOpenParcel={noop} onSignOut={noop} deliveryPartnerUrl="#delivery" merchantUrl="#merchant" />));
      expect(host.querySelector<HTMLButtonElement>('[aria-label="Edit profile"]')!.disabled).toBe(true);
      await act(async () => fail(new Error("Synthetic profile read failure")));
      const retry = [...host.querySelectorAll("button")].find(button => button.textContent === "Retry profile")!;
      expect(retry).toBeTruthy(); expect(host.querySelector<HTMLButtonElement>('[aria-label="Edit profile"]')!.disabled).toBe(true);
      vi.mocked(snapshotAccountProfile).mockResolvedValueOnce({ displayName: "Fresh profile", phoneNumber: "+919876543210" });
      await act(async () => retry.click());
      const edit = host.querySelector<HTMLButtonElement>('[aria-label="Edit profile"]')!;
      expect(edit.disabled).toBe(false); expect(edit.textContent).toContain("Fresh profile"); expect(host.textContent).not.toContain("Retry profile");
      act(() => edit.click());
      expect(document.querySelector<HTMLInputElement>('#customer-profile-name')!.value).toBe("Fresh profile");
    } finally { act(() => root.unmount()); host.remove(); }
  });
});
