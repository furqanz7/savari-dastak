// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AccountSessionsSheet } from "./AccountSessionsSheet";
import { AccountSessionRequestError, getAccountSessions, revokeAccountSession, signOutOtherSessions, type AccountSessionCollection } from "./accountSessions";
vi.mock("./accountSessions", async importOriginal => ({ ...await importOriginal<typeof import("./accountSessions")>(), getAccountSessions: vi.fn(), revokeAccountSession: vi.fn(), signOutOtherSessions: vi.fn() }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const snapshot: AccountSessionCollection = { sessions: [{ sessionId: "current", deviceName: "Synthetic current", platform: "web", appName: "Customer", createdAt: "2026-10-09", lastSeenAt: "2026-10-09", isCurrent: true }, { sessionId: "other", deviceName: "Synthetic other", platform: "web", appName: "Customer", createdAt: "2026-10-09", lastSeenAt: "2026-10-09", isCurrent: false }] };
let root: Root, host: HTMLDivElement;
function deferred<T>() { let resolve!: (value: T) => void, reject!: (error: unknown) => void; const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
const dismiss = vi.fn();
async function render(token = "synthetic-token", expired = vi.fn()) { await act(async () => root.render(<AccountSessionsSheet accessToken={token} publishableKey="synthetic-key" supabaseUrl="https://example.invalid" appName="Customer" onDismiss={dismiss} onSessionExpired={expired} />)); }
beforeEach(() => { vi.mocked(getAccountSessions).mockResolvedValue(snapshot); host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); vi.resetAllMocks(); });
describe("Settings devices and sessions", () => {
  it("does not reload for a new parent callback and dismisses without changing sessions", async () => {
    await render(); await render();
    expect(getAccountSessions).toHaveBeenCalledTimes(1);
    act(() => host.querySelector<HTMLButtonElement>('[aria-label="Close sessions"]')!.click());
    expect(dismiss).toHaveBeenCalledOnce(); expect(revokeAccountSession).not.toHaveBeenCalled(); expect(signOutOtherSessions).not.toHaveBeenCalled();
  });
  it("ignores an expired response from the previous token after session rotation", async () => {
    const old = deferred<AccountSessionCollection>(); vi.mocked(getAccountSessions).mockReturnValueOnce(old.promise);
    const oldExpired = vi.fn(), currentExpired = vi.fn(); await render("old", oldExpired); await render("new", currentExpired);
    await act(async () => old.reject(new AccountSessionRequestError("expired", "Expired", 401)));
    expect(oldExpired).not.toHaveBeenCalled(); expect(currentExpired).not.toHaveBeenCalled(); expect(host.textContent).toContain("Synthetic current");
  });
  it("retains loaded devices after failed removal, offers retry and prevents duplicate operations", async () => {
    await render(); const pending = deferred<AccountSessionCollection>(); vi.mocked(revokeAccountSession).mockReturnValueOnce(pending.promise);
    const remove = host.querySelector<HTMLButtonElement>('.account-session-remove')!;
    act(() => { remove.dispatchEvent(new MouseEvent("click", { bubbles: true })); remove.dispatchEvent(new MouseEvent("click", { bubbles: true })); });
    expect(revokeAccountSession).toHaveBeenCalledTimes(1);
    await act(async () => pending.reject(new Error("Synthetic failed removal")));
    expect(host.textContent).toContain("Synthetic other"); expect(host.querySelector('[role="alert"]')).not.toBeNull();
    vi.mocked(revokeAccountSession).mockResolvedValue({ sessions: [snapshot.sessions[0]] });
    await act(async () => remove.click()); expect(host.textContent).not.toContain("Synthetic other"); expect(host.textContent).toContain("No other devices");
  });
  it("does not expire the session after the sheet has closed", async () => {
    const pending = deferred<AccountSessionCollection>(); vi.mocked(getAccountSessions).mockReturnValueOnce(pending.promise); const expired = vi.fn();
    await render("token", expired); act(() => root.render(null));
    await act(async () => pending.reject(new AccountSessionRequestError("expired", "Expired", 401)));
    expect(expired).not.toHaveBeenCalled();
  });
  it("still reports a genuinely expired current session", async () => {
    vi.mocked(getAccountSessions).mockRejectedValueOnce(new AccountSessionRequestError("expired", "Expired", 401));
    const expired = vi.fn(); await render("current-token", expired);
    expect(expired).toHaveBeenCalledOnce();
  });
  it("deduplicates signing out other devices and retains this device", async () => {
    await render(); const pending = deferred<AccountSessionCollection>(); vi.mocked(signOutOtherSessions).mockReturnValueOnce(pending.promise);
    const signOut = host.querySelector<HTMLButtonElement>('.account-sessions-action')!;
    act(() => { signOut.dispatchEvent(new MouseEvent("click", { bubbles: true })); signOut.dispatchEvent(new MouseEvent("click", { bubbles: true })); });
    expect(signOutOtherSessions).toHaveBeenCalledOnce();
    await act(async () => pending.resolve({ sessions: [snapshot.sessions[0]] }));
    expect(host.textContent).toContain("Synthetic current"); expect(host.textContent).not.toContain("Synthetic other"); expect(signOut.disabled).toBe(true);
  });
});
