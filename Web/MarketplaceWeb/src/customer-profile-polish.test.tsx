import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AccountProfileSheet } from "./AccountProfileSheet";
import { CustomerHeader } from "./DastakV1CustomerExperience";

const props = { profile: { displayName: "A customer’s name", phoneNumber: "+919876543210" }, busy: false,
  onDismiss: () => undefined, onSave: async () => undefined };

describe("Customer-only final presentation polish", () => {
  it("renders one icon-only search action next to Basket at every width", () => {
    const html = renderToStaticMarkup(<CustomerHeader count={2} onAddress={props.onDismiss} onSearch={props.onDismiss} onCart={props.onDismiss} />);
    expect(html.match(/aria-label="Search Dastak"/g)).toHaveLength(1);
    expect(html).toMatch(/class="v1-header-actions"><button class="customer-header-search-icon"/);
    const search = html.match(/<button class="customer-header-search-icon".*?<\/button>/)?.[0];
    expect(search).toContain('<svg');
    expect(search).not.toContain('<span');
    expect(html).not.toContain("Search products, brands");
    expect(html).toContain('aria-label="Basket, 2 items"');
  });

  it("keeps profile values and name constraints with a labelled read-only phone", () => {
    const html = renderToStaticMarkup(<AccountProfileSheet {...props} presentation="customer" />);
    expect(html).toContain('role="dialog"');
    expect(html).toContain('aria-modal="true"');
    expect(html).toContain('aria-describedby="profile-sheet-description"');
    expect(html).toContain('for="customer-profile-name"');
    expect(html).toContain('autoComplete="name" maxLength="80" required=""');
    expect(html).toContain(props.profile.displayName);
    expect(html).toContain(`>${props.profile.phoneNumber}</output>`);
    expect(html.match(/<input/g)).toHaveLength(1);
    expect(html).toContain("Read only");
    expect(html).toContain('type="button">Cancel</button>');
    expect(html).toContain('type="submit"');
  });

  it("provides saving feedback and prevents edits or dismissal while saving", () => {
    const html = renderToStaticMarkup(<AccountProfileSheet {...props} presentation="customer" busy />);
    expect(html).toContain('aria-busy="true"');
    expect(html).toContain('role="status">Saving changes…');
    expect(html.match(/disabled=""/g)).toHaveLength(4);
  });

  it("keeps error feedback within the editor and preserves custom contact copy", () => {
    const html = renderToStaticMarkup(<AccountProfileSheet {...props} presentation="customer" error="Please try again." contactMessage="Contact our support team." />);
    expect(html).toContain('class="customer-profile-save-error" role="alert"');
    expect(html).toContain("Please try again.");
    expect(html).toContain("Contact our support team.");
    expect(html).toContain(props.profile.displayName);
  });

  it("leaves shared non-Customer profile sheets on their original presentation", () => {
    const html = renderToStaticMarkup(<AccountProfileSheet {...props} />);
    expect(html).toContain('class="customer-sheet account-profile-sheet"');
    expect(html).toContain("Edit profile");
    expect(html).not.toContain("customer-profile-editor");
    expect(html).not.toContain("Cancel</button>");
  });

  it("bounds the editor and reserves its actions outside scrolling content", () => {
    const css = readFileSync(new URL("./design/customer-experience.css", import.meta.url), "utf8");
    expect(css).toContain(".customer-experience .customer-profile-backdrop { place-items: center;");
    expect(css).toContain("width: min(540px, 100%)");
    expect(css).toContain("max-height: calc(100dvh - 48px)");
    expect(css).toContain(".customer-profile-editor-body { flex: 1 1 auto; min-height: 0; overflow-y: auto;");
    expect(css).toContain(".customer-profile-editor-actions { flex: 0 0 auto;");
    expect(css).toContain(".customer-header-search-icon { display: grid; place-items: center; flex: 0 0 auto; width: 48px; height: 48px;");
    expect(css).not.toContain("customer-mobile-search");
    expect(css).not.toMatch(/\.v1-customer-header\s*\{[^}]*minmax\(220px/);
    const customer = readFileSync(new URL("./CatalogueView.tsx", import.meta.url), "utf8");
    const sharedRole = readFileSync(new URL("./RoleAccountView.tsx", import.meta.url), "utf8");
    expect(customer).toMatch(/<AccountProfileSheet\s+presentation="customer"/);
    expect(sharedRole).not.toContain('presentation="customer"');
  });
});
