import { useReducer, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { ReimaginedGroceryRoom } from "./ReimaginedGroceryRoom";
import { ReimaginedCafeRoom } from "./ReimaginedCafeRoom";
import { useReimaginedWeather } from "./useReimaginedWeather";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGrocery } from "./ReimaginedGrocery";
import { ReimaginedBucketReview } from "./ReimaginedBucketReview";
import { ReimaginedGroceryBilling } from "./ReimaginedGroceryBilling";
import { GroceryPaymentNotice } from "./ReimaginedCheckoutCounter";
import { grocerySubtotal } from "./reimaginedCatalogue";
import { formatV1Price } from "./dastakV1";
import type { CustomerDeliveryAddress } from "./customerAddresses";
import { groceryFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { initialReimaginedState, reimaginedEnvironment, reimaginedReducer } from "./reimaginedState";
import "./design/reimaginedEnvironmentStudy.css";

const previewTrending = { city: "Preview city", skuIds: [fixtureId(7), fixtureId(6), fixtureId(8)], preview: true };
const previewAddresses: CustomerDeliveryAddress[] = ["Home", "Office"].map((label, index) => ({
  addressId: `preview-${index}`, label: `Preview ${label}`, address: `${index + 1} Demo Street`, building: "Sample building", details: "Synthetic address",
  displayAddress: `${index + 1} Demo Street · Synthetic address`, location: { latitude: 12.97, longitude: 77.59 }, isDefault: index === 0, updatedAt: "2026-10-07",
}));

export function EnvironmentStudy() {
  const localWeather = useReimaginedWeather();
  const [showInterface, setShowInterface] = useState(false);
  const [outside, setOutside] = useState(false);
  const [cafe, setCafe] = useState(false);
  const [cafeCounter, setCafeCounter] = useState(false);
  const [blinkRequest, setBlinkRequest] = useState(0);
  const [playStaff, setPlayStaff] = useState(false);
  const [eyesClosed, setEyesClosed] = useState(false);
  const [previewAddressId, setPreviewAddressId] = useState(previewAddresses[0].addressId);
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, () => reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "local-environment-study" }));
  const atCounter = state.exploration.grocery.checkout;
  return <>
    {showInterface ? <ReimaginedShell state={state} dispatch={dispatch} directory={reimaginedDirectory(groceryFixture.map)} greeting="Welcome" displayName="Furqan" locationLabel="Local design study" locationContent={<p>Location is not connected in this study.</p>} onSignIn={() => undefined} onOpenActiveOrder={() => undefined} shoppingTotalLabel={`${formatV1Price(grocerySubtotal(state, groceryFixture) ?? 0)} estimated`} sectionContent={{ orders: <p>Local visual study only.</p>, profile: <p>No account data loaded.</p>, settings: <p>No settings are changed.</p> }}>
      <p className="environment-study-disclaimer">Real interface components · synthetic test products, not live inventory.</p>
      <ReimaginedGrocery state={state} dispatch={dispatch} data={groceryFixture} status="ready" onRetry={() => undefined} supabaseUrl="" trending={previewTrending} eligibility={() => ({ canAdd: true, maximumQuantity: 2, reason: "Local simulation only" })}
        checkoutContent={<ReimaginedGroceryBilling items={<ReimaginedBucketReview state={state} dispatch={dispatch} data={groceryFixture} canIncrease maximumQuantity={2} />} retail={state.shopping.retail} subtotal={grocerySubtotal(state, groceryFixture)}
          addresses={{ addresses: previewAddresses, selected: previewAddresses.find(address => address.addressId === previewAddressId), status: "ready", error: undefined, select: setPreviewAddressId, retry: () => undefined }} recipient={{ name: "Preview customer", phoneNumber: "+919000000000" }} online canEdit accountUrl="#preview-account"
          counter={<section className="reimagined-checkout-confirmation"><h3>Payment & confirmation</h3><GroceryPaymentNotice /><p>Local visual review only. Addresses and recipient are synthetic. No order is placed and no payment is requested.</p><button type="button" disabled>Checkout unavailable in this study</button></section>} />} />
    </ReimaginedShell> : <div className="reimagined environment-study-bare" data-scene={cafe ? "food-restaurant" : reimaginedEnvironment(state)}><div className="reimagined-environment">{cafe ? <ReimaginedCafeRoom atCounter={cafeCounter} /> : <ReimaginedGroceryRoom atCounter={atCounter} outside={outside} weather={localWeather.weather} blinkRequest={blinkRequest} playStaff={playStaff} eyesClosed={eyesClosed} />}</div></div>}
    <aside className="environment-study-tools" data-interface={showInterface} aria-label="Local environment study controls">
      <div><span>{cafe ? "DASTAK / CAFÉ INTERIOR STUDY" : "DASTAK / REALTIME STUDY 03"}</span><strong>{cafe ? "A place for good food and good company." : "A brighter, modern supermarket."}</strong><p>{cafe ? "Live 3D · Interior layout · Decorative sample menu" : "Live 3D · Prototype staff · Local test data only"}</p></div>
      <div className="environment-study-buttons">
        {outside && <button type="button" disabled={localWeather.pending} onClick={localWeather.locate}>{localWeather.pending ? "Connecting weather…" : "Use current location"}</button>}
        <button type="button" aria-pressed={cafe && !cafeCounter} onClick={() => { setCafe(true); setCafeCounter(false); setOutside(false); setShowInterface(false); }}>Café inside</button>
        {cafe && <button type="button" aria-pressed={cafeCounter} onClick={() => setCafeCounter(true)}>Café counter</button>}
        <button type="button" aria-pressed={outside} onClick={() => { setCafe(false); setShowInterface(false); setOutside(true); }}>Outside</button>
        <button type="button" aria-pressed={!cafe && !outside && !atCounter} onClick={() => { setCafe(false); setOutside(false); dispatch({ type: "continueShopping" }); }}>Entrance</button>
        {!cafe && <button type="button" aria-pressed={!outside && atCounter} onClick={() => { setOutside(false); dispatch({ type: "takeBucket" }); dispatch({ type: "setGroceryQuantity", skuId: fixtureId(6), quantity: 1 }); dispatch({ type: "reviewShopping" }); }}>Billing view</button>}
        {!cafe && <button type="button" data-panel-toggle aria-pressed={showInterface} onClick={() => { setOutside(false); setShowInterface(value => !value); }}>{showInterface ? "Hide interface" : "Show interface"}</button>}
        {!cafe && !showInterface && !outside && <button type="button" onClick={() => setBlinkRequest(value => value + 1)}>Test blink</button>}
        {!cafe && !showInterface && !outside && <button type="button" aria-pressed={playStaff} onClick={() => setPlayStaff(value => !value)}>{playStaff ? "Use motion preference" : "Play staff"}</button>}
        {!cafe && !showInterface && !outside && <button type="button" aria-pressed={eyesClosed} onClick={() => setEyesClosed(value => !value)}>{eyesClosed ? "Release eyelids" : "Hold eyes closed"}</button>}
      </div>
      {outside && <div className="environment-study-weather"><div role="status">{localWeather.status}</div><div>Approximate area shared with <a href="https://open-meteo.com/" target="_blank" rel="noreferrer">Open-Meteo</a> only after permission. Weather refreshes every 15 min.</div></div>}
      <small>{cafe ? "Local visual study · MakeHuman CC0 prototype staff. Illustrative menu, not live inventory. Ordering is not connected." : "Local prototype, not final photoreal quality. Staff: MakeHuman CC0 assets, authored and posed for this study. All shopping is simulated."}</small>
    </aside>
  </>;
}

// Reuse the local preview root during Fast Refresh rather than mounting twice.
if (import.meta.env.DEV && ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)) {
  const root: Root = import.meta.hot?.data.environmentStudyRoot ?? createRoot(document.getElementById("root")!);
  if (import.meta.hot) import.meta.hot.data.environmentStudyRoot = root;
  root.render(<EnvironmentStudy />);
} else document.body.textContent = "Local environment study disabled.";
