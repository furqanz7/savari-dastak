// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, expect, it, vi } from "vitest";
import { ReimaginedGroceryRoom } from "./ReimaginedGroceryRoom";

const scene = vi.hoisted(() => ({ setWeather: vi.fn(), setCounter: vi.fn(), setOutside: vi.fn(), setStaffPlayback: vi.fn(), setEyesClosed: vi.fn(), testBlink: vi.fn(), dispose: vi.fn() }));
const createScene = vi.hoisted(() => vi.fn(() => scene));
vi.mock("./reimaginedGroceryScene", () => ({ createGroceryScene: createScene }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
afterEach(() => { vi.unstubAllGlobals(); vi.clearAllMocks(); });

it("switches outside, entrance and billing without recreating the scene", async () => {
  vi.stubGlobal("WebGLRenderingContext", class {});
  const host = document.createElement("div");
  const root = createRoot(host);
  try {
    await act(async () => { root.render(<ReimaginedGroceryRoom outside />); });
    expect(createScene).toHaveBeenCalledTimes(1);
    expect(createScene.mock.calls[0]).toEqual([expect.any(HTMLCanvasElement), expect.objectContaining({ outside: true, counter: false })]);
    await act(async () => { root.render(<ReimaginedGroceryRoom />); });
    expect(scene.setOutside).toHaveBeenLastCalledWith(false);
    await act(async () => { root.render(<ReimaginedGroceryRoom atCounter />); });
    expect(scene.setCounter).toHaveBeenLastCalledWith(true);
    expect(createScene).toHaveBeenCalledTimes(1);
  } finally { act(() => root.unmount()); }
  expect(scene.dispose).toHaveBeenCalledTimes(1);
});
