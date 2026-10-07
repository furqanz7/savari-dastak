// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { CatalogueView } from "./CatalogueView";
import { MatchingSheet, PaymentsSection } from "./DastakV1CustomerExperience";
import { workspaceOrderFixture as order } from "./reimaginedWorkspace.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const noop = () => {};
const props = { accountId: "test", accessToken: "test", client: {} as SupabaseClient, supabaseUrl: "https://example.invalid", publishableKey: "public", displayName: "Preview customer", email: "preview@example.invalid", phoneNumber: "+919876543210", orderRefreshToken: 0, section: "account" as const, onNavigate: noop, onOpenOrder: noop, onCloseOrder: noop, onOpenParcel: noop, onSignOut: noop, deliveryPartnerUrl: "/delivery", merchantUrl: "/merchant", legalLinks: { privacy: "/privacy", terms: "/terms", support: "/support" } };
const orderProps = { order, busy: false, imageUrlForLine: () => null, onDismiss: noop, onCancel: noop, onPay: noop, onReorder: noop, onRefresh: noop, onReportIssue: async () => true };

describe("dedicated Reimagined workspaces", () => {
  it("keeps personal details and saved places in Profile, not destructive controls", () => {
    const html = renderToStaticMarkup(<CatalogueView {...props} accountPane="profile" onOpenSettings={noop} />);
    expect(html).toContain('data-account-pane="profile"'); expect(html).toContain('aria-label="Your profile"');
    expect(html).toContain("Saved places"); expect(html).toContain("Wishlist"); expect(html).toContain("Open Settings");
    expect(html).not.toContain("Delete Customer"); expect(html).not.toContain("Devices and sessions"); expect(html).not.toContain("Order alerts"); expect(html).not.toContain("<h1");
  });
  it("puts alerts, sign-ins, privacy and account actions in Settings only", () => {
    const html = renderToStaticMarkup(<CatalogueView {...props} accountPane="settings" onOpenProfile={noop} />);
    expect(html).toContain('aria-label="Your settings"'); expect(html).toContain("Order alerts"); expect(html).toContain("Devices and sessions");
    expect(html).toContain("Download your data"); expect(html).toContain("Privacy Policy"); expect(html).toContain("Delete Customer"); expect(html).toContain("Edit your Profile");
    expect(html).not.toContain('aria-label="Edit profile"'); expect(html).not.toContain("Saved places</h2>"); expect(html).not.toContain("Wishlist</strong>"); expect(html).not.toContain("<h1");
  });
  it("retains the complete previous account experience when no pane is requested", () => {
    const html = renderToStaticMarkup(<CatalogueView {...props} />);
    expect(html).toContain("Your Dastak"); expect(html).toContain("Saved places"); expect(html).toContain("Order alerts"); expect(html).toContain("Delete Customer");
  });
  it("renders receipt and support in an inline order region, preserving the old modal default", () => {
    const panel = renderToStaticMarkup(<MatchingSheet {...orderProps} presentation="panel" />);
    expect(panel).toContain('role="region"'); expect(panel).not.toContain('aria-modal="true"'); expect(panel).not.toContain('class="v1-overlay"');
    expect(panel).toContain("Download receipt"); expect(panel).toContain("Get help with this order"); expect(panel).toContain("Order again"); expect(panel).toContain("₹122.00");
    expect(renderToStaticMarkup(<MatchingSheet {...orderProps} />)).toContain('aria-modal="true"');
  });
  it("never isolates navigation or locks the body for inline order details", () => {
    const host = document.createElement("div"); document.body.append(host); const root = createRoot(host); const onDismiss = vi.fn();
    document.body.style.overflow = "auto";
    try {
      act(() => root.render(<><button aria-label="Outside navigation">Home</button><MatchingSheet {...orderProps} onDismiss={onDismiss} presentation="panel" /></>));
      const outside = host.querySelector<HTMLButtonElement>('[aria-label="Outside navigation"]')!;
      expect(outside.inert).not.toBe(true); expect(outside.getAttribute('aria-hidden')).toBeNull(); expect(document.body.style.overflow).toBe("auto");
      act(() => host.querySelector('[role="region"]')!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
      expect(onDismiss).toHaveBeenCalledOnce();
      act(() => root.render(<><button aria-label="Outside navigation">Home</button><MatchingSheet {...orderProps} /></>));
      expect(document.body.style.overflow).toBe("hidden"); expect(outside.getAttribute('aria-hidden')).toBe("true");
    } finally { act(() => root.unmount()); host.remove(); document.body.style.overflow = ""; }
  });
  it("uses an inner Payments heading with unchanged confirmed amounts", () => {
    const html = renderToStaticMarkup(<PaymentsSection presentation="reimagined" orders={[order]} loading={false} onOpen={noop} onRefresh={noop} />);
    expect(html).not.toContain("<h1"); expect(html).toContain("₹122.00"); expect(html).toContain("Pay via UPI/Cash on Delivery");
  });
});
