// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";
import { AccountProfileSheet } from "./AccountProfileSheet";
import { ReimaginedModalLayer } from "./ReimaginedModalLayer";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe("Reimagined account dialog layer", () => {
  it("escapes the glass panel, isolates the app and restores focus after closing", () => {
    const host = document.createElement("div"); document.body.append(host);
    const root = createRoot(host); const dismiss = vi.fn();
    const render = (open: boolean) => <main style={{ backdropFilter: "blur(10px)" }}><button id="opener">Edit profile</button>{open ? <ReimaginedModalLayer><AccountProfileSheet presentation="customer" profile={{ displayName: "Preview", phoneNumber: "+919876543210" }} busy={false} onDismiss={dismiss} onSave={async () => {}} /></ReimaginedModalLayer> : null}</main>;
    try {
      act(() => root.render(render(false)));
      const opener = host.querySelector<HTMLButtonElement>("#opener")!; opener.focus();
      act(() => root.render(render(true)));
      const layer = document.querySelector(".reimagined-address-modal")!;
      expect(layer.parentElement).toBe(document.body);
      expect(host.querySelector('[role="dialog"]')).toBeNull();
      expect(document.activeElement?.id).toBe("customer-profile-name");
      expect(host.getAttribute("aria-hidden")).toBe("true");
      expect(document.body.style.overflow).toBe("hidden");
      act(() => document.activeElement!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
      expect(dismiss).toHaveBeenCalledOnce();
      act(() => root.render(render(false)));
      expect(document.querySelector(".reimagined-address-modal")).toBeNull();
      expect(host.getAttribute("aria-hidden")).toBeNull();
      expect(document.activeElement).toBe(opener);
      expect(document.body.style.overflow).not.toBe("hidden");
    } finally { act(() => root.unmount()); host.remove(); }
  });
  it("preserves inline rendering for the existing interface", () => {
    const host = document.createElement("div"); document.body.append(host); const root = createRoot(host);
    try {
      act(() => root.render(<ReimaginedModalLayer enabled={false}><span>Legacy dialog content</span></ReimaginedModalLayer>));
      expect(host.textContent).toBe("Legacy dialog content");
      expect(document.querySelector(".reimagined-address-modal")).toBeNull();
    } finally { act(() => root.unmount()); host.remove(); }
  });
  it("routes all existing account overlays through the embedded-only layer", () => {
    const catalogue = readFileSync("src/CatalogueView.tsx", "utf8");
    const overlays = catalogue.slice(catalogue.indexOf('<ReimaginedModalLayer enabled={overlayPresentation'), catalogue.indexOf('</ReimaginedModalLayer>'));
    for (const name of ["CustomerAddressBookSheet", "CustomerAddressSheet", "AccountProfileSheet", "AccountSessionsSheet", "AccountActionDialog", "DeleteAccountDialog", "CancellationSheet", "CustomerSupportSheet"]) expect(overlays).toContain(`<${name}`);
    expect(readFileSync("src/DastakCustomerView.tsx", "utf8")).toContain('overlayPresentation={props.embedded ? "reimagined" : undefined}');
  });
});
