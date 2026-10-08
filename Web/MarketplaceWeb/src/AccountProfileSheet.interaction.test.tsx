// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AccountProfileSheet } from "./AccountProfileSheet";

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let host: HTMLDivElement, root: Root;
beforeEach(() => { host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); });
const profile = { displayName: "Synthetic customer", phoneNumber: "+919876543210" };
function render(busy = false, name = profile.displayName, error?: string) {
  const save = vi.fn(async () => {}), dismiss = vi.fn();
  act(() => root.render(<AccountProfileSheet profile={{ ...profile, displayName: name }} presentation="customer" busy={busy} error={error} onSave={save} onDismiss={dismiss} />));
  return { save, dismiss };
}
function submit() { act(() => host.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))); }
describe("profile editor interaction boundaries", () => {
  it("does not submit again while a save is already in progress", () => {
    const { save } = render(true); submit(); expect(save).not.toHaveBeenCalled();
  });
  it("shows whitespace-only name validation without sending a save", () => {
    const { save } = render(false, "   "); submit();
    expect(host.textContent).toContain("Enter your full name."); expect(save).not.toHaveBeenCalled();
    expect(host.querySelector('input')?.getAttribute('aria-invalid')).toBe("true");
  });
  it("saves a valid draft, leaves phone read-only and permits retry after an error", () => {
    const { save } = render(false, profile.displayName, "Synthetic failed request"); submit();
    expect(save).toHaveBeenCalledWith(profile); expect(host.textContent).toContain("Synthetic failed request");
    expect(host.querySelectorAll('input')).toHaveLength(1); expect(host.querySelector('output')?.textContent).toBe(profile.phoneNumber);
  });
  it("Cancel dismisses without sending a save", () => {
    const { save, dismiss } = render();
    act(() => [...host.querySelectorAll('button')].find(x => x.textContent === "Cancel")!.click());
    expect(dismiss).toHaveBeenCalledOnce(); expect(save).not.toHaveBeenCalled();
  });
});
