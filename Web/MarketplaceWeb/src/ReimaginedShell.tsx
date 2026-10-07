import { useEffect, useId, useRef, type Dispatch, type ReactNode } from "react";
import { ArrowLeft, ArrowRight, Bookmark, Check, Home, MapPin, Package, Printer, ReceiptText, Search, Settings, ShoppingBasket, ShoppingBag, UserRound, Utensils, X } from "lucide-react";
import type { ReimaginedDirectory } from "./reimaginedDirectory";
import { reimaginedEnvironment, type ReimaginedAction, type ReimaginedSection, type ReimaginedState } from "./reimaginedState";
import "./design/reimagined.css";
import { ReimaginedGroceryRoom } from "./ReimaginedGroceryRoom";
import { ReimaginedCafeRoom } from "./ReimaginedCafeRoom";

const navigation = [
  { section: "home", label: "Home", icon: Home },
  { section: "orders", label: "Orders", icon: ReceiptText },
  { section: "profile", label: "Profile", icon: UserRound },
  { section: "settings", label: "Settings", icon: Settings },
] as const;
const services = [
  { service: "food", label: "Food", icon: Utensils },
  { service: "grocery", label: "Grocery", icon: ShoppingBag },
  { service: "parcel", label: "Parcel", icon: Package },
  { service: "print", label: "Print", icon: Printer },
] as const;

type Props = {
  state: ReimaginedState;
  dispatch: Dispatch<ReimaginedAction>;
  directory: ReimaginedDirectory;
  directoryStatus?: "loading" | "ready" | "unavailable";
  onRetryDirectory?: () => void;
  displayName?: string;
  greeting: string;
  locationLabel: string;
  locationContent: ReactNode;
  onSignIn: (provider: "apple" | "google") => void;
  signInBusy?: boolean;
  signInError?: string;
  authFooter?: ReactNode;
  onOpenWishlist?: () => void;
  featureTitle?: string;
  children: ReactNode;
  searchSuggestions?: ReactNode;
  sectionContent: Partial<Record<Exclude<ReimaginedSection, "home">, ReactNode>>;
  shoppingTotalLabel?: string;
  activeOrderLabel?: string;
  onOpenActiveOrder: (id: string) => void;
  environment?: ReactNode;
};

export function ReimaginedShell({ state, dispatch, directory, directoryStatus = "ready", onRetryDirectory, displayName, greeting, locationLabel, locationContent, onSignIn, signInBusy, signInError, authFooter, onOpenWishlist, featureTitle, children, searchSuggestions, sectionContent, shoppingTotalLabel, activeOrderLabel, onOpenActiveOrder, environment }: Props) {
  const searchId = useId();
  const directoryId = useId();
  const scene = reimaginedEnvironment(state);
  const exploration = state.exploration[state.service];
  const shell = useRef<HTMLDivElement>(null);
  const lastContentButton = useRef<HTMLButtonElement | null>(null);
  const detailOpener = useRef<HTMLButtonElement | null>(null);
  const detailReturnScroll = useRef<number | null>(null);
  const cartReturnScroll = useRef<number | null>(null);
  const previousFocus = useRef({ account: state.accountId, service: state.service, section: state.section, search: exploration.searchOpen, location: state.locationOpen, detail: exploration.detailId, checkout: exploration.checkout });
  useEffect(() => {
    const content = shell.current?.querySelector<HTMLElement>(".reimagined-panel-content");
    if (content) content.scrollTop = 0;
    shell.current?.querySelector<HTMLElement>("main")?.focus({ preventScroll: true });
  }, [featureTitle]);
  useEffect(() => {
    const previous = previousFocus.current;
    previousFocus.current = { account: state.accountId, service: state.service, section: state.section, search: exploration.searchOpen, location: state.locationOpen, detail: exploration.detailId, checkout: exploration.checkout };
    const scopeChanged = previous.account !== state.accountId || previous.service !== state.service || previous.section !== state.section;
    if (scopeChanged) {
      detailOpener.current = null;
      lastContentButton.current = null;
      detailReturnScroll.current = null;
      cartReturnScroll.current = null;
      const target = state.section === "home" && exploration.searchOpen
        ? shell.current?.querySelector<HTMLElement>(".reimagined-search input")
        : state.section === "home" && exploration.detailId
          ? shell.current?.querySelector<HTMLElement>(".reimagined-detail-close")
          : undefined;
      (target ?? shell.current?.querySelector<HTMLElement>("main"))?.focus();
      return;
    }
    if (exploration.checkout !== previous.checkout) {
      const content = shell.current?.querySelector<HTMLElement>(".reimagined-panel-content");
      if (exploration.checkout) {
        detailOpener.current = null;
        detailReturnScroll.current = null;
        shell.current?.querySelector<HTMLElement>(".reimagined-continue")?.focus({ preventScroll: true });
        if (content) content.scrollTop = 0;
      } else {
        (shell.current?.querySelector<HTMLElement>(".reimagined-shopping-strip button") ?? shell.current?.querySelector<HTMLElement>("main"))?.focus({ preventScroll: true });
        if (content && cartReturnScroll.current !== null) content.scrollTop = cartReturnScroll.current;
        cartReturnScroll.current = null;
      }
    } else if (state.locationOpen && !previous.location) shell.current?.querySelector<HTMLButtonElement>('[aria-label="Close location"]')?.focus();
    else if (!state.locationOpen && previous.location) shell.current?.querySelector<HTMLButtonElement>(".reimagined-location > button")?.focus();
    else if (exploration.detailId && previous.detail !== exploration.detailId) {
      if (!previous.detail) detailOpener.current = lastContentButton.current;
      (shell.current?.querySelector<HTMLElement>(".reimagined-detail-close") ?? shell.current?.querySelector<HTMLElement>("main"))?.focus({ preventScroll: true });
      const content = shell.current?.querySelector<HTMLElement>(".reimagined-panel-content");
      if (content) content.scrollTop = 0;
    } else if (!exploration.detailId && previous.detail) {
      const opener = detailOpener.current;
      const label = opener?.getAttribute("aria-label");
      const restored = opener?.isConnected ? opener : label ? Array.from(shell.current?.querySelectorAll<HTMLButtonElement>(".reimagined-panel-content button") ?? []).find(button => button.getAttribute("aria-label") === label) : undefined;
      (restored ?? shell.current?.querySelector<HTMLElement>("main"))?.focus({ preventScroll: true });
      const content = shell.current?.querySelector<HTMLElement>(".reimagined-panel-content");
      if (content && detailReturnScroll.current !== null) content.scrollTop = detailReturnScroll.current;
      detailOpener.current = null;
      detailReturnScroll.current = null;
    } else if (!exploration.searchOpen && previous.search) shell.current?.querySelector<HTMLButtonElement>('[aria-label="Open search"]')?.focus();
  }, [state.accountId, state.service, state.section, state.locationOpen, exploration.detailId, exploration.searchOpen, exploration.checkout]);
  const quantity = state.service === "grocery"
    ? Object.values(state.shopping.retail).reduce((total, count) => total + count, 0)
    : state.shopping.food.reduce((total, line) => total + line.quantity, 0);
  const bottomRows = Number(quantity > 0 && !exploration.checkout) + Number(Boolean(state.activeOrder));
  const selectedDestination = exploration.view.kind === "browse" ? exploration.view.nodeKey : undefined;
  const title = exploration.checkout ? (state.service === "grocery" ? "Your Bucket" : "Your Food cart")
    : exploration.view.kind === "search" ? `Results for “${exploration.view.query}”`
      : selectedDestination ? directory.flatMap(section => section.destinations).find(destination => destination.key === selectedDestination)?.label ?? "Grocery"
        : state.service === "grocery" ? "Make yourself at home." : "Something good is nearby.";

  return <div ref={shell} className="reimagined" data-scene={scene} data-authenticated={Boolean(state.accountId)} data-bottom-rows={bottomRows} onClickCapture={event => {
    const button = event.target instanceof Element ? event.target.closest<HTMLButtonElement>("button") : null;
    if (!exploration.checkout && button?.closest(".reimagined-shopping-strip")) cartReturnScroll.current = exploration.detailId ? detailReturnScroll.current : shell.current?.querySelector<HTMLElement>(".reimagined-panel-content")?.scrollTop ?? null;
    if (!exploration.detailId && button?.closest(".reimagined-panel-content, .reimagined-search")) {
      lastContentButton.current = button;
      detailReturnScroll.current = shell.current?.querySelector<HTMLElement>(".reimagined-panel-content")?.scrollTop ?? null;
    }
  }} onKeyDown={event => {
    if (event.key !== "Escape" || event.defaultPrevented || !(event.target instanceof Element)) return;
    if (state.locationOpen && event.target.closest(".reimagined-location-panel")) dispatch({ type: "closeLocation" });
    else if (exploration.searchOpen && event.target.closest(".reimagined-search")) dispatch({ type: "closeSearch" });
    else if (exploration.detailId && event.target.closest(".reimagined-panel-content")) dispatch({ type: "closeDetail" });
    else return;
    event.preventDefault(); event.stopPropagation();
  }}>
    <div className="reimagined-environment" aria-hidden="true">{environment ?? (scene.startsWith("grocery") ? <ReimaginedGroceryRoom atCounter={scene === "groceryCounter"} /> : scene.startsWith("food") ? <ReimaginedCafeRoom atCounter={scene === "foodCounter"} /> : <ReimaginedSpatialStudy key={scene} />)}</div>
    <a className="reimagined-skip" href="#reimagined-main">Skip to main content</a>
    {!state.accountId ? <main id="reimagined-main" className="reimagined-auth glass-panel" tabIndex={-1}>
      <span className="reimagined-kicker">WELCOME TO</span><h1>Dastak<span>.</span></h1>
      <p>Your neighbourhood, through one door.</p>
      <div className="reimagined-auth-actions">
        <button type="button" disabled={signInBusy} onClick={() => onSignIn("apple")}>Continue with Apple</button>
        <button type="button" disabled={signInBusy} onClick={() => onSignIn("google")}>Continue with Google</button>
      </div>
      {signInBusy ? <p role="status">Opening sign in…</p> : null}
      {signInError ? <p role="alert">{signInError}</p> : null}
      {authFooter}
    </main> : <>
      <header className="reimagined-wordmark" aria-label="Dastak">Dastak<span>.</span></header>
      <nav className="reimagined-navigation glass-panel" aria-label="Dastak navigation">
        {navigation.map(({ section, label, icon: Icon }) => <button key={section} type="button" aria-current={state.section === section ? "page" : undefined} onClick={() => dispatch({ type: "navigate", section })}><Icon aria-hidden="true" size={19} /><span>{label}</span></button>)}
      </nav>
      <div className="reimagined-location">
        <button className="glass-panel" type="button" aria-expanded={state.locationOpen} onClick={() => dispatch({ type: "openLocation" })}><MapPin aria-hidden="true" size={18} /><span><small>DELIVERING TO</small>{locationLabel}</span></button>
        {state.locationOpen ? <section className="reimagined-location-panel glass-panel" aria-label="Delivery location"><div className="reimagined-panel-heading"><h2>Delivery location</h2><button type="button" aria-label="Close location" onClick={() => dispatch({ type: "closeLocation" })}><X size={18} /></button></div>{locationContent}</section> : null}
      </div>
      <aside className="reimagined-right">
        <nav className="reimagined-services glass-panel" aria-label="Choose a Dastak service">
          {services.map(({ service, label, icon: Icon }) => {
            const soon = service === "parcel" || service === "print";
            return <button type="button" key={service} disabled={soon} aria-pressed={!soon && state.service === service} aria-label={soon ? `${label}, coming soon` : label} aria-controls={service === "grocery" ? directoryId : undefined} onClick={() => dispatch({ type: "selectService", service })}><Icon aria-hidden="true" size={18} /><span>{label}</span>{soon ? <small>SOON</small> : null}</button>;
          })}
        </nav>
        {state.service === "grocery" ? <nav id={directoryId} className="reimagined-directory glass-panel" aria-label="Grocery departments and categories">
          <div className="reimagined-directory-title"><span className="reimagined-kicker">FIND YOUR AISLE</span><h2>Inside the store</h2></div>
          {directory.map(section => <section key={section.key} aria-label={section.label}><h3>{section.label}</h3>{section.destinations.map(destination => <button key={destination.key} type="button" aria-pressed={selectedDestination === destination.key} onClick={() => dispatch({ type: "openBrowseDestination", nodeKey: destination.key })}><span>{destination.label}</span><ArrowRight aria-hidden="true" size={15} /></button>)}</section>)}
          {directoryStatus === "loading" ? <p role="status">Opening the store directory…</p> : null}
          {directoryStatus === "unavailable" ? <div role="status"><p>Couldn’t load the directory right now.</p>{onRetryDirectory ? <button type="button" onClick={onRetryDirectory}>Try again</button> : null}</div> : null}
          {directoryStatus === "ready" && !directory.length ? <p>The store directory is not available yet.</p> : null}
        </nav> : null}
      </aside>
      <main id="reimagined-main" className="reimagined-main glass-panel" tabIndex={-1}>
        <header className="reimagined-main-heading">
          <div><span className="reimagined-kicker">{greeting}{displayName ? `, ${displayName}` : ""}</span><h1>{featureTitle ?? (state.section === "home" ? title : navigation.find(item => item.section === state.section)?.label)}</h1></div>
          {state.section === "home" ? <div className="reimagined-header-actions">
            {onOpenWishlist ? <button type="button" aria-label="Open Wishlist" onClick={onOpenWishlist}><Bookmark size={20} /></button> : null}
            <button type="button" aria-label="Open search" aria-expanded={exploration.searchOpen} aria-controls={searchId} onClick={() => dispatch({ type: "openSearch" })}><Search size={21} /></button>
            {state.service === "grocery" ? <button type="button" className={state.bucketPrompt ? "bucket-prompt" : undefined} aria-label={state.bucketAcquired ? "Bucket taken" : "Take a Bucket"} aria-pressed={state.bucketAcquired} onClick={() => dispatch({ type: "takeBucket" })}><ShoppingBasket size={23} />{state.bucketAcquired ? <Check className="bucket-check" size={12} /> : null}</button> : null}
          </div> : <button type="button" aria-label="Return Home" onClick={() => dispatch({ type: "navigate", section: "home" })}><X size={20} /></button>}
        </header>
        {state.bucketPrompt ? <p className="reimagined-bucket-notice" role="status">Take a bucket first. You’ll find it beside Search.</p> : null}
        {exploration.searchOpen && state.section === "home" ? <section id={searchId} className="reimagined-search glass-panel" aria-label="Search Dastak">
          <form onSubmit={event => { event.preventDefault(); dispatch({ type: "submitSearch" }); }}>
            <label className="reimagined-sr-only" htmlFor={`${searchId}-input`}>{state.service === "grocery" ? "Search Grocery" : "Search Food"}</label>
            <input id={`${searchId}-input`} type="search" autoFocus value={exploration.searchDraft} placeholder={state.service === "grocery" ? "Find a product, brand or aisle" : "Find restaurants, cafés or dishes"} onChange={event => dispatch({ type: "typeSearch", query: event.target.value })} />
            <button type="submit" aria-label="Submit search"><ArrowRight size={20} /></button>
            <button type="button" aria-label="Close search" onClick={() => dispatch({ type: "closeSearch" })}><X size={20} /></button>
          </form>
          {searchSuggestions ? <div className="reimagined-search-suggestions">{searchSuggestions}</div> : null}
        </section> : null}
        {exploration.checkout && state.section === "home" ? <button className="reimagined-continue" type="button" onClick={() => dispatch({ type: "continueShopping" })}><ArrowLeft size={17} />Continue Shopping</button> : null}
        <div className="reimagined-panel-content" tabIndex={0} role="region" aria-label={state.section === "home" ? "Shopping content" : `${state.section} content`}>{state.section === "home" ? children : sectionContent[state.section]}</div>
      </main>
      <div className="reimagined-bottom">
        {quantity > 0 && !exploration.checkout ? <section className="reimagined-shopping-strip glass-panel" aria-label={state.service === "grocery" ? "Grocery Bucket summary" : "Food cart summary"}><ShoppingBasket size={22} aria-hidden="true" /><div><strong>{quantity} {quantity === 1 ? "item" : "items"}</strong>{shoppingTotalLabel ? <span> · {shoppingTotalLabel}</span> : null}<small>{state.service === "grocery" ? "In your Bucket" : "In your Food cart"}</small></div><button type="button" onClick={() => dispatch({ type: "reviewShopping" })}>{state.service === "grocery" ? "Take to Cart" : "Review Food cart"}<ArrowRight size={17} aria-hidden="true" /></button></section> : null}
        {state.activeOrder ? <button className="reimagined-order-strip glass-panel" type="button" onClick={() => { if (state.activeOrder) onOpenActiveOrder(state.activeOrder.id); }}><span className="reimagined-order-dot" aria-hidden="true" /><span>{activeOrderLabel ?? "View your active order"}</span><ArrowRight size={16} aria-hidden="true" /></button> : null}
      </div>
    </>}
  </div>;
}

// Decorative, code-native environment: no inventory, interactive targets or commerce state.
export function ReimaginedSpatialStudy() {
  return <div className="reimagined-room">
    <div className="room-ceiling" /><div className="room-back"><div className="room-sign">Dastak<span>.</span></div><div className="room-door" /><div className="room-back-panels" /></div>
    <div className="room-lights"><i /><i /><i /></div>
    <div className="room-floor" />
    <div className="room-aisle room-aisle-left"><span className="room-aisle-sign">GROCERY</span>{[0, 1, 2].map(row => <div key={row} className="room-shelf" />)}</div>
    <div className="room-aisle room-aisle-right"><span className="room-aisle-sign">DAILY ESSENTIALS</span>{[0, 1, 2].map(row => <div key={row} className="room-shelf" />)}</div>
    <div className="room-table room-table-left"><i className="room-chair room-chair-near" /><i className="room-chair room-chair-far" /></div>
    <div className="room-table room-table-right"><i className="room-chair room-chair-near" /><i className="room-chair room-chair-far" /></div>
    <div className="room-counter-sign">ORDER · COLLECT</div>
    <div className="room-counter"><span>CHECKOUT</span><div className="room-register" /><div className="room-staff"><i /><span /></div></div>
    <div className="room-storefront"><div className="room-front-sign">Dastak<span>.</span><small>YOUR NEIGHBOURHOOD, THROUGH ONE DOOR</small></div><div className="room-awning" /><div className="room-shop-window room-shop-window-left" /><div className="room-shop-window room-shop-window-right" /><div className="room-shop-entry"><span>WELCOME</span></div><div className="room-planter room-planter-left" /><div className="room-planter room-planter-right" /></div>
    <div className="room-vignette" />
  </div>;
}
