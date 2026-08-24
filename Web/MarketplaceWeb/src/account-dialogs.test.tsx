import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { DeleteAccountDialog } from "./DeleteAccountDialog";

describe("customer account dialogs", () => {
  it("requires an explicit typed deletion confirmation in a modal alert", () => {
    const markup = renderToStaticMarkup(<DeleteAccountDialog
      busy={false}
      identities={[]}
      reauthenticationRequired={false}
      warning="Permanent deletion warning"
      onConfirm={() => undefined}
      onDismiss={() => undefined}
      onReauthenticate={() => undefined}
    />);

    expect(markup).toContain('role="alertdialog"');
    expect(markup).toContain('aria-modal="true"');
    expect(markup).toContain("Type <strong>DELETE</strong>");
    expect(markup).toContain("Permanent deletion warning");
    expect(markup).toContain("disabled");
  });

  it("offers only already-linked provider identities for recent verification", () => {
    const markup = renderToStaticMarkup(<DeleteAccountDialog
      busy={false}
      identities={[{ provider: "google", linkKind: "ORIGIN", linkedAt: "2026-08-24T08:00:00Z" }]}
      reauthenticationRequired
      warning="Permanent deletion warning"
      onConfirm={() => undefined}
      onDismiss={() => undefined}
      onReauthenticate={() => undefined}
    />);

    expect(markup).toContain("Continue with Google");
    expect(markup).not.toContain("Continue with Apple");
    expect(markup).not.toContain("Type <strong>DELETE</strong>");
  });

  it("keeps modal keyboard containment, scroll lock, and focus restoration", () => {
    const source = readFileSync(new URL("./useModalDialog.ts", import.meta.url), "utf8");
    expect(source).toContain('document.body.style.overflow = "hidden"');
    expect(source).toContain('event.key === "Escape"');
    expect(source).toContain('event.key !== "Tab"');
    expect(source).toContain("opener?.focus()");
  });

  it("keeps the premium Account hierarchy responsive and accessible", () => {
    const catalogue = readFileSync(new URL("./CatalogueView.tsx", import.meta.url), "utf8");
    const addresses = readFileSync(new URL("./CustomerAddressBookSheet.tsx", import.meta.url), "utf8");
    const styles = readFileSync(new URL("./design/customer.css", import.meta.url), "utf8");

    expect(catalogue).toContain('className="customer-profile-meta"');
    expect(catalogue).toContain("Identity, sessions, privacy and access");
    expect(addresses).toContain("useModalDialog<HTMLElement>");
    expect(styles).toContain(".customer-profile-card::before");
    expect(styles).toContain("width: min(100%, 780px)");
    expect(styles).toContain("@media (prefers-reduced-motion: reduce)");
  });
});
