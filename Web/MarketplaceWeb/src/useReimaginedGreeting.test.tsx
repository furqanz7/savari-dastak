// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { reimaginedGreeting, useReimaginedGreeting } from "./useReimaginedGreeting";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root | undefined;
let host: HTMLDivElement | undefined;
function Fixture() { return <output>{useReimaginedGreeting()}</output>; }
afterEach(() => { if (root) act(() => root!.unmount()); root = undefined; host?.remove(); vi.useRealTimers(); vi.restoreAllMocks(); });
describe("device-local Reimagined greeting", () => {
  it("uses defined local morning, afternoon and evening boundaries", () => {
    for (const [hour, expected] of [[0, "Good evening"], [4, "Good evening"], [5, "Good morning"], [11, "Good morning"], [12, "Good afternoon"], [17, "Good afternoon"], [18, "Good evening"], [23, "Good evening"]] as const) {
      expect(reimaginedGreeting(new Date(2026, 9, 8, hour))).toBe(expected);
    }
  });
  it("updates at the next boundary, refreshes after focus and cleans up its single timer", () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date(2026, 9, 8, 11, 59, 59));
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    act(() => root!.render(<Fixture />));
    expect(host.textContent).toBe("Good morning"); expect(vi.getTimerCount()).toBe(1);
    act(() => vi.advanceTimersByTime(1000)); expect(host.textContent).toBe("Good afternoon");
    vi.setSystemTime(new Date(2026, 9, 8, 21));
    act(() => window.dispatchEvent(new Event("focus"))); expect(host.textContent).toBe("Good evening");
    expect(vi.getTimerCount()).toBe(1);
    act(() => vi.advanceTimersByTime(8 * 60 * 60 * 1000)); expect(host.textContent).toBe("Good morning");
    act(() => root!.unmount()); root = undefined; expect(vi.getTimerCount()).toBe(0);
  });
  it("pauses its timer while hidden and updates when visible again", () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date(2026, 9, 8, 9));
    const visibility = vi.spyOn(document, "visibilityState", "get").mockReturnValue("hidden");
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    act(() => root!.render(<Fixture />)); expect(vi.getTimerCount()).toBe(0);
    vi.setSystemTime(new Date(2026, 9, 8, 18)); visibility.mockReturnValue("visible");
    act(() => document.dispatchEvent(new Event("visibilitychange")));
    expect(host.textContent).toBe("Good evening"); expect(vi.getTimerCount()).toBe(1);
  });
});
