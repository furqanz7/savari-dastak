import { useState } from "react";
import { createRoot } from "react-dom/client";
import { MerchantSupportPage } from "./MerchantSupportPage";
import { AdminMerchantSupportPanel } from "./AdminMerchantSupportPanel";

const fixture = { supabaseUrl: "http://127.0.0.1:56430", publishableKey: "local-fixture-only" };
export function LocalCheck() {
  const [admin, setAdmin] = useState(false);
  return <><aside style={{ padding: 16, background: "#e7dbb9", color: "#24362f", fontFamily: "system-ui" }}>LOCAL SAMPLE DATABASE ONLY · no real account or orders · <button onClick={() => setAdmin(value => !value)}>{admin ? "Open public form" : "Open fixture Admin inbox"}</button></aside>
    {admin ? <main style={{ maxWidth: 900, padding: 28, margin: "auto" }}><AdminMerchantSupportPanel auth={{ ...fixture, accessToken: "local-fixture-admin" }} /></main> : <MerchantSupportPage connection={fixture} />}</>;
}
if (import.meta.env.DEV && ["127.0.0.1", "localhost", "[::1]"].includes(window.location.hostname)) {
  const root = createRoot(document.getElementById("root")!); root.render(<LocalCheck />);
  import.meta.hot?.dispose(() => root.unmount());
}
