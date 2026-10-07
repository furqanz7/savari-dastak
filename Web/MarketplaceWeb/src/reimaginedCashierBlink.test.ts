import { describe, expect, it } from "vitest";
import { createBlinkPlayback, createEyelidBuffer } from "./reimaginedCashierBlink";

describe("visible blink playback", () => {
  it("keeps a blink closed through missed body draws, then smoothly reopens", () => {
    const blink = createBlinkPlayback(true);
    expect(blink(4.6)).toBe(0);
    expect(blink(5.2)).toBe(1);
    expect(blink(5.8)).toBe(1);
    expect(blink(6.2)).toBe(1);
    blink.markClosedRendered(6.2);
    expect(blink(6.24)).toBe(1);
    expect(blink(6.35)).toBeCloseTo(.5);
    expect(blink(6.5)).toBe(0);
    expect(blink(11.6)).toBe(1);
  });
  it("resets pending closure when returning to a paused/rest pose", () => {
    const blink = createBlinkPlayback(true);
    expect(blink(5.2)).toBe(1);
    expect(blink(0)).toBe(0);
    expect(blink(0)).toBe(0);
  });
  it("renders closure even when slow frames straddle the whole blink", () => {
    const blink = createBlinkPlayback();
    expect(blink(4.6)).toBe(0);
    expect(blink(5.2)).toBe(1);
    expect(blink(5.5)).toBe(0);
    expect(blink(11.9)).toBe(1);
    expect(blink(12.2)).toBe(0);
  });
  it("preserves smooth normal playback and an open reduced-motion pose", () => {
    const blink = createBlinkPlayback();
    expect(blink(0)).toBe(0);
    expect(blink(4.84)).toBeCloseTo(.5);
    expect(blink(4.9)).toBe(1);
    expect(blink(5.1)).toBeLessThan(.1);
    expect(blink(0)).toBe(0);
    expect(blink(0)).toBe(0);
  });
});

describe("sparse eyelid deformation before skinning", () => {
  it("changes only affected coordinates and restores the original without drift", () => {
    const base = new Float32Array([0, 1, 2, 3, 4, 5]);
    const blink = createEyelidBuffer(base, [[0, .8, 2, 3, 4, 5], [0, 1, 2, 3, 3.8, 5]]);
    for (let i = 0; i < 100; i++) { blink.update(1); blink.update(.5); blink.update(0); }
    expect(blink.data).toEqual(base);
    blink.update(1);
    expect(blink.data[1]).toBeCloseTo(.8);
    expect(blink.data[4]).toBeCloseTo(3.8);
    expect([blink.data[0], blink.data[2], blink.data[3], blink.data[5]]).toEqual([0, 2, 3, 5]);
    expect(base).toEqual(new Float32Array([0, 1, 2, 3, 4, 5]));
  });
  it("bounds the weight and rejects incompatible target data", () => {
    const blink = createEyelidBuffer([1], [[0]]);
    blink.update(2); expect(blink.data[0]).toBe(0);
    blink.update(NaN); expect(blink.data[0]).toBe(1);
    expect(() => createEyelidBuffer([1], [[0, 1]])).toThrow("size mismatch");
  });
});
