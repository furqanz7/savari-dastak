export const timestamp = "2026-09-13T09:30:00Z";
export const id = (n: number) => `10000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
export const mode = new URLSearchParams(location.search).get("state") ?? "ready";
export async function read<T>(data: T, empty?: T): Promise<T> {
  if (mode === "loading") return new Promise(() => undefined);
  if (mode === "failed" || mode === "denied") throw new DastakV1RequestError(mode === "denied" ? "access_denied" : "request_timeout", "Isolated verification response", mode === "denied" ? 403 : 0);
  await new Promise((resolve) => setTimeout(resolve, 100));
  return structuredClone(mode === "empty" && empty ? empty : data);
}
import { DastakV1RequestError } from "../../src/dastakV1";
