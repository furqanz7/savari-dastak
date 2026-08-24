import { describe, expect, it } from "vitest";
import {
  endCurrentAccountSession,
  getAccountSessions,
  revokeAccountSession,
  signOutOtherSessions,
} from "./accountSessions";

const auth = {
  supabaseUrl: "https://example.supabase.co",
  publishableKey: "publishable-key",
  accessToken: "access-token",
};

const metadata = {
  deviceName: "Safari on iPhone",
  platform: "web" as const,
  appName: "Customer",
};

const session = {
  sessionId: "11111111-1111-4111-8111-111111111111",
  deviceName: metadata.deviceName,
  platform: metadata.platform,
  appName: metadata.appName,
  createdAt: "2026-08-16T00:00:00Z",
  lastSeenAt: "2026-08-16T01:00:00Z",
  isCurrent: true,
};

describe("account sessions", () => {
  it("loads and registers the current session", async () => {
    let body: unknown;
    const result = await getAccountSessions({ ...auth, ...metadata }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({ sessions: [session] }), { status: 200 }));
    });
    expect(body).toEqual({ operation: "snapshot", ...metadata });
    expect(result.sessions).toEqual([session]);
  });

  it("signs out other sessions and records current sign-out", async () => {
    const operations: unknown[] = [];
    const fetcher = (_input: RequestInfo | URL, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body));
      operations.push(body);
      const response = body.operation === "endCurrent" ? { ended: true } : { sessions: [session] };
      return Promise.resolve(new Response(JSON.stringify(response), { status: 200 }));
    };
    await signOutOtherSessions({ ...auth, ...metadata }, fetcher);
    await endCurrentAccountSession(auth, fetcher);
    expect(operations).toEqual([
      { operation: "signOutOthers", ...metadata },
      { operation: "endCurrent" },
    ]);
  });

  it("removes one chosen non-current session", async () => {
    let body: unknown;
    const otherSessionId = "22222222-2222-4222-8222-222222222222";
    const result = await revokeAccountSession({ ...auth, sessionId: otherSessionId }, (_input, init) => {
      body = JSON.parse(String(init?.body));
      return Promise.resolve(new Response(JSON.stringify({ sessions: [session] }), { status: 200 }));
    });
    expect(body).toEqual({ operation: "revoke", sessionId: otherSessionId });
    expect(result.sessions).toEqual([session]);
  });
});
