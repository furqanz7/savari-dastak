import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AppleLogo, GoogleLogo } from "./IdentityProviderLogos";

describe("identity provider logos", () => {
  it("renders an accessible-hidden, cross-platform Apple SVG using the button color", () => {
    const markup = renderToStaticMarkup(<AppleLogo />);

    expect(markup).toContain('class="apple-logo"');
    expect(markup).toContain('aria-hidden="true"');
    expect(markup).toContain('fill="currentColor"');
    expect(markup).not.toContain("&#63743;");
  });

  it("preserves the four-color Google mark", () => {
    const markup = renderToStaticMarkup(<GoogleLogo />);

    expect(markup).toContain('class="google-logo"');
    expect(markup.match(/<path/g)).toHaveLength(4);
  });

  it("keeps the Dastak Apple label contrasted in both color schemes", () => {
    const styles = readFileSync(new URL("./styles.css", import.meta.url), "utf8");
    const appleRule = styles.match(/\.product-dastak \.provider-button\.apple \{([^}]+)\}/)?.[1];

    expect(appleRule).toContain("background: var(--text-primary)");
    expect(appleRule).toContain("color: var(--primary-action-foreground)");
    expect(appleRule).not.toContain("color: var(--dastak-icon-background)");
  });
});
