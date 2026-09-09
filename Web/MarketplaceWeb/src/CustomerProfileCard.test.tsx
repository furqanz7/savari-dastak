import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { CustomerProfileCard } from "./CustomerProfileCard";

const props = { initials: "AN", displayName: "A very long customer name", phoneNumber: "+919876543210",
  email: "a-long-private-relay-address@privaterelay.appleid.com", signInLabel: "Apple sign-in", savedPlaceCount: 1, onEdit: () => undefined };

describe("Account visible profile card", () => {
  it("preserves the full name, phone and email in distinct presentation rows", () => {
    const html = renderToStaticMarkup(<CustomerProfileCard {...props} />);
    expect(html).toContain(props.displayName);
    expect(html).toContain(props.phoneNumber);
    expect(html).toContain(props.email);
    expect(html).toContain('class="customer-identity-phone"');
    expect(html).toContain('class="customer-identity-email"');
    expect(html).toContain('aria-hidden="true">AN</span>');
  });

  it("keeps the whole card as one keyboard-accessible edit action without nested controls", () => {
    const onEdit = vi.fn();
    const element = CustomerProfileCard({ ...props, onEdit });
    expect(element.type).toBe("button");
    expect(element.props.type).toBe("button");
    element.props.onClick();
    expect(onEdit).toHaveBeenCalledOnce();
    const html = renderToStaticMarkup(element);
    expect(html.match(/<button/g)).toHaveLength(1);
    expect(html).toContain('aria-label="Edit profile"');
    expect(html).toContain('aria-describedby="customer-identity-name customer-identity-contacts customer-identity-meta"');
    expect(html).toContain('<span>Edit</span>');
  });

  it("shows Apple identity and correct saved-place pluralization without hiding the metadata", () => {
    const html = renderToStaticMarkup(<CustomerProfileCard {...props} />);
    expect(html).toContain('class="apple-logo"');
    expect(html).toContain("Apple sign-in");
    expect(html).toContain("1 saved place</span>");
    expect(html).toContain('class="customer-identity-meta" id="customer-identity-meta"');
    const multiple = renderToStaticMarkup(<CustomerProfileCard {...props} signInLabel="Apple + Google sign-in" savedPlaceCount={3} />);
    expect(multiple).toContain("Apple + Google sign-in");
    expect(multiple).toContain("3 saved places");
  });

  it("retains existing fallbacks without displaying an empty email row", () => {
    const html = renderToStaticMarkup(<CustomerProfileCard {...props} displayName="" phoneNumber="" email={undefined} signInLabel="Secure sign-in" savedPlaceCount={0} />);
    expect(html).toContain("Your account");
    expect(html).toContain("Add a contact number");
    expect(html).toContain("Secure sign-in");
    expect(html).toContain("0 saved places");
    expect(html).not.toContain('class="customer-identity-email"');
  });

  it("isolates the card from the old gold panel and circular mobile Edit styling", () => {
    const css = readFileSync(new URL("./design/customer-experience.css", import.meta.url), "utf8");
    const card = css.match(/\.customer-experience \.customer-identity-card \{([^}]+)\}/)?.[1];
    expect(card).toContain("background: var(--surface)");
    expect(card).toContain("color: var(--text-primary)");
    expect(card).not.toContain("var(--primary-action)");
    const edit = css.match(/\.customer-experience \.customer-identity-edit \{([^}]+)\}/)?.[1];
    expect(edit).toContain("border: 0");
    expect(edit).toContain("background: transparent");
    expect(edit).toContain("min-height: 44px");
    expect(edit).not.toContain("50%");
    expect(css).not.toMatch(/\.customer-identity-edit\s*\{[^}]*font-size: 0/);
    expect(css).toContain(".customer-identity-contacts > span > span { min-width: 0; overflow-wrap: anywhere;");
    expect(css).toContain(".customer-identity-heading { grid-template-columns: 48px minmax(0, 1fr) auto;");
    const integration = readFileSync(new URL("./CatalogueView.tsx", import.meta.url), "utf8");
    expect(integration).toContain('onEdit={() => setProfileEditorOpen(true)}');
    expect(integration).toContain('presentation="customer"');
    expect(integration).not.toContain('className="customer-profile-card"');
  });
});
