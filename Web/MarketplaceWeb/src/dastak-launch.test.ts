import { describe, expect, it, vi } from "vitest";
import {
  canCompleteDastakLaunch,
  dastakLaunchVideos,
  nextDastakLaunchIndex,
  takeNextDastakLaunchVideo,
} from "./dastak-launch";

describe("Dastak launch video rotation", () => {
  it("starts at the first video, advances, and wraps", () => {
    expect(nextDastakLaunchIndex(null, 3)).toBe(0);
    expect(nextDastakLaunchIndex("0", 3)).toBe(1);
    expect(nextDastakLaunchIndex("1", 3)).toBe(2);
    expect(nextDastakLaunchIndex("2", 3)).toBe(0);
  });

  it("recovers from invalid storage", () => {
    expect(nextDastakLaunchIndex("invalid", 3)).toBe(0);
    expect(nextDastakLaunchIndex("9", 3)).toBe(0);
    expect(nextDastakLaunchIndex("0", 0)).toBe(0);
  });

  it("uses a deterministic fallback when storage is unavailable", () => {
    const storage = {
      getItem: vi.fn(() => { throw new Error("denied"); }),
      setItem: vi.fn(),
    };
    expect(takeNextDastakLaunchVideo(storage, "dastak-customer")).toBe(dastakLaunchVideos[0]);
  });
});

describe("Dastak launch completion", () => {
  it("waits for both the minimum duration and media readiness", () => {
    expect(canCompleteDastakLaunch({
      minimumDurationElapsed: false,
      mediaState: "ready",
      reducedMotion: false,
      maximumDurationElapsed: false,
    })).toBe(false);
    expect(canCompleteDastakLaunch({
      minimumDurationElapsed: true,
      mediaState: "ready",
      reducedMotion: false,
      maximumDurationElapsed: false,
    })).toBe(true);
  });

  it("falls back after failure or the maximum duration", () => {
    expect(canCompleteDastakLaunch({
      minimumDurationElapsed: true,
      mediaState: "failed",
      reducedMotion: false,
      maximumDurationElapsed: false,
    })).toBe(true);
    expect(canCompleteDastakLaunch({
      minimumDurationElapsed: true,
      mediaState: "loading",
      reducedMotion: false,
      maximumDurationElapsed: true,
    })).toBe(true);
  });

  it("does not wait for video when reduced motion is enabled", () => {
    expect(canCompleteDastakLaunch({
      minimumDurationElapsed: true,
      mediaState: "loading",
      reducedMotion: true,
      maximumDurationElapsed: false,
    })).toBe(true);
  });
});
