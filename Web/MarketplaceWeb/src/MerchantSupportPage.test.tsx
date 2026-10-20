// @vitest-environment jsdom
import { act, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { MerchantSupportPage } from "./MerchantSupportPage";
import { AdminMerchantSupportPanel } from "./AdminMerchantSupportPanel";
import { callMerchantSupport, MerchantSupportError } from "./merchantSupport";
vi.mock("./merchantSupport", async original => ({ ...await original<typeof import("./merchantSupport")>(), callMerchantSupport: vi.fn() }));
const connection = { supabaseUrl: "https://example.supabase.co", publishableKey: "public" };
const ticket = { id: "11111111-1111-4111-8111-111111111111", category: "ACCESS", subject: "Store access help", status: "OPEN", version: 1, createdAt: "2026-10-21T01:00:00Z", updatedAt: "2026-10-21T01:00:00Z", messages: [] };
let root: Root; let host: HTMLDivElement;
beforeEach(() => {
  (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.clearAllMocks(); });
async function render(node: ReactNode) { await act(async () => root.render(node)); }
async function click(text: string) { const button = [...host.querySelectorAll("button")].find(b => b.textContent?.includes(text)); if (!button) throw Error(`Missing ${text}`); await act(async () => button.click()); }
async function type(element: HTMLInputElement | HTMLTextAreaElement, value: string) {
  await act(async () => { Object.getOwnPropertyDescriptor(element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, "value")!.set!.call(element, value); element.dispatchEvent(new Event("input", { bubbles: true })); });
}
async function submit(form: HTMLFormElement) { await act(async () => form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))); }
it("shows clear public privacy warnings and no promise of email replies", async () => {
  await render(<MerchantSupportPage connection={connection} />);
  expect(host.textContent).toContain("even if you can’t sign in"); expect(host.textContent).toContain("Never send passwords");
  expect(host.querySelector('input[type="file"]')).toBeNull(); expect(host.querySelector('button[type="submit"]')).toBeNull();
  expect(callMerchantSupport).not.toHaveBeenCalled();
});
it("creates a request and shows a private code without storing it", async () => {
  vi.mocked(callMerchantSupport).mockImplementation(async (_connection, input) => ({ ...ticket, id: input.ticketId }));
  await render(<MerchantSupportPage connection={connection} />);
  await type(host.querySelector('input[minlength="5"]')!, "Store access help"); await type(host.querySelector("textarea")!, "Cannot access my store account.");
  await act(async () => host.querySelector<HTMLInputElement>('input[type="checkbox"]')!.click());
  await submit(host.querySelector("form")!);
  const sent = vi.mocked(callMerchantSupport).mock.calls[0][1];
  expect(sent.operation).toBe("create"); expect(sent.token).toMatch(/^[a-f0-9]{64}$/);
  expect(host.querySelector<HTMLInputElement>('input[readonly]')!.value).toContain(String(sent.token));
  expect(window.location.href).not.toContain(String(sent.token)); expect(localStorage.length).toBe(0); expect(sessionStorage.length).toBe(0);
  expect(host.textContent).toContain("Request received");
});
it("retains exactly the same mutation on an uncertain response", async () => {
  vi.mocked(callMerchantSupport).mockRejectedValueOnce(new MerchantSupportError("support_unavailable")).mockImplementation(async (_connection, input) => ({ ...ticket, id: input.ticketId }));
  await render(<MerchantSupportPage connection={connection} />);
  await type(host.querySelector('input[minlength="5"]')!, "Store access help"); await type(host.querySelector("textarea")!, "Cannot access my store account.");
  await act(async () => host.querySelector<HTMLInputElement>('input[type="checkbox"]')!.click()); await submit(host.querySelector("form")!);
  expect(host.textContent).toContain("Retry same request"); const original = vi.mocked(callMerchantSupport).mock.calls[0][1];
  await click("Retry same request"); expect(vi.mocked(callMerchantSupport).mock.calls[1][1]).toEqual(original);
});
it("rejects an invalid recovery code without contacting backend", async () => {
  await render(<MerchantSupportPage connection={connection} />); await click("Read a reply");
  await type(host.querySelector("input")!, "not an order number"); await submit(host.querySelector("form")!);
  expect(host.textContent).toContain("Paste the entire"); expect(callMerchantSupport).not.toHaveBeenCalled();
});
it("clears an uncertain request when reading confirms its original message ID", async () => {
  let original: Record<string, unknown> = {};
  vi.mocked(callMerchantSupport).mockImplementationOnce(async (_connection, input) => { original = input; throw new MerchantSupportError("support_unavailable"); })
    .mockImplementationOnce(async () => ({ ...ticket, id: original.ticketId, messages: [{ id: original.requestId, side: "MERCHANT", body: original.message, createdAt: ticket.createdAt, status: "OPEN" }] }));
  await render(<MerchantSupportPage connection={connection} />);
  await type(host.querySelector('input[minlength="5"]')!, "Store access help"); await type(host.querySelector("textarea")!, "Cannot access my store account.");
  await act(async () => host.querySelector<HTMLInputElement>('input[type="checkbox"]')!.click()); await submit(host.querySelector("form")!);
  await click("Check saved result"); expect(host.textContent).toContain("saved request is confirmed"); expect(host.textContent).not.toContain("Retry same request");
});
it("Admin reads a thread, escapes content and sends reply with expected version", async () => {
  vi.mocked(callMerchantSupport).mockResolvedValueOnce({ tickets: [ticket] }).mockResolvedValueOnce({ ...ticket, messages: [{ id: ticket.id, side: "MERCHANT", body: "<img src=x onerror=alert(1)>", createdAt: ticket.createdAt, status: "OPEN" }] }).mockResolvedValueOnce({ ...ticket, version: 2 });
  await render(<AdminMerchantSupportPanel auth={{ ...connection, accessToken: "fixture-only" }} />); await click("Store access help");
  expect(host.querySelector("img")).toBeNull(); expect(host.textContent).toContain("<img src=x");
  await type(host.querySelector("textarea")!, "Please use your original sign-in identity."); await submit(host.querySelector("form")!);
  expect(vi.mocked(callMerchantSupport).mock.calls.at(-1)?.[1]).toMatchObject({ operation: "adminReply", ticketId: ticket.id, version: 1, status: "WAITING_ON_MERCHANT" });
  expect(host.textContent).toContain("No email or push was sent");
});
it("Admin keeps last successful inbox visible when refresh fails", async () => {
  vi.mocked(callMerchantSupport).mockResolvedValueOnce({ tickets: [ticket] }).mockRejectedValueOnce(new MerchantSupportError("support_unavailable"));
  await render(<AdminMerchantSupportPanel auth={{ ...connection, accessToken: "fixture-only" }} />); await click("Refresh inbox");
  expect(host.textContent).toContain("Store access help"); expect(host.querySelector('[role="alert"]')).not.toBeNull();
});
