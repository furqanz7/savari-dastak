import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { LogOut, RefreshCw, ShieldCheck, UserRound } from "lucide-react";
import { createClient, type Provider, type Session } from "@supabase/supabase-js";
import { completeProfile, isValidProfile, resolveAccess, type AccessResult } from "./access";
import { shouldPreserveAuthenticatedView } from "./auth-state";
import { DastakCustomerView } from "./DastakCustomerView";
import { AdminDashboard } from "./AdminDashboard";
import { DeliveryPartnerApplicationForm } from "./DeliveryPartnerApplicationForm";
import { DeliveryPartnerView } from "./DeliveryPartnerView";
import { readAppConfig } from "./config";
import { MerchantApplicationForm } from "./MerchantApplicationForm";
import { MerchantOrdersView } from "./MerchantOrdersView";
import { SavariRideView } from "./SavariRideView";

const config = readAppConfig({
  VITE_APP_VARIANT: import.meta.env.VITE_APP_VARIANT,
  VITE_SUPABASE_URL: import.meta.env.VITE_SUPABASE_URL,
  VITE_SUPABASE_PUBLISHABLE_KEY: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
});
document.title = `${config.brand} ${config.roleLabel}`;
const supabase = createClient(config.supabaseUrl, config.supabasePublishableKey, {
  auth: {
    detectSessionInUrl: true,
    persistSession: true,
    autoRefreshToken: true,
  },
});

type ViewState =
  | { phase: "loading" }
  | { phase: "signed_out" }
  | { phase: "profile"; session: Session }
  | { phase: "ready"; session: Session; access: AccessResult }
  | { phase: "restricted"; session: Session; access: AccessResult }
  | { phase: "error"; session?: Session; message: string };

export default function App() {
  const [view, setView] = useState<ViewState>({ phase: "loading" });
  const [busy, setBusy] = useState(false);
  const knownUserId = useRef<string | undefined>(undefined);

  const evaluate = useCallback(async (session: Session | null) => {
    if (!session) {
      knownUserId.current = undefined;
      setView({ phase: "signed_out" });
      return;
    }
    knownUserId.current = session.user.id;
    setView({ phase: "loading" });
    try {
      const access = await resolveAccess(supabase, session, config);
      if (access.state === "signed_out") {
        await supabase.auth.signOut({ scope: "local" });
        setView({ phase: "signed_out" });
      } else if (access.state === "needs_profile") setView({ phase: "profile", session });
      else if (access.state === "active") setView({ phase: "ready", session, access });
      else setView({ phase: "restricted", session, access });
    } catch (error) {
      setView({ phase: "error", session, message: errorMessage(error) });
    }
  }, []);

  useEffect(() => {
    let active = true;
    const { data } = supabase.auth.onAuthStateChange((event, session) => {
      if (!active) return;
      if (shouldPreserveAuthenticatedView(event, session, knownUserId.current)) {
        setView((current) => updateViewSession(current, session));
        return;
      }
      void evaluate(session);
    });
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, [evaluate]);

  const signIn = async (provider: Provider) => {
    setBusy(true);
    const { error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: `${window.location.origin}/`,
        scopes: provider === "apple" ? "name email" : undefined,
      },
    });
    if (error) {
      setBusy(false);
      setView({ phase: "error", message: error.message });
    }
  };

  const signOut = async () => {
    setBusy(true);
    await supabase.auth.signOut();
    setBusy(false);
  };

  return (
    <main className={`app product-${config.product}`}>
      <header className="topbar">
        <Brand />
        {view.phase !== "signed_out" && view.phase !== "loading" && !(
          ["dastak-customer", "dastak-merchant"].includes(config.variant) &&
          view.phase === "ready"
        ) && (
          <button className="icon-button" type="button" onClick={signOut} disabled={busy} aria-label="Sign out" title="Sign out">
            <LogOut size={19} />
          </button>
        )}
      </header>

      <section className={`content ${view.phase === "ready" && ["dastak-admin", "dastak-customer", "dastak-delivery", "dastak-merchant", "savari-passenger"].includes(config.variant) ? "workspace-content" : ""}`}>
        {view.phase === "loading" && <Loading />}
        {view.phase === "signed_out" && <SignIn busy={busy} onSignIn={signIn} />}
        {view.phase === "profile" && (
          <ProfileForm session={view.session} onComplete={() => evaluate(view.session)} />
        )}
        {view.phase === "ready" && <Ready access={view.access} email={view.session.user.email} session={view.session} onSignOut={signOut} />}
        {view.phase === "restricted" && (
          <Restricted access={view.access} session={view.session} onSubmitted={() => evaluate(view.session)} />
        )}
        {view.phase === "error" && (
          <ErrorState message={view.message} onRetry={() => evaluate(view.session ?? null)} />
        )}
      </section>
    </main>
  );
}

function updateViewSession(view: ViewState, session: Session): ViewState {
  switch (view.phase) {
    case "profile":
    case "ready":
    case "restricted":
    case "error":
      return { ...view, session };
    default:
      return view;
  }
}

function Brand() {
  return (
    <div className="brand-lockup">
      <span className="brand-mark" aria-hidden="true">{config.brand[0]}</span>
      <span>
        <strong>{config.brand}{config.product === "dastak" && <span className="brand-urdu" lang="ur"> دستک</span>}</strong>
        <small>{config.roleLabel}</small>
      </span>
    </div>
  );
}

function SignIn({ busy, onSignIn }: { busy: boolean; onSignIn: (provider: Provider) => void }) {
  return (
    <div className="auth-layout">
      <div className="auth-copy">
        <p className="eyebrow">{config.roleLabel}</p>
        <h1>{config.brand}</h1>
        <p>Sign in to continue.</p>
      </div>
      <div className="auth-actions" aria-label="Sign in options">
        <button className="provider-button apple" type="button" disabled={busy} onClick={() => onSignIn("apple")}>
          <span aria-hidden="true">&#63743;</span> Continue with Apple
        </button>
        <button className="provider-button google" type="button" disabled={busy} onClick={() => onSignIn("google")}>
          <span className="google-g" aria-hidden="true">G</span> Continue with Google
        </button>
      </div>
    </div>
  );
}

function ProfileForm({ session, onComplete }: { session: Session; onComplete: () => void }) {
  const suggestedName = useMemo(() => {
    const metadata = session.user.user_metadata as Record<string, unknown>;
    return typeof metadata.full_name === "string" ? metadata.full_name : "";
  }, [session.user.user_metadata]);
  const [displayName, setDisplayName] = useState(suggestedName);
  const [phoneNumber, setPhoneNumber] = useState("+91");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const valid = isValidProfile({ displayName, phoneNumber });

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid) return;
    setBusy(true);
    setError(undefined);
    try {
      await completeProfile(supabase, session, config, { displayName, phoneNumber });
      onComplete();
    } catch (submitError) {
      setError(errorMessage(submitError));
      setBusy(false);
    }
  };

  return (
    <form className="form-panel" onSubmit={submit}>
      <div className="section-icon"><UserRound size={22} /></div>
      <p className="eyebrow">Account details</p>
      <h1>Complete your profile</h1>
      <label>
        Full name
        <input autoComplete="name" value={displayName} maxLength={100} onChange={(event) => setDisplayName(event.target.value)} />
      </label>
      <label>
        Phone number
        <input type="tel" inputMode="tel" autoComplete="tel" value={phoneNumber} onChange={(event) => setPhoneNumber(event.target.value)} aria-describedby="phone-hint" />
      </label>
      <small id="phone-hint">Include country code, for example +91.</small>
      {error && <p className="error-text" role="alert">{error}</p>}
      <button className="primary-button" disabled={!valid || busy} type="submit">Save and continue</button>
    </form>
  );
}

function Ready({ access, email, session, onSignOut }: {
  access: AccessResult;
  email?: string;
  session: Session;
  onSignOut: () => void;
}) {
  if (config.variant === "savari-passenger") {
    return (
      <SavariRideView
        accessToken={session.access_token}
        displayName={access.profile?.displayName}
        supabaseUrl={config.supabaseUrl}
        publishableKey={config.supabasePublishableKey}
      />
    );
  }
  if (config.variant === "dastak-customer") {
    return (
      <DastakCustomerView
        accessToken={session.access_token}
        displayName={access.profile?.displayName}
        email={email}
        phoneNumber={access.profile?.phoneNumber}
        supabaseUrl={config.supabaseUrl}
        publishableKey={config.supabasePublishableKey}
        onSignOut={onSignOut}
      />
    );
  }
  if (config.variant === "dastak-merchant") {
    return (
      <MerchantOrdersView
        accessToken={session.access_token}
        accountId={session.user.id}
        client={supabase}
        displayName={access.profile?.displayName}
        email={email}
        phoneNumber={access.profile?.phoneNumber}
        supabaseUrl={config.supabaseUrl}
        publishableKey={config.supabasePublishableKey}
        onSignOut={onSignOut}
      />
    );
  }
  if (config.variant === "dastak-delivery") {
    return (
      <DeliveryPartnerView
        accessToken={session.access_token}
        displayName={access.profile?.displayName}
        supabaseUrl={config.supabaseUrl}
        publishableKey={config.supabasePublishableKey}
      />
    );
  }
  if (config.variant === "dastak-admin") {
    return (
      <AdminDashboard
        accessToken={session.access_token}
        displayName={access.profile?.displayName}
        supabaseUrl={config.supabaseUrl}
        publishableKey={config.supabasePublishableKey}
      />
    );
  }
  return (
    <div className="status-panel">
      <div className="section-icon success"><ShieldCheck size={23} /></div>
      <p className="eyebrow">{config.roleLabel}</p>
      <h1>{access.profile?.displayName ? `Hello, ${access.profile.displayName}` : "Account ready"}</h1>
      <dl className="account-list">
        <div><dt>Status</dt><dd>Active</dd></div>
        {email && <div><dt>Email</dt><dd>{email}</dd></div>}
        {access.profile?.phoneNumber && <div><dt>Phone</dt><dd>{access.profile.phoneNumber}</dd></div>}
      </dl>
    </div>
  );
}

function Restricted({
  access,
  session,
  onSubmitted,
}: {
  access: AccessResult;
  session: Session;
  onSubmitted: () => void;
}) {
  if (config.variant === "dastak-merchant" && access.state === "denied") {
    return (
      <MerchantApplicationForm
        client={supabase}
        session={session}
        supabaseUrl={config.supabaseUrl}
        publishableKey={config.supabasePublishableKey}
        onSubmitted={onSubmitted}
      />
    );
  }
  if (config.variant === "dastak-delivery" && access.state === "denied") {
    return (
      <DeliveryPartnerApplicationForm
        client={supabase}
        session={session}
        supabaseUrl={config.supabaseUrl}
        publishableKey={config.supabasePublishableKey}
        onSubmitted={onSubmitted}
      />
    );
  }
  const title = access.state === "pending" ? "Approval pending" : access.state === "suspended" ? "Account suspended" : "Access not approved";
  return (
    <div className="status-panel">
      <div className="section-icon"><ShieldCheck size={23} /></div>
      <p className="eyebrow">{config.roleLabel}</p>
      <h1>{title}</h1>
      <p>{access.message}</p>
    </div>
  );
}

function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="status-panel">
      <p className="eyebrow">Connection error</p>
      <h1>Unable to continue</h1>
      <p className="error-text" role="alert">{message}</p>
      <button className="secondary-button" type="button" onClick={onRetry}><RefreshCw size={17} /> Retry</button>
    </div>
  );
}

function Loading() {
  return <div className="loading" role="status"><span /> Checking account</div>;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Something went wrong.";
}
