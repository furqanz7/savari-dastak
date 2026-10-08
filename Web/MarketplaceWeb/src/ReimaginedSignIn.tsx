import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGroceryRoom } from "./ReimaginedGroceryRoom";
import { initialReimaginedState } from "./reimaginedState";

const signedOut = initialReimaginedState();

// App continues to own OAuth, callbacks, profile completion and session errors.
export function ReimaginedSignIn({ busy, signingInProvider, onSignIn, legalLinks }: {
  busy: boolean; onSignIn: (provider: "apple" | "google") => void;
  signingInProvider?: "apple" | "google";
  legalLinks?: { terms: string; privacy: string; support: string };
}) {
  return <ReimaginedShell state={signedOut} dispatch={() => {}} directory={[]} greeting="Welcome" locationLabel="" locationContent={null}
    onSignIn={onSignIn} signInBusy={busy} signingInProvider={signingInProvider} onOpenActiveOrder={() => {}} sectionContent={{}}
    environment={<ReimaginedGroceryRoom outside />}
    authFooter={legalLinks ? <p className="auth-legal">By continuing, you agree to Dastak’s <a href={legalLinks.terms} target="_blank" rel="noreferrer">Terms</a> and acknowledge the <a href={legalLinks.privacy} target="_blank" rel="noreferrer">Privacy Policy</a>. <a href={legalLinks.support} target="_blank" rel="noreferrer">Get help</a></p> : null}>
    {null}
  </ReimaginedShell>;
}
