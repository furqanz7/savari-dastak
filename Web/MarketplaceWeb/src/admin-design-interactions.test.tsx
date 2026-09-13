// @vitest-environment jsdom
import { act, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { AdminWorkspaceNavigation } from "./AdminWorkspaceNavigation";
import { AdminRecordDialog } from "./AdminRecordDialog";
import { AdminPrivilegedActionDialog } from "./AdminPrivilegedActionDialog";

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
let host: HTMLDivElement;
let root: Root;
beforeEach(() => { host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(async () => { await act(async () => root.unmount()); host.remove(); });

describe("Admin redesigned navigation and safe review", () => {
  it("exposes every workspace in the mobile drawer, closes after selection and restores focus", async () => {
    const onSelect = vi.fn();
    const items = ["overview", "merchants", "riders", "customers", "catalogue", "audit", "access"];
    await act(async () => root.render(<AdminWorkspaceNavigation groups={[{ label: "Reviewed workspaces", items: items.map((id) => ({ id, label: id, icon: null })) }]} selected="overview" onSelect={onSelect} displayName="Operator" role="Superadmin" />));
    const opener = host.querySelector<HTMLButtonElement>('[aria-haspopup="dialog"]')!;
    opener.focus();
    await act(async () => opener.click());
    const dialog = host.querySelector('[role="dialog"]')!;
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    expect(document.activeElement?.getAttribute("aria-label")).toBe("Close navigation");
    expect(dialog.querySelectorAll("nav button")).toHaveLength(items.length);
    expect(dialog.querySelector('[aria-current="page"]')?.textContent).toBe("overview");
    await act(async () => [...dialog.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "audit")!.click());
    expect(onSelect).toHaveBeenCalledWith("audit");
    expect(host.querySelector('[role="dialog"]')).toBeNull();
    expect(document.activeElement).toBe(opener);
  });

  it("Escape closes only the top confirmation, preserves the exact SKU editor and restores its opener", async () => {
    const dismissed = vi.fn();
    const mutate = vi.fn();
    function Editor() {
      const [confirm, setConfirm] = useState(false);
      return <AdminRecordDialog title="An unusually long exact SKU · 500 g × 2" busy={false} onDismiss={dismissed}>
        <details><summary>Product facts</summary><input aria-label="Hidden fact" /></details>
        <button onClick={() => setConfirm(true)}>Review primary replacement</button>
        {confirm ? <AdminPrivilegedActionDialog intent={{ title: "Replace primary image?", entityLabel: "Exact SKU", entityValue: "An unusually long exact SKU · SKU-123", currentState: "Primary A · version 3", resultingState: "Primary B", consequence: "Exact-SKU association is preserved.", confirmLabel: "Replace primary", confirmationValue: "SKU-123", reasonOptions: ["Correction", "Other"] }} onDismiss={() => setConfirm(false)} onConfirm={mutate} /> : null}
      </AdminRecordDialog>;
    }
    await act(async () => root.render(<Editor />));
    const review = [...host.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Review primary replacement")!;
    review.focus();
    await act(async () => review.click());
    expect(document.activeElement?.textContent).toBe("Cancel");
    expect(host.querySelector('[role="alertdialog"]')?.textContent).toContain("Primary A · version 3");
    const submit = [...host.querySelectorAll<HTMLButtonElement>('[role="alertdialog"] button')].find((button) => button.textContent?.includes("Replace primary"))!;
    expect(submit.disabled).toBe(true);
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    expect(dismissed).not.toHaveBeenCalled();
    expect(mutate).not.toHaveBeenCalled();
    expect(host.querySelector('[role="alertdialog"]')).toBeNull();
    expect(host.querySelector('[role="dialog"]')).not.toBeNull();
    expect(document.activeElement).toBe(review);
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true })));
    expect(document.activeElement?.getAttribute("aria-label")).toBe("Close product editor");
  });

  it("excludes collapsed detail inputs from the record focus loop", async () => {
    await act(async () => root.render(<AdminRecordDialog title="SKU" busy={false} onDismiss={() => undefined}>
      <details><summary>Full record</summary><input aria-label="Collapsed input" /></details>
    </AdminRecordDialog>));
    host.querySelector("summary")!.focus();
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true })));
    expect(document.activeElement?.getAttribute("aria-label")).toBe("Close product editor");
  });

  it("releases page scrolling when an editor and its confirmation unmount together", async () => {
    document.body.style.overflow = "auto";
    function Editor() {
      const [confirm, setConfirm] = useState(false);
      return <AdminRecordDialog title="Exact SKU" busy={false} onDismiss={() => undefined}>
        <button onClick={() => setConfirm(true)}>Review image</button>
        {confirm ? <AdminPrivilegedActionDialog intent={{ title: "Review image", entityLabel: "SKU", entityValue: "Exact SKU", currentState: "Primary A", resultingState: "Primary B", consequence: "Safe replacement", confirmLabel: "Replace" }} onDismiss={() => undefined} onConfirm={() => undefined} /> : null}
      </AdminRecordDialog>;
    }
    await act(async () => root.render(<Editor />));
    await act(async () => [...host.querySelectorAll<HTMLButtonElement>("button")].find((button) => button.textContent === "Review image")!.click());
    expect(document.body.style.overflow).toBe("hidden");
    await act(async () => root.render(null));
    expect(document.body.style.overflow).toBe("auto");
    document.body.style.overflow = "";
  });

  it("labels Other detail as required and keeps unknown-outcome reconciliation in the action position", async () => {
    await act(async () => root.render(<AdminPrivilegedActionDialog intent={{ title: "Review account action", entityLabel: "Account", entityValue: "Customer · exact ID", currentState: "Active sessions", resultingState: "Re-authentication required", consequence: "Revoke the reviewed sessions only.", confirmLabel: "Revoke", reasonOptions: ["Other"] }} reconciliationBlocked onReconcile={async () => undefined} onDismiss={() => undefined} onConfirm={() => undefined} />));
    expect(host.querySelector("textarea")?.required).toBe(true);
    expect(host.textContent).toContain("Detail (required for Other)");
    expect(host.textContent).toContain("Reconcile state");
    expect([...host.querySelectorAll("button")].some((button) => button.textContent === "Revoke")).toBe(false);
  });

  it("keeps styling Admin-scoped, readable and responsive without truncating product facts", () => {
    const css = readFileSync("src/design/admin-workspace.css", "utf8");
    expect(css).toContain(".variant-dastak-admin:has(.admin-console)");
    expect(css).toContain("@media (prefers-color-scheme: dark)");
    expect(css).toContain("@media (prefers-reduced-motion: reduce)");
    expect(css).toContain(".admin-confirmation-body { overflow-y: auto");
    expect(css).toContain(".admin-catalogue-browser.with-rail { height: auto; overflow: visible");
    expect(css).toContain(".admin-sku-tile-copy > strong { overflow: visible");
    expect(css).toContain(".admin-catalogue-toolbar { display: grid; min-width: 0");
    expect(css).toContain(".admin-search > svg { position: static");
    expect(css).toContain(".admin-sku-sheet > header { margin: 0;");
    expect(css).toContain(".admin-console :is(button, a, input, textarea, select, summary):focus-visible");
    const original = readFileSync("src/design/v1-admin.css", "utf8");
    expect(original).not.toMatch(/font-size: (8|9|10|11)px/);
  });
});
