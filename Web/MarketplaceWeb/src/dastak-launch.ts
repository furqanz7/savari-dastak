export const dastakLaunchVideos = [
  "/launch/dastak-launch.mp4",
  "/launch/dastak-launch-2.mp4",
  "/launch/dastak-launch-3.mp4",
] as const;

type LaunchStorage = Pick<Storage, "getItem" | "setItem">;

export function nextDastakLaunchIndex(storedValue: string | null, count: number) {
  if (count <= 0) return 0;
  if (storedValue === null) return 0;

  const currentIndex = Number(storedValue);
  if (!Number.isInteger(currentIndex) || currentIndex < 0 || currentIndex >= count) return 0;
  return (currentIndex + 1) % count;
}

export function takeNextDastakLaunchVideo(storage: LaunchStorage | undefined, variant: string) {
  const key = `dastak.${variant}.launch-video-index.v1`;
  let nextIndex = 0;

  try {
    nextIndex = nextDastakLaunchIndex(storage?.getItem(key) ?? null, dastakLaunchVideos.length);
    storage?.setItem(key, String(nextIndex));
  } catch {
    // Private browsing and managed browsers can deny storage; the first video is a safe fallback.
  }

  return dastakLaunchVideos[nextIndex];
}

export function canCompleteDastakLaunch(input: {
  minimumDurationElapsed: boolean;
  mediaState: "loading" | "ready" | "failed";
  reducedMotion: boolean;
  maximumDurationElapsed: boolean;
}) {
  if (!input.minimumDurationElapsed) return false;
  return input.reducedMotion || input.maximumDurationElapsed || input.mediaState !== "loading";
}
