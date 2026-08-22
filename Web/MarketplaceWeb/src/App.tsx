import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { LogOut, RefreshCw, ShieldCheck, UserRound } from "lucide-react";
import { createClient, type Provider, type Session } from "@supabase/supabase-js";
import { completeProfile, isValidProfile, resolveAccess, type AccessResult } from "./access";
import { AccountActionDialog } from "./AccountActionDialog";
import { endCurrentAccountSession, getAccountSessions, webSessionMetadata } from "./accountSessions";
import {
  callbackFailureMessage,
  readAuthCallback,
  sanitizedAuthCallbackUrl,
} from "./auth-callback";
import { shouldPreserveAuthenticatedView } from "./auth-state";
import { canCompleteDastakLaunch, dastakLaunchVideos, takeNextDastakLaunchVideo } from "./dastak-launch";
import { readAppConfig } from "./config";
import { PhoneNumberField } from "./PhoneNumberField";

const AdminDashboard = lazy(() => import("./AdminDashboard").then((module) => ({ default: module.AdminDashboard })));
const DastakCustomerView = lazy(() => import("./DastakCustomerView").then((module) => ({ default: module.DastakCustomerView })));
const DeliveryPartnerApplicationForm = lazy(() => import("./DeliveryPartnerApplicationForm").then((module) => ({ default: module.DeliveryPartnerApplicationForm })));
const DeliveryPartnerView = lazy(() => import("./DeliveryPartnerView").then((module) => ({ default: module.DeliveryPartnerView })));
const MerchantApplicationForm = lazy(() => import("./MerchantApplicationForm").then((module) => ({ default: module.MerchantApplicationForm })));
const MerchantOrdersView = lazy(() => import("./MerchantOrdersView").then((module) => ({ default: module.MerchantOrdersView })));
const SavariRideView = lazy(() => import("./SavariRideView").then((module) => ({ default: module.SavariRideView })));

const config = readAppConfig({
  VITE_APP_VARIANT: import.meta.env.VITE_APP_VARIANT,
  VITE_SUPABASE_URL: import.meta.env.VITE_SUPABASE_URL,
  VITE_SUPABASE_PUBLISHABLE_KEY: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
});
document.title = `${config.brand} ${config.roleLabel}`;
const initialAuthCallback = readAuthCallback(window.location.href);
const supabase = createClient(config.supabaseUrl, config.supabasePublishableKey, {
  auth: {
    detectSessionInUrl: true,
    persistSession: true,
    autoRefreshToken: true,
    flowType: initialAuthCallback?.kind === "implicit" ? "implicit" : "pkce",
  },
});
const dastakLaunchVideo = config.product === "dastak"
  ? takeNextDastakLaunchVideo(dastakLaunchStorage(), config.variant)
  : dastakLaunchVideos[0];

function dastakLaunchStorage() {
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

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
  const [showsDastakLaunch, setShowsDastakLaunch] = useState(config.product === "dastak");
  const knownUserId = useRef<string | undefined>(undefined);
  const registeredSessionToken = useRef<string | undefined>(undefined);
  const hasHandledAuthCallback = useRef(false);
  const finishDastakLaunch = useCallback(() => setShowsDastakLaunch(false), []);
  const usesFullDastakAuth = config.product === "dastak"
    && (view.phase === "loading" || view.phase === "signed_out" || view.phase === "profile");

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
      if (initialAuthCallback && !hasHandledAuthCallback.current && (event === "INITIAL_SESSION" || event === "SIGNED_IN")) {
        hasHandledAuthCallback.current = true;
        window.history.replaceState(window.history.state, "", sanitizedAuthCallbackUrl(window.location.href));
        if (!session) {
          setView({ phase: "error", message: callbackFailureMessage(initialAuthCallback) });
          return;
        }
      }
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

  useEffect(() => {
    if (config.product !== "dastak") return;
    const session = view.phase === "ready" || view.phase === "restricted" ? view.session : undefined;
    if (!session || registeredSessionToken.current === session.access_token) return;
    registeredSessionToken.current = session.access_token;
    void getAccountSessions({
      accessToken: session.access_token,
      supabaseUrl: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      ...webSessionMetadata(config.roleLabel),
    }).catch(() => {
      registeredSessionToken.current = undefined;
    });
  }, [view]);

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

  const signOut = useCallback(async () => {
    setBusy(true);
    const { data } = await supabase.auth.getSession();
    if (data.session?.access_token && config.product === "dastak") {
      try {
        await endCurrentAccountSession({
          accessToken: data.session.access_token,
          supabaseUrl: config.supabaseUrl,
          publishableKey: config.supabasePublishableKey,
        });
      } catch {
        // Local sign-out must remain available if the session registry is offline.
      }
    }
    const { error } = await supabase.auth.signOut({ scope: "local" });
    setBusy(false);
    if (error) setView({ phase: "error", message: "Dastak could not sign you out. Try again." });
  }, []);

  return (
    <main className={`app product-${config.product}`}>
      {!usesFullDastakAuth && <header className="topbar" aria-hidden={showsDastakLaunch || undefined}>
        <Brand />
        {view.phase !== "signed_out" && view.phase !== "loading" && !(
          config.product === "dastak" &&
          (view.phase === "ready" || view.phase === "restricted")
        ) && (
          <button className="icon-button" type="button" onClick={signOut} disabled={busy} aria-label="Sign out" title="Sign out">
            <LogOut size={19} />
          </button>
        )}
      </header>}

      <section
        aria-hidden={showsDastakLaunch || undefined}
        className={`content ${usesFullDastakAuth ? "dastak-auth-content" : ""} ${view.phase === "ready" && ["dastak-admin", "dastak-customer", "dastak-delivery", "dastak-merchant", "savari-passenger"].includes(config.variant) ? "workspace-content" : ""}`}
      >
        {view.phase === "loading" && <Loading />}
        {view.phase === "signed_out" && <SignIn busy={busy} onSignIn={signIn} />}
        {view.phase === "profile" && (
          <ProfileForm session={view.session} onComplete={() => evaluate(view.session)} onSignOut={signOut} />
        )}
        {view.phase === "ready" && <Suspense fallback={<Loading />}><Ready access={view.access} email={view.session.user.email} session={view.session} onSignOut={signOut} /></Suspense>}
        {view.phase === "restricted" && (
          <Suspense fallback={<Loading />}><Restricted access={view.access} session={view.session} onSubmitted={() => evaluate(view.session)} onSignOut={signOut} /></Suspense>
        )}
        {view.phase === "error" && (
          <ErrorState
            message={view.message}
            onRetry={() => evaluate(view.session ?? null)}
            onSignOut={view.session ? signOut : undefined}
          />
        )}
      </section>
      {showsDastakLaunch && (
        <DastakLaunchScreen videoSource={dastakLaunchVideo} onFinished={finishDastakLaunch} />
      )}
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
  if (config.product === "dastak") {
    return (
      <div className="brand-lockup brand-lockup-dastak">
        <span>
          <strong>Dastak <span className="brand-urdu" lang="ur">دستک</span></strong>
          <small>{config.roleLabel}</small>
        </span>
      </div>
    );
  }

  return (
    <div className="brand-lockup">
      <span className="brand-mark" aria-hidden="true">{config.brand[0]}</span>
      <span>
        <strong>{config.brand}</strong>
        <small>{config.roleLabel}</small>
      </span>
    </div>
  );
}

function SignIn({ busy, onSignIn }: { busy: boolean; onSignIn: (provider: Provider) => void }) {
  return (
    <div className={`auth-layout ${config.product === "dastak" ? "dastak-auth-layout" : ""}`}>
      <div className="auth-copy">
        {config.product === "dastak" ? (
          <>
            <h1>Dastak <span className="brand-urdu" lang="ur">دستک</span></h1>
            <p>{config.roleLabel}</p>
          </>
        ) : (
          <>
            <p className="eyebrow">{config.roleLabel}</p>
            <h1>{config.brand}</h1>
            <p>Sign in to continue.</p>
          </>
        )}
      </div>
      <div className="auth-actions" aria-label="Sign in options">
        <button className="provider-button apple" type="button" disabled={busy} onClick={() => onSignIn("apple")}>
          <span aria-hidden="true">&#63743;</span> Continue with Apple
        </button>
        <button className="provider-button google" type="button" disabled={busy} onClick={() => onSignIn("google")}>
          <GoogleLogo /> Continue with Google
        </button>
      </div>
    </div>
  );
}

function DastakLaunchScreen({
  videoSource,
  onFinished,
}: {
  videoSource: string;
  onFinished: () => void;
}) {
  const reducedMotion = usePrefersReducedMotion();
  const [mediaState, setMediaState] = useState<"loading" | "ready" | "failed">("loading");
  const [minimumDurationElapsed, setMinimumDurationElapsed] = useState(false);
  const [maximumDurationElapsed, setMaximumDurationElapsed] = useState(false);
  const [isLeaving, setIsLeaving] = useState(false);

  useEffect(() => {
    const minimumTimer = window.setTimeout(
      () => setMinimumDurationElapsed(true),
      reducedMotion ? 650 : 1200,
    );
    const maximumTimer = window.setTimeout(() => setMaximumDurationElapsed(true), 2500);
    return () => {
      window.clearTimeout(minimumTimer);
      window.clearTimeout(maximumTimer);
    };
  }, [reducedMotion]);

  useEffect(() => {
    if (isLeaving || !canCompleteDastakLaunch({
      minimumDurationElapsed,
      mediaState,
      reducedMotion,
      maximumDurationElapsed,
    })) return;
    setIsLeaving(true);
  }, [isLeaving, maximumDurationElapsed, mediaState, minimumDurationElapsed, reducedMotion]);

  useEffect(() => {
    if (!isLeaving) return;
    const timer = window.setTimeout(onFinished, reducedMotion ? 0 : 280);
    return () => window.clearTimeout(timer);
  }, [isLeaving, onFinished, reducedMotion]);

  return (
    <section
      className={`dastak-launch ${mediaState === "ready" ? "is-ready" : ""} ${isLeaving ? "is-leaving" : ""}`}
      role="status"
      aria-label="Opening Dastak"
    >
      {!reducedMotion && mediaState !== "failed" && (
        <video
          className="dastak-launch-video"
          autoPlay
          muted
          loop
          playsInline
          preload="auto"
          aria-hidden="true"
          onCanPlay={() => setMediaState("ready")}
          onError={() => setMediaState("failed")}
        >
          <source src={videoSource} type="video/mp4" />
        </video>
      )}
      <div className="dastak-launch-content">
        <p><span className="dastak-launch-latin">Dastak</span> <span className="dastak-launch-urdu" lang="ur">دستک</span></p>
        <small>{config.roleLabel}</small>
        <i aria-hidden="true" />
      </div>
    </section>
  );
}

function usePrefersReducedMotion() {
  const query = "(prefers-reduced-motion: reduce)";
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches);

  useEffect(() => {
    const mediaQuery = window.matchMedia(query);
    const update = () => setMatches(mediaQuery.matches);
    mediaQuery.addEventListener("change", update);
    return () => mediaQuery.removeEventListener("change", update);
  }, []);

  return matches;
}

function GoogleLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" className="google-logo">
      <path fill="#4285F4" d="M21.35 12.2c0-.7-.06-1.37-.16-2.01H12v3.82h5.27c-.23 1.24-.96 2.29-2.04 2.99v2.49h3.3c1.93-1.77 3.04-4.38 3.04-7.29z" />
      <path fill="#34A853" d="M12 22c2.7 0 4.97-.89 6.62-2.41l-3.3-2.49c-.92.62-2.1.99-3.32.99-2.56 0-4.73-1.73-5.51-4.06H3.07v2.55A9.99 9.99 0 0 0 12 22z" />
      <path fill="#FBBC05" d="M6.49 13.99A5.99 5.99 0 0 1 6.18 12c0-.69.12-1.36.31-1.99V7.46H3.07A9.99 9.99 0 0 0 2 12c0 1.61.39 3.13 1.07 4.54l3.42-2.55z" />
      <path fill="#EA4335" d="M12 5.99c1.47 0 2.79.51 3.83 1.52l2.87-2.87C16.96 2.99 14.69 2 12 2A9.99 9.99 0 0 0 3.07 7.46l3.42 2.55C7.27 7.72 9.44 5.99 12 5.99z" />
    </svg>
  );
}

function ProfileForm({ session, onComplete, onSignOut }: {
  session: Session;
  onComplete: () => void;
  onSignOut: () => void;
}) {
  const suggestedName = useMemo(() => {
    const metadata = session.user.user_metadata as Record<string, unknown>;
    return typeof metadata.full_name === "string" ? metadata.full_name : "";
  }, [session.user.user_metadata]);
  const [displayName, setDisplayName] = useState(suggestedName);
  const [phoneNumber, setPhoneNumber] = useState("+91");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [confirmingSignOut, setConfirmingSignOut] = useState(false);
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

  return <>
    <form className={`form-panel${config.product === "dastak" ? " dastak-profile-form" : ""}`} onSubmit={submit}>
      {config.product === "dastak" ? <header className="dastak-profile-heading">
        <div className="dastak-profile-topline">
          <p className="dastak-profile-wordmark"><span>Dastak</span> <span lang="ur">دستک</span></p>
          <button type="button" onClick={() => setConfirmingSignOut(true)}>Use a different account</button>
        </div>
        <p className="eyebrow">{config.roleLabel}</p>
        <h1>Your details</h1>
        <p>Tell us how to address you and how an active delivery can reach you.</p>
      </header> : <>
        <div className="section-icon"><UserRound size={22} /></div>
        <p className="eyebrow">Account details</p>
        <h1>Complete your profile</h1>
      </>}
      <label>
        Full name
        <input autoComplete="name" value={displayName} maxLength={80} onChange={(event) => setDisplayName(event.target.value)} />
      </label>
      <div className="phone-field-group">
        <label htmlFor="profile-phone">Phone number</label>
        <PhoneNumberField value={phoneNumber} onChange={setPhoneNumber} id="profile-phone" />
      </div>
      <small id="phone-hint">Used only when an active delivery requires contact. It is not used to sign in.</small>
      {error && <p className="error-text" role="alert">{error}</p>}
      <button className="primary-button" disabled={!valid || busy} type="submit">Save and continue</button>
    </form>
    {confirmingSignOut && <AccountActionDialog
      action="sign-out"
      message="You'll need to sign in again to continue with a different account."
      onConfirm={onSignOut}
      onDismiss={() => setConfirmingSignOut(false)}
    />}
  </>;
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
  if (config.variant === "dastak-admin") {
    return (
      <AdminDashboard
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
  onSignOut,
}: {
  access: AccessResult;
  session: Session;
  onSubmitted: () => void;
  onSignOut: () => void;
}) {
  if (config.variant === "dastak-merchant") {
    return (
      <RestrictedShell onSignOut={onSignOut}>
        <MerchantApplicationForm
          accessState={access.state === "pending" || access.state === "suspended"
            ? access.state
            : "denied"}
          client={supabase}
          session={session}
          supabaseUrl={config.supabaseUrl}
          publishableKey={config.supabasePublishableKey}
          onSubmitted={onSubmitted}
          onSessionExpired={onSignOut}
        />
      </RestrictedShell>
    );
  }
  if (config.variant === "dastak-delivery" && access.state === "denied") {
    return (
      <RestrictedShell onSignOut={onSignOut}>
        <DeliveryPartnerApplicationForm
          client={supabase}
          session={session}
          supabaseUrl={config.supabaseUrl}
          publishableKey={config.supabasePublishableKey}
          onSubmitted={onSubmitted}
          onSessionExpired={onSignOut}
        />
      </RestrictedShell>
    );
  }
  const title = access.state === "pending" ? "Approval pending" : access.state === "suspended" ? "Account suspended" : "Access not approved";
  return (
    <RestrictedShell onSignOut={onSignOut}>
      <div className="status-panel">
        <div className="section-icon"><ShieldCheck size={23} /></div>
        <p className="eyebrow">{config.roleLabel}</p>
        <h1>{title}</h1>
        <p>{access.message}</p>
        <button className="secondary-button" type="button" onClick={onSubmitted}><RefreshCw size={17} /> Check status</button>
      </div>
    </RestrictedShell>
  );
}

function RestrictedShell({ children, onSignOut }: { children: ReactNode; onSignOut: () => void }) {
  const [confirmingSignOut, setConfirmingSignOut] = useState(false);
  return <>
    <div className="restricted-account-layout">
      {children}
      <button className="restricted-account-switch" type="button" onClick={() => setConfirmingSignOut(true)}>
        <LogOut size={17} /> Use a different account
      </button>
    </div>
    {confirmingSignOut && <AccountActionDialog
      action="sign-out"
      message="You'll need to sign in again to continue with a different account."
      onConfirm={onSignOut}
      onDismiss={() => setConfirmingSignOut(false)}
    />}
  </>;
}

function ErrorState({ message, onRetry, onSignOut }: {
  message: string;
  onRetry: () => void;
  onSignOut?: () => void;
}) {
  const [confirmingSignOut, setConfirmingSignOut] = useState(false);
  return (
    <>
      <div className="status-panel">
        <p className="eyebrow">Connection error</p>
        <h1>Unable to continue</h1>
        <p className="error-text" role="alert">{message}</p>
        <button className="secondary-button" type="button" onClick={onRetry}><RefreshCw size={17} /> Retry</button>
        {onSignOut && <button className="restricted-account-switch" type="button" onClick={() => setConfirmingSignOut(true)}>
          <LogOut size={17} /> Use a different account
        </button>}
      </div>
      {confirmingSignOut && onSignOut && <AccountActionDialog
        action="sign-out"
        message="You'll need to sign in again to continue with a different account."
        onConfirm={onSignOut}
        onDismiss={() => setConfirmingSignOut(false)}
      />}
    </>
  );
}

function Loading() {
  return <div className="loading" role="status"><span /> Checking account</div>;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Something went wrong.";
}
