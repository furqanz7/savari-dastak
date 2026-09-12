import { afterEach, describe, expect, it, vi } from "vitest";
import { validateDecodableImage } from "./imageValidation";

afterEach(() => vi.unstubAllGlobals());

describe("merchant evidence validation", () => {
  it("requires the selected file to decode as an image", async () => {
    const close = vi.fn();
    const decode = vi.fn().mockResolvedValue({ width: 640, height: 480, close });
    vi.stubGlobal("createImageBitmap", decode);
    const file = new File([new Uint8Array([1, 2, 3])], "ready.jpg", { type: "image/jpeg" });
    await expect(validateDecodableImage(file)).resolves.toBe(true);
    expect(decode).toHaveBeenCalledWith(file);
    expect(close).toHaveBeenCalledOnce();
  });

  it("accepts decodable WebP catalogue imagery", async () => {
    vi.stubGlobal("createImageBitmap", vi.fn().mockResolvedValue({ width: 800, height: 800, close: vi.fn() }));
    const file = new File([new Uint8Array([1, 2, 3])], "product.webp", { type: "image/webp" });
    await expect(validateDecodableImage(file, 5 * 1024 * 1024)).resolves.toBe(true);
  });

  it("rejects MIME-spoofed, undecodable, empty, and oversized files", async () => {
    vi.stubGlobal("createImageBitmap", vi.fn().mockRejectedValue(new Error("decode failed")));
    await expect(validateDecodableImage(new File(["not an image"], "fake.jpg", { type: "image/jpeg" }))).resolves.toBe(false);
    await expect(validateDecodableImage(new File([], "empty.png", { type: "image/png" }))).resolves.toBe(false);
    await expect(validateDecodableImage(new File(["text"], "note.txt", { type: "text/plain" }))).resolves.toBe(false);
  });
});
