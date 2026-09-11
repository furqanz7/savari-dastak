// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AdminAccessPanel } from "./AdminAccessPanel";
import type { V1AdminAccess } from "./dastakV1";

const setExecutive = vi.fn();
const getAccess = vi.fn();
vi.mock("./dastakV1", async (importOriginal) => ({
  ...await importOriginal<typeof import("./dastakV1")>(),
  setV1ExecutiveAdmin: (...args: unknown[]) => setExecutive(...args),
  getV1AdminAccess: (...args: unknown[]) => getAccess(...args),
}));

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const auth = { accessToken: "token", supabaseUrl: "https://example.supabase.co", publishableKey: "public" };
const access: V1AdminAccess = {
  role: "SUPERADMIN",
  canManageAdmins: true,
  slots: [
    { slot: 0, role: "SUPERADMIN", email: "owner@example.com", linked: true, version: 1 },
    { slot: 1, role: "EXECUTIVE_ADMIN", email: undefined, linked: false, version: 1 },
    { slot: 2, role: "EXECUTIVE_ADMIN", email: undefined, linked: false, version: 1 },
  ],
};

describe("AdminAccessPanel privileged confirmation", () => {
  let host: HTMLDivElement;
  let root: Root;
  beforeEach(() => {
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    setExecutive.mockReset().mockResolvedValue(undefined);
    getAccess.mockReset().mockResolvedValue(access);
  });
  afterEach(async () => { await act(async () => root.unmount()); host.remove(); });

  it("does not grant Executive Admin access until the exact reviewed account is confirmed", async () => {
    await act(async () => root.render(<AdminAccessPanel auth={auth} access={access} onChange={() => undefined} />));
    const email = host.querySelector("#executive-email-1") as HTMLInputElement;
    await setInput(email, "reviewed@example.com");
    const assign = [...host.querySelectorAll("button")].find((button) => button.textContent === "Assign")!;
    await act(async () => assign.click());

    expect(setExecutive).not.toHaveBeenCalled();
    expect(host.querySelector('[role="alertdialog"]')?.textContent).toContain("reviewed@example.com");
    expect(host.querySelector('[role="alertdialog"]')?.textContent).toContain("full operational capabilities");
    const confirmButton = [...host.querySelectorAll('[role="alertdialog"] button')]
      .find((button) => button.textContent?.includes("Grant full Admin access")) as HTMLButtonElement;
    expect(confirmButton.disabled).toBe(true);
    await setInput(host.querySelector(".admin-confirmation-match input") as HTMLInputElement, "reviewed@example.com");
    expect(confirmButton.disabled).toBe(false);
    await act(async () => confirmButton.click());

    expect(setExecutive).toHaveBeenCalledOnce();
    const request = setExecutive.mock.calls[0][0];
    expect(request).toMatchObject({ slot: 1, email: "reviewed@example.com", expectedVersion: 1, reason: "Role assignment" });
    expect(request.idempotencyKey).toMatch(/^[0-9a-f-]{36}$/i);
  });
});

async function setInput(input: HTMLInputElement, value: string) {
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set?.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
}
