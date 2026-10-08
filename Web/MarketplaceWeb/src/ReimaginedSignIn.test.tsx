// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { ReimaginedSignIn } from "./ReimaginedSignIn";
vi.mock("./ReimaginedGroceryRoom", () => ({ ReimaginedGroceryRoom: ({ outside }: { outside: boolean }) => <div data-outside={outside} /> }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
it("uses existing OAuth callbacks, disables duplicate sign-in and keeps legal access outside the store", () => {
  const host = document.createElement("div"); document.body.append(host); const root = createRoot(host); const onSignIn = vi.fn();
  const props = { busy: false, onSignIn, legalLinks: { terms: "/terms", privacy: "/privacy", support: "/support" } };
  try {
    act(() => root.render(<ReimaginedSignIn {...props} />));
    expect(host.querySelector('[data-outside="true"]')).not.toBeNull();
    expect(host.querySelector('a[href="/privacy"]')).not.toBeNull();
    expect(host.querySelector("h1")?.textContent).toBe("Dastakدستک");
    expect(host.querySelector('h1 bdi[lang="ur"][dir="rtl"]')).not.toBeNull();
    expect(host.querySelectorAll('.reimagined-auth-actions svg[aria-hidden="true"]')).toHaveLength(2);
    const buttons = [...host.querySelectorAll("button")];
    act(() => buttons.find(button => button.textContent === "Continue with Google")!.click());
    expect(onSignIn).toHaveBeenCalledWith("google");
    act(() => root.render(<ReimaginedSignIn {...props} busy signingInProvider="google" />));
    expect([...host.querySelectorAll("button")].every(button => button.disabled)).toBe(true);
    expect(host.querySelector('[aria-label="Sign in options"]')?.getAttribute("aria-busy")).toBe("true");
    expect(host.textContent).toContain("Opening Google…");
    expect(host.querySelector('a[href="/support"]')).not.toBeNull();
    act(() => root.render(<ReimaginedSignIn {...props} />));
    act(() => [...host.querySelectorAll("button")].find(button => button.textContent === "Continue with Apple")!.click());
    expect(onSignIn).toHaveBeenLastCalledWith("apple");
    expect(host.querySelector('[aria-label="Dastak navigation"]')).toBeNull();
  } finally { act(() => root.unmount()); host.remove(); }
});
