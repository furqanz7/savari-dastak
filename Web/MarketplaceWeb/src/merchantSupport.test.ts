import { afterEach, describe, expect, it, vi } from "vitest";
import { callMerchantSupport, createSupportCapability, parseSupportPage, parseSupportRecoveryCode, parseSupportTicket, readMerchantSupportConnection, supportRecoveryCode } from "./merchantSupport";
const id = "11111111-1111-4111-8111-111111111111";
const row = { id, category: "ACCESS", subject: "Store access help", status: "OPEN", version: 1, createdAt: "2026-10-21T01:00:00Z", updatedAt: "2026-10-21T01:00:00Z" };
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });
describe("Merchant support client", () => {
  it("needs only the browser-safe API configuration, not VAPID, variant or sign-in", () => {
    expect(readMerchantSupportConnection({ VITE_SUPABASE_URL: "https://example.supabase.co/", VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_example" }, { development: false, pageUrl: "https://merchant.example/merchant-support" })).toEqual({ supabaseUrl: "https://example.supabase.co", publishableKey: "sb_publishable_example" });
  });
  it("allows only explicit loopback development fixture endpoints", () => {
    const env = { VITE_SUPABASE_URL: "http://127.0.0.1:56430", VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_fixture", VITE_MERCHANT_SUPPORT_LOCAL_API: "1" };
    expect(readMerchantSupportConnection(env, { development: true, pageUrl: "http://127.0.0.1:5178/merchant-support" }).supabaseUrl).toBe(env.VITE_SUPABASE_URL);
    expect(() => readMerchantSupportConnection(env, { development: false, pageUrl: "http://127.0.0.1:5178/merchant-support" })).toThrow();
    expect(() => readMerchantSupportConnection(env, { development: true, pageUrl: "https://merchant.example/merchant-support" })).toThrow();
    expect(() => readMerchantSupportConnection({ ...env, VITE_MERCHANT_SUPPORT_LOCAL_API: undefined }, { development: true, pageUrl: "http://127.0.0.1:5178/merchant-support" })).toThrow();
  });
  it("rejects service secrets and non-Supabase hosted destinations", () => {
    expect(() => readMerchantSupportConnection({ VITE_SUPABASE_URL: "https://example.supabase.co", VITE_SUPABASE_PUBLISHABLE_KEY: "sb_secret_private" }, { development: false, pageUrl: "https://merchant.example" })).toThrow(/secret key/);
    expect(() => readMerchantSupportConnection({ VITE_SUPABASE_URL: "https://untrusted.example", VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_example" }, { development: false, pageUrl: "https://merchant.example" })).toThrow();
  });
  it("creates independent 256-bit capabilities and round trips the private code", () => {
    const first = createSupportCapability(); const next = createSupportCapability();
    expect(first.token).toMatch(/^[a-f0-9]{64}$/); expect(first.token).not.toBe(next.token); expect(first.ticketId).not.toBe(next.ticketId);
    expect(parseSupportRecoveryCode(supportRecoveryCode(first))).toEqual(first);
  });
  it.each(["", "123", `${id}.short`, `${id}.${"a".repeat(64)}.extra`, `invalid.${"a".repeat(64)}`])("rejects invalid recovery code %s", value => {
    expect(parseSupportRecoveryCode(value)).toBeUndefined();
  });
  it("parses a typed thread without rendering markup", () => {
    expect(parseSupportTicket({ ...row, messages: [{ id, side: "SUPPORT", body: "<script>test</script>", createdAt: row.createdAt, status: "RESOLVED" }] }).messages[0].body).toBe("<script>test</script>");
  });
  it.each([{ ...row, messages: null }, { ...row, status: "__proto__", messages: [] }, { ...row, version: "1", messages: [] }])("rejects invalid server data", value => {
    expect(() => parseSupportTicket(value)).toThrow();
  });
  it("uses a bounded 40-row page with a sentinel", () => {
    expect(parseSupportPage({ tickets: Array(41).fill(row) })).toEqual({ tickets: Array(40).fill(row), more: true });
    expect(() => parseSupportPage({ tickets: Array(42).fill(row) })).toThrow();
  });
  it("sends the capability in a no-store POST, never the URL", async () => {
    const fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ...row, messages: [] }))); vi.stubGlobal("fetch", fetch);
    await callMerchantSupport({ supabaseUrl: "https://example.supabase.co", publishableKey: "public" }, { operation: "read", ticketId: id, token: "a".repeat(64) });
    expect(fetch.mock.calls[0][0]).toBe("https://example.supabase.co/functions/v1/merchant-support");
    expect(fetch.mock.calls[0][1]).toMatchObject({ method: "POST", cache: "no-store", referrerPolicy: "no-referrer" });
    expect(fetch.mock.calls[0][1].headers.Authorization).toBeUndefined();
  });
  it("does not replay a timed-out mutation automatically", async () => {
    vi.useFakeTimers();
    const fetch = vi.fn((_url, init) => new Promise((_resolve, reject) => init.signal.addEventListener("abort", () => reject(new Error("timeout")))));
    vi.stubGlobal("fetch", fetch);
    const result = expect(callMerchantSupport({ supabaseUrl: "https://example.supabase.co", publishableKey: "public" }, { operation: "create" })).rejects.toThrow(/not confirm/);
    await vi.advanceTimersByTimeAsync(15_001); await result; expect(fetch).toHaveBeenCalledTimes(1);
  });
  it("preserves specific stale/access errors but not raw provider data", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({ error: { code: "support_stale", message: "sensitive detail" } }), { status: 409 })));
    await expect(callMerchantSupport({ supabaseUrl: "https://example.supabase.co", publishableKey: "public" }, { operation: "reply" })).rejects.toThrow(/conversation changed/);
  });
  it.each(["hello\u0000there", "hello\ud800there", "hello\udc00there"])("rejects unsupported text locally without an HTTP write: %s", async message => {
    const fetch = vi.fn(); vi.stubGlobal("fetch", fetch);
    await expect(callMerchantSupport({ supabaseUrl: "https://example.supabase.co", publishableKey: "public" }, { operation: "create", message })).rejects.toMatchObject({ code: "support_invalid" });
    expect(fetch).not.toHaveBeenCalled();
  });
  it("keeps a busy write retry explicit and preserves its payload", async () => {
    const input = { operation: "reply", requestId: id, message: "Please check again", version: 1 };
    const original = { ...input };
    const fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ error: { code: "support_busy" } }), { status: 409 })); vi.stubGlobal("fetch", fetch);
    await expect(callMerchantSupport({ supabaseUrl: "https://example.supabase.co", publishableKey: "public" }, input)).rejects.toThrow(/safe to retry/);
    expect(input).toEqual(original); expect(fetch).toHaveBeenCalledTimes(1);
  });
});
