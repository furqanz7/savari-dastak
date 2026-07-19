import { useState } from "react";
import { ImageOff, LocateFixed, MapPin, PackageOpen, RefreshCw, Store } from "lucide-react";
import {
  browseCatalogue,
  catalogueImageUrl,
  CatalogueRequestError,
  formatPrice,
  groupCatalogue,
  type CatalogueLocation,
  type GroupedCatalogueStore,
} from "./catalogue";

type Props = {
  accessToken: string;
  displayName?: string;
  supabaseUrl: string;
  publishableKey: string;
};

type SelectedLocation = { label: string; coordinates: CatalogueLocation };
type CatalogueState =
  | { phase: "idle" }
  | { phase: "loading" }
  | { phase: "ready"; stores: GroupedCatalogueStore[] }
  | { phase: "error"; code: string; message: string };

const vaniyambadi: SelectedLocation = {
  label: "Vaniyambadi",
  coordinates: { latitude: 12.6819, longitude: 78.6201 },
};

export function CatalogueView({ accessToken, displayName, supabaseUrl, publishableKey }: Props) {
  const [selectedLocation, setSelectedLocation] = useState<SelectedLocation>();
  const [state, setState] = useState<CatalogueState>({ phase: "idle" });

  const load = async (location: SelectedLocation) => {
    setSelectedLocation(location);
    setState({ phase: "loading" });
    try {
      const snapshot = await browseCatalogue({
        supabaseUrl,
        publishableKey,
        accessToken,
        location: location.coordinates,
      });
      setState({ phase: "ready", stores: groupCatalogue(snapshot) });
    } catch (error) {
      const requestError = error instanceof CatalogueRequestError
        ? error
        : new CatalogueRequestError("catalogue_unavailable", "The catalogue is unavailable right now.", 0);
      setState({ phase: "error", code: requestError.code, message: requestError.message });
    }
  };

  const useCurrentLocation = () => {
    if (!navigator.geolocation) {
      setState({ phase: "error", code: "location_unavailable", message: "This browser cannot provide your location." });
      return;
    }
    setState({ phase: "loading" });
    navigator.geolocation.getCurrentPosition(
      (position) => void load({
        label: "Current location",
        coordinates: { latitude: position.coords.latitude, longitude: position.coords.longitude },
      }),
      () => setState({
        phase: "error",
        code: "location_denied",
        message: "Location access was not allowed. You can still browse the Vaniyambadi launch area.",
      }),
      { enableHighAccuracy: true, timeout: 12_000, maximumAge: 60_000 },
    );
  };

  return (
    <div className="catalogue-shell">
      <div className="catalogue-heading">
        <div>
          <p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak customer"}</p>
          <h1>Nearby stores</h1>
          <p>{selectedLocation ? `Delivering near ${selectedLocation.label}` : "Choose where you want the order delivered."}</p>
        </div>
        <div className="location-actions" aria-label="Delivery location">
          <button type="button" className="location-button primary-location" onClick={useCurrentLocation} disabled={state.phase === "loading"}>
            <LocateFixed size={18} /> Use current location
          </button>
          <button type="button" className="location-button" onClick={() => void load(vaniyambadi)} disabled={state.phase === "loading"}>
            <MapPin size={18} /> Browse Vaniyambadi
          </button>
        </div>
      </div>

      {state.phase === "idle" && (
        <CatalogueMessage icon={<MapPin size={25} />} title="Set a delivery location">
          Stores and products are shown only for areas Dastak currently serves.
        </CatalogueMessage>
      )}
      {state.phase === "loading" && <div className="catalogue-loading" role="status"><span /> Finding nearby stores</div>}
      {state.phase === "error" && (
        <CatalogueMessage
          icon={<MapPin size={25} />}
          title={state.code === "outside_service_area" ? "Not available here yet" : "Could not load stores"}
        >
          <p>{state.message}</p>
          {selectedLocation && (
            <button type="button" className="secondary-button compact-button" onClick={() => void load(selectedLocation)}>
              <RefreshCw size={16} /> Retry
            </button>
          )}
        </CatalogueMessage>
      )}
      {state.phase === "ready" && state.stores.length === 0 && (
        <CatalogueMessage icon={<PackageOpen size={25} />} title="No stores are open yet">
          Dastak serves this area, but no merchant catalogue is currently available.
        </CatalogueMessage>
      )}
      {state.phase === "ready" && state.stores.length > 0 && (
        <div className="store-list" aria-live="polite">
          {state.stores.map((store) => <StoreCatalogue key={store.storeId} store={store} supabaseUrl={supabaseUrl} />)}
        </div>
      )}
    </div>
  );
}

function CatalogueMessage({ icon, title, children }: { icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <section className="catalogue-message">
      <span className="message-icon" aria-hidden="true">{icon}</span>
      <div><h2>{title}</h2><div className="message-body">{children}</div></div>
    </section>
  );
}

function StoreCatalogue({ store, supabaseUrl }: { store: GroupedCatalogueStore; supabaseUrl: string }) {
  const productCount = store.categories.reduce((count, category) => count + category.products.length, 0);
  return (
    <section className="store-section">
      <header className="store-heading">
        <span className="store-icon"><Store size={20} /></span>
        <div><h2>{store.name}</h2><p>{store.address}</p></div>
        <span className={`store-status ${store.acceptingOrders ? "open" : "paused"}`}>
          {store.acceptingOrders ? "Accepting orders" : "Paused"}
        </span>
      </header>
      {productCount === 0 ? <p className="store-empty">This store is preparing its catalogue.</p> : store.categories.map((category) => (
        category.products.length > 0 && <div className="category-section" key={category.categoryId}>
          <h3>{category.name}</h3>
          <div className="product-grid">
            {category.products.map((product) => {
              const imageUrl = catalogueImageUrl(supabaseUrl, product.imageObjectPath);
              return (
                <article className={`product-card ${product.availability === "out_of_stock" ? "unavailable" : ""}`} key={product.productId}>
                  <div className="product-image">
                    {imageUrl ? <img src={imageUrl} alt="" loading="lazy" /> : <ImageOff size={24} aria-label="No product image" />}
                  </div>
                  <div className="product-copy">
                    <h4>{product.name}</h4>
                    <p>{product.unitLabel}</p>
                    <strong>{formatPrice(product.price.paise)}</strong>
                    {product.availability === "out_of_stock" && <span>Out of stock</span>}
                  </div>
                </article>
              );
            })}
          </div>
        </div>
      ))}
    </section>
  );
}
