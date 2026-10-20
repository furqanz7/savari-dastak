import { requestDeadline } from "./requestDeadline";
import { assertBrowserSafeKey } from "./config";

export type SupportConnection = { supabaseUrl: string; publishableKey: string; accessToken?: string };
export const supportCategories = { ACCESS: "Sign-in & approval", ORDERS: "Orders & handoff", STORE: "Store & menu", EARNINGS: "Earnings & payouts", PRIVACY: "Account & privacy", OTHER: "Something else" } as const;
export const supportStatuses = { OPEN: "Open", WAITING_ON_MERCHANT: "Awaiting your reply", RESOLVED: "Resolved" } as const;
export type SupportStatus = keyof typeof supportStatuses;
export type SupportTicketRow = { id: string; category: keyof typeof supportCategories; subject: string; status: SupportStatus; version: number; createdAt: string; updatedAt: string };
export type SupportMessage = { id: string; side: "MERCHANT" | "SUPPORT"; body: string; createdAt: string; status: SupportStatus };
export type SupportTicket = SupportTicketRow & { messages: SupportMessage[] };
export type SupportCapability = { ticketId: string; token: string };
export type SupportInput = Record<string, unknown> & { operation: string };
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;

/** Public help must not depend on sign-in, VAPID or Customer legal-link setup. */
export function readMerchantSupportConnection(environment: Record<string, unknown>, context: { development: boolean; pageUrl: string }): SupportConnection {
  const supabaseUrl = typeof environment.VITE_SUPABASE_URL === "string" ? environment.VITE_SUPABASE_URL.trim().replace(/\/$/, "") : "";
  const publishableKey = typeof environment.VITE_SUPABASE_PUBLISHABLE_KEY === "string" ? environment.VITE_SUPABASE_PUBLISHABLE_KEY.trim() : "";
  let loopbackPage = false;
  try { const page = new URL(context.pageUrl); loopbackPage = ["http:", "https:"].includes(page.protocol) && ["localhost", "127.0.0.1", "[::1]"].includes(page.hostname) && !page.username && !page.password; } catch { /* Fail closed. */ }
  const local = environment.VITE_MERCHANT_SUPPORT_LOCAL_API === "1" && context.development && loopbackPage
    && /^http:\/\/(?:127\.0\.0\.1|localhost|\[::1\]):(?:54321|56430)$/.test(supabaseUrl);
  if (!local && !/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(supabaseUrl)) throw new Error("Support requires a configured Supabase endpoint.");
  assertBrowserSafeKey(publishableKey);
  return { supabaseUrl, publishableKey };
}

export function createSupportCapability(): SupportCapability {
  return { ticketId: crypto.randomUUID(), token: [...crypto.getRandomValues(new Uint8Array(32))].map(b => b.toString(16).padStart(2, "0")).join("") };
}
export function supportRecoveryCode(capability: SupportCapability) { return `${capability.ticketId}.${capability.token}`; }
export function parseSupportRecoveryCode(code: string): SupportCapability | undefined {
  const [ticketId, token, extra] = code.trim().split(".");
  return uuid.test(ticketId ?? "") && /^[a-f0-9]{64}$/.test(token ?? "") && extra === undefined ? { ticketId: ticketId.toLowerCase(), token } : undefined;
}
export class MerchantSupportError extends Error {
  constructor(public code: string) { super(supportErrorText(code)); }
}
function supportErrorText(code: string) {
  const texts: Record<string, string> = {
    support_invalid: "Check the fields and try again.", support_not_found: "That recovery code could not open a request. Check the entire code.",
    support_forbidden: "This inbox requires an active Dastak Admin role.", authentication_required: "Sign in again before opening the inbox.",
    support_stale: "This conversation changed. Refresh it before sending another reply.",
    support_conflict: "The saved request does not match. Open the request with its recovery code to check the result.",
    support_rate_limited: "Support is receiving too many requests. Keep your recovery code and try again later.",
    support_thread_full: "This conversation has reached its message limit. Start a new request and quote this request reference—not its private recovery code.",
    support_busy: "This conversation is being updated. Your original request is safe to retry in a moment.",
  };
  return Object.hasOwn(texts, code) ? texts[code] : "Support could not confirm the result. Your text is still here. Retry the same request, or refresh the conversation to check its status.";
}
export async function callMerchantSupport(connection: SupportConnection, input: SupportInput, signal?: AbortSignal): Promise<unknown> {
  // Match PostgreSQL text restrictions before retaining a permanently invalid write.
  for (const field of ["subject", "message"]) {
    const value = input[field];
    if (typeof value === "string" && !supportTextIsValid(value)) throw new MerchantSupportError("support_invalid");
  }
  const deadline = requestDeadline(signal);
  try {
    const response = await fetch(`${connection.supabaseUrl}/functions/v1/merchant-support`, {
      method: "POST", cache: "no-store", referrerPolicy: "no-referrer", signal: deadline.signal,
      headers: { "Content-Type": "application/json", apikey: connection.publishableKey,
        ...(connection.accessToken ? { Authorization: `Bearer ${connection.accessToken}` } : {}) },
      body: JSON.stringify(input),
    });
    const result = await response.json();
    if (!response.ok) throw new MerchantSupportError(typeof result?.error?.code === "string" ? result.error.code : "support_unavailable");
    return result;
  } catch (error) {
    if (error instanceof MerchantSupportError) throw error;
    throw new MerchantSupportError("support_unavailable");
  } finally { deadline.dispose(); }
}
export function supportTextIsValid(value: string) {
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code === 0) return false;
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
    } else if (code >= 0xdc00 && code <= 0xdfff) return false;
  }
  return true;
}
const object = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);
export function parseSupportRow(value: unknown): SupportTicketRow {
  if (!object(value) || typeof value.id !== "string" || !uuid.test(value.id) || typeof value.subject !== "string"
    || typeof value.category !== "string" || !Object.hasOwn(supportCategories, value.category)
    || typeof value.status !== "string" || !Object.hasOwn(supportStatuses, value.status)
    || !Number.isSafeInteger(value.version) || Number(value.version) < 1
    || typeof value.createdAt !== "string" || !Number.isFinite(Date.parse(value.createdAt))
    || typeof value.updatedAt !== "string" || !Number.isFinite(Date.parse(value.updatedAt))) throw new MerchantSupportError("support_unavailable");
  return { id: value.id, subject: value.subject, category: value.category as SupportTicketRow["category"], status: value.status as SupportStatus,
    version: Number(value.version), createdAt: value.createdAt, updatedAt: value.updatedAt };
}
export function parseSupportTicket(value: unknown): SupportTicket {
  const row = parseSupportRow(value);
  if (!object(value) || !Array.isArray(value.messages)) throw new MerchantSupportError("support_unavailable");
  const messages = value.messages.map((m: unknown): SupportMessage => {
    if (!object(m) || typeof m.id !== "string" || !uuid.test(m.id) || (m.side !== "MERCHANT" && m.side !== "SUPPORT")
      || typeof m.body !== "string" || typeof m.createdAt !== "string" || !Number.isFinite(Date.parse(m.createdAt))
      || typeof m.status !== "string" || !Object.hasOwn(supportStatuses, m.status)) throw new MerchantSupportError("support_unavailable");
    return { id: m.id, side: m.side, body: m.body, createdAt: m.createdAt, status: m.status as SupportStatus };
  });
  return { ...row, messages };
}
export function parseSupportPage(value: unknown): { tickets: SupportTicketRow[]; more: boolean } {
  if (!object(value) || !Array.isArray(value.tickets) || value.tickets.length > 41) throw new MerchantSupportError("support_unavailable");
  return { tickets: value.tickets.slice(0, 40).map(parseSupportRow), more: value.tickets.length > 40 };
}
