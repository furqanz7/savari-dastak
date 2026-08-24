import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const favicon = readFileSync(new URL("../public/favicon.svg", import.meta.url), "utf8");
const document = readFileSync(new URL("../index.html", import.meta.url), "utf8");

describe("Dastak brand assets", () => {
  it("uses the Instrument Serif wordmark D and current brand palette as the favicon", () => {
    expect(favicon).toContain("Dastak wordmark D");
    expect(favicon).toContain('fill="#f4ebdd"');
    expect(favicon).toContain('fill="#21130e"');
    expect(favicon).toContain("Exact D outline from the bundled Instrument Serif wordmark font");
    expect(favicon).not.toContain("#0f0f10");
    expect(favicon).not.toContain("#b08d57");
  });

  it("uses a versioned favicon URL so browsers replace the previous icon", () => {
    expect(document).toContain('href="/favicon.svg?v=2"');
  });
});
