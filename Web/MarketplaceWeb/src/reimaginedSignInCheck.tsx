import { useState } from "react";
import { createRoot } from "react-dom/client";
import { ReimaginedSignIn } from "./ReimaginedSignIn";
import "./styles.css";

// Isolated presentation fixture. No account, OAuth, geolocation or commerce calls.
// Not included in the deployment's index.html entry; can be built explicitly to
// verify import.meta.env.DEV=false without signing a real account out.
export function SignInCheck() {
  const [provider, setProvider] = useState<"apple" | "google">();
  return <main className="app product-dastak variant-dastak-customer customer-onboarding-active">
    <section className="content dastak-auth-content dastak-customer-auth-content">
      <ReimaginedSignIn busy={Boolean(provider)} signingInProvider={provider} onSignIn={setProvider}
        legalLinks={{ terms: "/terms", privacy: "/privacy", support: "/support" }} />
    </section>
  </main>;
}
const root = createRoot(document.getElementById("root")!);
root.render(<SignInCheck />);
import.meta.hot?.dispose(() => root.unmount());
