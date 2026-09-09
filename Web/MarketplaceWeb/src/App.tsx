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
import {
  ArrowRight,
  CircleAlert,
  BadgeCheck,
  LockKeyhole,
  Phone,
  LogOut,
  RefreshCw,
  ShieldCheck,
  UserRound,
} from "lucide-react";
import { createClient, type Provider, type Session } from "@supabase/supabase-js";
import {
  completeProfile,
  DastakProfileSubmissionError,
  isValidProfile,
  mustSignOutDeniedAdmin,
  ProfileSubmissionAttempt,
  profileValidation,
  resolveAccess,
  type AccessResult,
} from "./access";
import { AccountActionDialog } from "./AccountActionDialog";
import { endCurrentAccountSession, registerAccountSessionWithRetry, webSessionMetadata } from "./accountSessions";
import {
  callbackFailureMessage,
  readAuthCallback,
  sanitizedAuthCallbackUrl,
} from "./auth-callback";
import { shouldPreserveAuthenticatedView } from "./auth-state";
import { resolveAuthenticatedEmail } from "./authenticatedEmail";
import { canCompleteDastakLaunch, dastakLaunchVideos, takeNextDastakLaunchVideo } from "./dastak-launch";
import { readAppConfig } from "./config";
import { PhoneNumberField } from "./PhoneNumberField";
import { AppleLogo, GoogleLogo } from "./IdentityProviderLogos";
import { readableErrorMessage, userFacingError } from "./userFacingError";

const AdminDashboard = lazy(() => import("./AdminDashboard").then((module) => ({ default: module.AdminDashboard })));
const DastakCustomerView = lazy(() => import("./DastakCustomerView").then((module) => ({ default: module.DastakCustomerView })));
const DeliveryPartnerApplicationForm = lazy(() => import("./DeliveryPartnerApplicationForm").then((module) => ({ default: module.DeliveryPartnerApplicationForm })));
const DeliveryPartnerView = lazy(() => import("./DeliveryPartnerView").then((module) => ({ default: module.DeliveryPartnerView })));
const MerchantApplicationForm = lazy(() => import("./MerchantApplicationForm").then((module) => ({ default: module.MerchantApplicationForm })));
const MerchantOrdersView = lazy(() => import("./MerchantOrdersView").then((module) => ({ default: module.MerchantOrdersView })));
const SavariRideView = lazy(() => import("./SavariRideView").then((module) => ({ default: module.SavariRideView })));

const config = readAppConfig(import.meta.env);
document.title = `${config.brand} ${config.roleLabel}`;
document.querySelector('meta[name="description"]')?.setAttribute(
  "content",
  config.product === "dastak"
    ? `Sign in to Dastak as ${config.roleLabel}.`
    : `Sign in to Savari as ${config.roleLabel}.`,
);
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
  | { phase: "error"; session?: Session; kind: "connection" | "sign_in" | "account"; message: string };

export default function App() {
  const [view, setView] = useState<ViewState>({ phase: "loading" });
  const [busy, setBusy] = useState(false);
  const [signingInProvider, setSigningInProvider] = useState<Provider>();
  const [showsDastakLaunch, setShowsDastakLaunch] = useState(config.product === "dastak");
  const knownUserId = useRef<string | undefined>(undefined);
  const registeredSessionToken = useRef<string | undefined>(undefined);
  const hasHandledAuthCallback = useRef(false);
  const finishDastakLaunch = useCallback(() => setShowsDastakLaunch(false), []);
  const usesFullDastakAuth = config.product === "dastak"
    && (
      view.phase === "loading"
      || view.phase === "signed_out"
      || view.phase === "profile"
      || view.phase === "error"
    );
  const usesCustomerOnboarding = config.variant === "dastak-customer" && usesFullDastakAuth;

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
      else if (mustSignOutDeniedAdmin(access, config.role)) {
        knownUserId.current = undefined;
        await supabase.auth.signOut({ scope: "local" });
        setView({
          phase: "error",
          kind: "sign_in",
          message: "This email is not assigned to Dastak Admin.",
        });
      } else setView({ phase: "restricted", session, access });
    } catch (error) {
      setView({ phase: "error", session, kind: "connection", message: errorMessage(error) });
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
          setView({
            phase: "error",
            kind: "sign_in",
            message: callbackFailureMessage(initialAuthCallback),
          });
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
    const controller = new AbortController();
    registeredSessionToken.current = session.access_token;
    void registerAccountSessionWithRetry({
      accessToken: session.access_token,
      supabaseUrl: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      signal: controller.signal,
      ...webSessionMetadata(config.roleLabel),
    }).catch(() => {
      if (!controller.signal.aborted) registeredSessionToken.current = undefined;
    });
    return () => controller.abort();
  }, [view]);

  const signIn = async (provider: Provider) => {
    if (busy) return;
    setBusy(true);
    setSigningInProvider(provider);
    const { error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: `${window.location.origin}/`,
        scopes: provider === "apple" ? "name email" : undefined,
      },
    });
    if (error) {
      setBusy(false);
      setSigningInProvider(undefined);
      setView({
        phase: "error",
        kind: "sign_in",
        message: providerSignInFailure(provider, error),
      });
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
    if (error) setView({
      phase: "error",
      kind: "account",
      message: "Dastak could not sign you out. Try again.",
    });
  }, []);

  return (
    <main className={`app product-${config.product} variant-${config.variant}${usesCustomerOnboarding ? " customer-onboarding-active" : ""}`}>
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
        className={`content ${usesFullDastakAuth ? "dastak-auth-content" : ""} ${usesCustomerOnboarding ? "dastak-customer-auth-content" : ""} ${view.phase === "ready" && ["dastak-admin", "dastak-customer", "dastak-delivery", "dastak-merchant", "savari-passenger"].includes(config.variant) ? "workspace-content" : ""}`}
      >
        {view.phase === "loading" && <Loading />}
        {view.phase === "signed_out" && <SignIn busy={busy} signingInProvider={signingInProvider} onSignIn={signIn} />}
        {view.phase === "profile" && (
          <ProfileForm session={view.session} onComplete={() => evaluate(view.session)} onSignOut={signOut} />
        )}
        {view.phase === "ready" && <Suspense fallback={<Loading />}><Ready access={view.access} email={resolveAuthenticatedEmail(view.session.user)} session={view.session} onSignOut={signOut} /></Suspense>}
        {view.phase === "restricted" && (
          <Suspense fallback={<Loading />}><Restricted access={view.access} session={view.session} onSubmitted={() => evaluate(view.session)} onSignOut={signOut} /></Suspense>
        )}
        {view.phase === "error" && (
          <ErrorState
            kind={view.kind}
            message={view.message}
            onRetry={() => evaluate(view.session ?? null)}
            onSignOut={view.session ? signOut : undefined}
            supportUrl={config.legalLinks?.support}
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

function SignIn({ busy, signingInProvider, onSignIn }: {
  busy: boolean;
  signingInProvider?: Provider;
  onSignIn: (provider: Provider) => void;
}) {
  if (config.variant === "dastak-customer") {
    return <CustomerSignIn
      busy={busy}
      signingInProvider={signingInProvider}
      onSignIn={onSignIn}
    />;
  }

  const providerName = signingInProvider === "apple"
    ? "Apple"
    : signingInProvider === "google" ? "Google" : undefined;
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
      <div className="auth-actions" aria-label="Sign in options" aria-busy={busy || undefined}>
        <button className="provider-button apple" type="button" disabled={busy} onClick={() => onSignIn("apple")}>
          <AppleLogo /> {signingInProvider === "apple" ? "Opening Apple…" : "Continue with Apple"}
        </button>
        <button className="provider-button google" type="button" disabled={busy} onClick={() => onSignIn("google")}>
          <GoogleLogo /> {signingInProvider === "google" ? "Opening Google…" : "Continue with Google"}
        </button>
        <p className="auth-progress" role="status" aria-live="polite">
          {providerName ? `Opening ${providerName} securely…` : ""}
        </p>
        {config.product === "dastak" && config.legalLinks && (
          <p className="auth-legal">
            By continuing, you agree to Dastak’s{" "}
            <a href={config.legalLinks.terms} target="_blank" rel="noreferrer">Terms</a>
            {" "}and acknowledge the{" "}
            <a href={config.legalLinks.privacy} target="_blank" rel="noreferrer">Privacy Policy</a>.
            {" "}<a href={config.legalLinks.support} target="_blank" rel="noreferrer">Get help</a>
          </p>
        )}
      </div>
    </div>
  );
}

function CustomerSignIn({ busy, signingInProvider, onSignIn }: {
  busy: boolean;
  signingInProvider?: Provider;
  onSignIn: (provider: Provider) => void;
}) {
  const providerName = signingInProvider === "apple"
    ? "Apple"
    : signingInProvider === "google" ? "Google" : undefined;

  return (
    <div className="customer-onboarding customer-sign-in-layout">
      <section className="customer-onboarding-hero" aria-labelledby="customer-sign-in-title">
        <header className="customer-onboarding-brand">
          <p className="customer-onboarding-wordmark">
            <span>Dastak</span> <span lang="ur">دستک</span>
          </p>
          <span>Customer</span>
        </header>

        <div className="customer-onboarding-copy">
          <p className="eyebrow">Welcome to Dastak</p>
          <h1 id="customer-sign-in-title">Everything you need,<br /><em>thoughtfully delivered.</em></h1>
          <p>Food and everyday essentials in one basket. We secure every item before you pay.</p>
        </div>

        <ul className="customer-onboarding-promises" aria-label="Dastak promises">
          <li>
            <BadgeCheck size={18} aria-hidden="true" />
            <span><strong>Exact items</strong><small>Secured first</small></span>
          </li>
          <li>
            <ShieldCheck size={18} aria-hidden="true" />
            <span><strong>Private by design</strong><small>One protected checkout</small></span>
          </li>
        </ul>
      </section>

      <section className="customer-auth-panel" aria-labelledby="customer-auth-panel-title">
        <div className="customer-auth-panel-heading">
          <p className="eyebrow">Secure sign-in</p>
          <h2 id="customer-auth-panel-title">Your Dastak starts here.</h2>
          <p>Use Apple or Google to create or return to your account.</p>
        </div>

        <div className="auth-actions" aria-label="Sign in options" aria-busy={busy || undefined}>
          <button
            className="provider-button apple"
            type="button"
            disabled={busy}
            onClick={() => onSignIn("apple")}
          >
            <AppleLogo /> Continue with Apple
          </button>
          <button
            className="provider-button google"
            type="button"
            disabled={busy}
            onClick={() => onSignIn("google")}
          >
            <GoogleLogo /> Continue with Google
          </button>
          <p className="auth-progress" role="status" aria-live="polite">
            {providerName && <><span className="auth-inline-spinner" aria-hidden="true" />Opening {providerName} securely…</>}
          </p>
        </div>

        <p className="customer-auth-trust">
          <LockKeyhole size={16} aria-hidden="true" />
          <span>Your phone number is added later for delivery contact—not for sign-in.</span>
        </p>

        {config.legalLinks && (
          <p className="auth-legal">
            By continuing, you agree to Dastak’s{" "}
            <a href={config.legalLinks.terms} target="_blank" rel="noreferrer">Terms</a>
            {" "}and acknowledge the{" "}
            <a href={config.legalLinks.privacy} target="_blank" rel="noreferrer">Privacy Policy</a>.
            {" "}<a href={config.legalLinks.support} target="_blank" rel="noreferrer">Get help</a>
          </p>
        )}
      </section>
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

function ProfileForm({ session, onComplete, onSignOut }: {
  session: Session;
  onComplete: () => void;
  onSignOut: () => void;
}) {
  const suggestedName = useMemo(() => {
    const metadata = session.user.user_metadata as Record<string, unknown>;
    const value = typeof metadata.full_name === "string"
      ? metadata.full_name
      : typeof metadata.name === "string" ? metadata.name : "";
    const normalized = value.trim().replace(/\s+/g, " ");
    return normalized.length <= 80 ? normalized : "";
  }, [session.user.user_metadata]);
  const [displayName, setDisplayName] = useState(suggestedName);
  const [phoneNumber, setPhoneNumber] = useState(() => canonicalSessionPhone(session.user.phone) ?? "+91");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [identityRecoveryComplete, setIdentityRecoveryComplete] = useState(false);
  const [confirmingSignOut, setConfirmingSignOut] = useState(false);
  const [touched, setTouched] = useState({ name: false, phone: false });
  const submissionAttempt = useRef(new ProfileSubmissionAttempt());
  const validation = profileValidation({ displayName, phoneNumber });
  const valid = isValidProfile({ displayName, phoneNumber });
  const isCustomerProfile = config.variant === "dastak-customer";
  const provider = session.user.app_metadata.provider === "apple"
    ? "Apple"
    : session.user.app_metadata.provider === "google" ? "Google" : "your identity provider";

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (identityRecoveryComplete) {
      onSignOut();
      return;
    }
    if (!valid) {
      setTouched({ name: true, phone: true });
      return;
    }
    setBusy(true);
    setError(undefined);
    try {
      const profile = { displayName, phoneNumber };
      await completeProfile(
        supabase,
        session,
        config,
        profile,
        submissionAttempt.current.keyFor(profile),
      );
      submissionAttempt.current.reset();
      onComplete();
    } catch (submitError) {
      if (
        submitError instanceof DastakProfileSubmissionError &&
        submitError.code === "identity_reauthentication_required"
      ) {
        setIdentityRecoveryComplete(true);
        setError("Your Dastak account is recovered. Continue to sign in with your updated email.");
      } else {
        setError(errorMessage(submitError));
      }
      setBusy(false);
    }
  };

  const profileFields = <>
    <label>
      Full name
      <input
        autoComplete="name"
        value={displayName}
        maxLength={80}
        required
        disabled={busy}
        placeholder="Enter your full name"
        aria-invalid={touched.name && Boolean(validation.name) || undefined}
        aria-describedby="name-hint"
        onBlur={() => setTouched((current) => ({ ...current, name: true }))}
        onChange={(event) => setDisplayName(event.target.value)}
      />
    </label>
    <small id="name-hint" className={touched.name && validation.name ? "field-error" : undefined}>
      {touched.name && validation.name
        ? validation.name
        : isCustomerProfile
          ? "As you want it shown on your Dastak account."
          : "Use the name you want shown on your Dastak account."}
    </small>
    <div className="phone-field-group">
      <label htmlFor="profile-phone">{isCustomerProfile ? "Delivery phone" : "Phone number"}</label>
      <PhoneNumberField
        value={phoneNumber}
        onChange={setPhoneNumber}
        id="profile-phone"
        required
        disabled={busy}
        invalid={touched.phone && Boolean(validation.phone)}
        describedBy="phone-hint phone-error"
        onBlur={() => setTouched((current) => ({ ...current, phone: true }))}
      />
    </div>
    <small id="phone-hint">{isCustomerProfile ? <>
      <Phone size={13} aria-hidden="true" /> Required for your Dastak profile and active-delivery contact. No SMS verification is used.
    </> : "Required for your Dastak profile and operational contact. No SMS verification is used."}</small>
    <small id="phone-error" className="field-error" aria-live="polite">
      {touched.phone ? validation.phone ?? "" : ""}
    </small>
    {error && <div className="error-text profile-submit-error" role="alert">
      <CircleAlert size={18} aria-hidden="true" />
      <span><strong>We couldn’t continue</strong><small>{error}</small></span>
    </div>}
    <button
      className={`primary-button${isCustomerProfile ? " profile-continue-button" : ""}`}
      disabled={busy || (isCustomerProfile && !valid)}
      aria-busy={busy || undefined}
      type="submit"
    >
      {busy ? "Saving your details…" : <>
        {identityRecoveryComplete
          ? "Continue to sign in"
          : "Save and continue"}
        {isCustomerProfile && <ArrowRight size={18} aria-hidden="true" />}
      </>}
    </button>
  </>;

  return <>
    <form className={`form-panel${config.product === "dastak" ? " dastak-profile-form" : ""}${isCustomerProfile ? " dastak-customer-profile-form" : ""}`} onSubmit={submit}>
      {isCustomerProfile ? <>
        <header className="dastak-customer-profile-heading">
          <div className="dastak-profile-topline">
            <p className="dastak-profile-wordmark"><span>Dastak</span> <span lang="ur">دستک</span></p>
            <button type="button" onClick={() => setConfirmingSignOut(true)}>Use a different account</button>
          </div>
          <div className="dastak-profile-progress" aria-hidden="true"><span /><span /></div>
          <p className="eyebrow">Account setup · 2 of 2</p>
          <h1>Make Dastak yours.</h1>
          <p>Tell us what to call you and where an active delivery can reach you.</p>
        </header>
        <div className="dastak-customer-profile-card">
          <p className="dastak-profile-identity"><ShieldCheck size={17} aria-hidden="true" /> Signed in securely with {provider}</p>
          {profileFields}
        </div>
      </> : <>
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
        {profileFields}
      </>}
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
        legalLinks={config.legalLinks!}
        webPushPublicKey={config.webPushPublicKey!}
        deliveryPartnerUrl={config.deliveryPartnerUrl!}
        merchantUrl={config.merchantUrl!}
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
  if (config.variant === "dastak-delivery") {
    return (
      <RestrictedShell onSignOut={onSignOut}>
        <DeliveryPartnerApplicationForm
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

function ErrorState({ kind, message, onRetry, onSignOut, supportUrl }: {
  kind: "connection" | "sign_in" | "account";
  message: string;
  onRetry: () => void;
  onSignOut?: () => void;
  supportUrl?: string;
}) {
  const [confirmingSignOut, setConfirmingSignOut] = useState(false);
  const presentation = kind === "sign_in"
    ? { eyebrow: "Sign-in", title: "Sign-in didn’t finish", retry: "Back to sign-in" }
    : kind === "account"
      ? { eyebrow: "Account", title: "Account action didn’t finish", retry: "Try again" }
      : { eyebrow: "Connection", title: "Unable to continue", retry: "Try again" };
  return (
    <>
      <div className={`status-panel${config.variant === "dastak-customer" ? " customer-auth-status" : ""}`}>
        {config.variant === "dastak-customer" && <p className="customer-status-wordmark"><span>Dastak</span> <span lang="ur">دستک</span></p>}
        <p className="eyebrow">{presentation.eyebrow}</p>
        <h1>{presentation.title}</h1>
        <p className="error-text" role="alert">{message}</p>
        <button className="secondary-button" type="button" onClick={onRetry}><RefreshCw size={17} /> {presentation.retry}</button>
        {supportUrl && <a className="status-support-link" href={supportUrl} target="_blank" rel="noreferrer">Contact Dastak support</a>}
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
  if (config.variant === "dastak-customer") {
    return <div className="customer-auth-loading" role="status">
      <p><span>Dastak</span> <span lang="ur">دستک</span></p>
      <span aria-hidden="true" />
      <small>Checking your account securely</small>
    </div>;
  }
  return <div className="loading" role="status"><span /> Checking account</div>;
}

function canonicalSessionPhone(value?: string) {
  if (!value) return undefined;
  const normalized = value.startsWith("+") ? value : `+${value}`;
  return /^\+[1-9][0-9]{7,14}$/.test(normalized) ? normalized : undefined;
}

function errorMessage(error: unknown) {
  return userFacingError(error, "Something went wrong. Please try again.");
}

function providerSignInFailure(provider: Provider, error: unknown) {
  const providerName = provider === "apple" ? "Apple" : "Google";
  const message = readableErrorMessage(error)?.toLowerCase() ?? "";
  if (message.includes("cancel") || message.includes("denied")) {
    return `${providerName} sign-in was cancelled. No account changes were made.`;
  }
  if (message.includes("network") || message.includes("fetch") || message.includes("offline")) {
    return `Dastak could not reach ${providerName}. Check your connection and try again.`;
  }
  return `${providerName} sign-in could not be completed. Please try again.`;
}
