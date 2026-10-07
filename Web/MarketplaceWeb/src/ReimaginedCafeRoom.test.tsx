// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it, vi } from "vitest";
import { ReimaginedCafeRoom } from "./ReimaginedCafeRoom";
const scene = vi.hoisted(() => ({ setCounter: vi.fn(), dispose: vi.fn() }));
const createScene = vi.hoisted(() => vi.fn(() => scene));
vi.mock("./reimaginedCafeScene", () => ({ createCafeScene: createScene }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
afterEach(() => { vi.unstubAllGlobals(); vi.clearAllMocks(); });

it("moves to the café counter without rebuilding the room and disposes when leaving", async () => {
  vi.stubGlobal("WebGLRenderingContext", class {});
  const host = document.createElement("div"); const root = createRoot(host);
  try {
    await act(async () => root.render(<ReimaginedCafeRoom />));
    expect(createScene).toHaveBeenCalledWith(expect.any(HTMLCanvasElement), false, expect.any(Function));
    await act(async () => root.render(<ReimaginedCafeRoom atCounter />));
    expect(scene.setCounter).toHaveBeenLastCalledWith(true); expect(createScene).toHaveBeenCalledTimes(1);
  } finally { act(() => root.unmount()); }
  expect(scene.dispose).toHaveBeenCalledTimes(1);
});
it("reports an unavailable GPU without starting a renderer", async () => {
  vi.stubGlobal("WebGLRenderingContext", undefined);
  const host = document.createElement("div"); const root = createRoot(host);
  try {
    await act(async () => root.render(<ReimaginedCafeRoom />));
    expect(host.textContent).toContain("preview unavailable"); expect(createScene).not.toHaveBeenCalled();
  } finally { act(() => root.unmount()); }
});
it("cleans up context loss without double-disposing on unmount", async () => {
  vi.stubGlobal("WebGLRenderingContext", class {});
  const host = document.createElement("div"); const root = createRoot(host);
  await act(async () => root.render(<ReimaginedCafeRoom />));
  act(() => host.querySelector("canvas")!.dispatchEvent(new Event("webglcontextlost", { cancelable: true })));
  expect(host.textContent).toContain("paused");
  act(() => root.unmount()); expect(scene.dispose).toHaveBeenCalledTimes(1);
});
