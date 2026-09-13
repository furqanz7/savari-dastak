import { createRoot } from "react-dom/client";
import { lazy, Suspense } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import "../../src/styles.css";
import "../../src/design/customer.css";
import "../../src/design/v1-customer.css";
import "../../src/design/v1-admin.css";
import "../../src/design/v1-merchant.css";
const AdminDashboard = lazy(() => import("../../src/AdminDashboard").then((module) => ({ default: module.AdminDashboard })));

// No credentials, no remote requests, no persistent data or successful mutations.
window.fetch = async () => { throw Object.assign(new Error("Network blocked in isolated UI verification"), { code: "network_error", status: 0 }); };
const client = {
  realtime: { setAuth: async () => undefined },
  channel: () => {
    const channel = { on: () => channel, subscribe: (callback: (status: string) => void) => { queueMicrotask(() => callback("SUBSCRIBED")); return channel; } };
    return channel;
  },
  removeChannel: async () => undefined,
} as unknown as SupabaseClient;
createRoot(document.getElementById("root")!).render(<div className="app product-dastak variant-dastak-admin"><section className="content workspace-content"><Suspense fallback={<p>Loading isolated Admin preview…</p>}><AdminDashboard accessToken="fixture-only" client={client} displayName="Test Operator" email="operator@example.test" phoneNumber="" supabaseUrl="http://127.0.0.1:4179" publishableKey="fixture-only" onSignOut={() => undefined} /></Suspense></section></div>);
