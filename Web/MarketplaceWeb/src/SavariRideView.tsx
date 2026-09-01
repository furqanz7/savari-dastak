import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Bike, CarFront, LocateFixed, MapPin, Navigation, Phone, RefreshCw, Search, ShieldCheck, X } from "lucide-react";
import { userFacingError } from "./userFacingError";
import {
  cancelRide,
  formatDistance,
  formatDuration,
  formatFare,
  getRideSnapshot,
  isCancellableRide,
  isFinishedRide,
  quoteRide,
  requestRide,
  RideRequestError,
  rideStatusLabel,
  searchDestinations,
  type DestinationResult,
  type RidePoint,
  type RideQuote,
  type RideSnapshot,
  type VehicleChoice,
} from "./rides";

type Props = {
  accessToken: string;
  displayName?: string;
  supabaseUrl: string;
  publishableKey: string;
};

export function SavariRideView(props: Props) {
  const auth = useMemo(() => ({
    accessToken: props.accessToken,
    supabaseUrl: props.supabaseUrl,
    publishableKey: props.publishableKey,
  }), [props.accessToken, props.publishableKey, props.supabaseUrl]);
  const [checking, setChecking] = useState(true);
  const [pickup, setPickup] = useState<RidePoint>();
  const [destination, setDestination] = useState<DestinationResult>();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<DestinationResult[]>([]);
  const [quote, setQuote] = useState<RideQuote>();
  const [vehicle, setVehicle] = useState<VehicleChoice>("auto");
  const [ride, setRide] = useState<RideSnapshot>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    let active = true;
    void getRideSnapshot(auth).then((snapshot) => {
      if (active && snapshot) setRide(snapshot);
    }).catch((loadError) => {
      if (active) setError(message(loadError));
    }).finally(() => {
      if (active) setChecking(false);
    });
    return () => { active = false; };
  }, [auth]);

  useEffect(() => {
    if (!ride || isFinishedRide(ride.status)) return;
    const interval = window.setInterval(() => {
      void getRideSnapshot({ ...auth, rideId: ride.rideId }).then((snapshot) => {
        if (snapshot) setRide(snapshot);
      }).catch(() => undefined);
    }, 5_000);
    return () => window.clearInterval(interval);
  }, [auth, ride]);

  const locate = () => {
    setError(undefined);
    if (!navigator.geolocation) {
      setError("This browser cannot provide your location.");
      return;
    }
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setPickup({
          label: "Current location",
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
        });
        setDestination(undefined);
        setQuote(undefined);
        setResults([]);
        setBusy(false);
      },
      () => {
        setError("Location access was not allowed.");
        setBusy(false);
      },
      { enableHighAccuracy: true, timeout: 12_000, maximumAge: 60_000 },
    );
  };

  const search = async (event: FormEvent) => {
    event.preventDefault();
    if (!pickup || query.trim().length < 2) return;
    setBusy(true);
    setError(undefined);
    try {
      setResults(await searchDestinations({ ...auth, query, userLocation: pickup }));
    } catch (searchError) {
      setError(message(searchError));
    } finally {
      setBusy(false);
    }
  };

  const selectDestination = (result: DestinationResult) => {
    setDestination(result);
    setQuery(result.label);
    setResults([]);
    setQuote(undefined);
    setError(undefined);
  };

  const getQuote = async () => {
    if (!pickup || !destination) return;
    setBusy(true);
    setError(undefined);
    try {
      setQuote(await quoteRide({ ...auth, pickup, destination }));
    } catch (quoteError) {
      setError(message(quoteError));
    } finally {
      setBusy(false);
    }
  };

  const book = async () => {
    if (!quote) return;
    setBusy(true);
    setError(undefined);
    try {
      setRide(await requestRide({
        ...auth,
        quoteToken: quote.quoteToken,
        vehicleType: vehicle,
        idempotencyKey: crypto.randomUUID(),
      }));
    } catch (requestError) {
      if (requestError instanceof RideRequestError && requestError.ride) setRide(requestError.ride);
      else setError(message(requestError));
    } finally {
      setBusy(false);
    }
  };

  const cancel = async () => {
    if (!ride || !window.confirm("Cancel this ride request?")) return;
    setBusy(true);
    setError(undefined);
    try {
      setRide(await cancelRide({
        ...auth,
        rideId: ride.rideId,
        reason: "Passenger cancelled from web",
        idempotencyKey: crypto.randomUUID(),
      }));
    } catch (cancelError) {
      setError(message(cancelError));
    } finally {
      setBusy(false);
    }
  };

  const reset = () => {
    setRide(undefined);
    setDestination(undefined);
    setQuote(undefined);
    setQuery("");
    setResults([]);
    setError(undefined);
  };

  if (checking) return <div className="ride-loading" role="status"><span /> Checking current ride</div>;
  if (ride) return <ActiveRide ride={ride} busy={busy} error={error} onCancel={cancel} onReset={reset} />;

  return (
    <div className="ride-shell">
      <header className="ride-heading">
        <div>
          <p className="eyebrow">{props.displayName ? `Hello, ${props.displayName}` : "Savari passenger"}</p>
          <h1>Book a ride</h1>
          <p>Immediate Auto and Bike rides in Vaniyambadi.</p>
        </div>
      </header>

      <section className="route-builder" aria-label="Ride locations">
        <div className="route-row">
          <span className="route-marker pickup-marker" aria-hidden="true" />
          <div><small>Pickup</small><strong>{pickup?.label ?? "Choose pickup"}</strong></div>
          <button className="route-action" type="button" onClick={locate} disabled={busy}>
            <LocateFixed size={18} /> Use my location
          </button>
        </div>
        <form className="route-row destination-row" onSubmit={search}>
          <span className="route-marker destination-marker" aria-hidden="true" />
          <label>
            <small>Destination</small>
            <input
              type="search"
              placeholder={pickup ? "Search a place" : "Set pickup first"}
              value={query}
              disabled={!pickup || busy}
              onChange={(event) => {
                setQuery(event.target.value);
                setDestination(undefined);
                setQuote(undefined);
              }}
            />
          </label>
          <button className="icon-button search-button" type="submit" disabled={!pickup || query.trim().length < 2 || busy} aria-label="Search destination" title="Search destination">
            <Search size={18} />
          </button>
        </form>
        {results.length > 0 && (
          <div className="destination-results">
            {results.map((result) => (
              <button type="button" key={`${result.latitude}-${result.longitude}-${result.label}`} onClick={() => selectDestination(result)}>
                <MapPin size={18} /><span><strong>{result.label}</strong><small>{result.address}</small></span>
              </button>
            ))}
          </div>
        )}
      </section>

      {error && <p className="ride-error" role="alert">{error}</p>}

      {!quote && (
        <button className="primary-button ride-primary" type="button" disabled={!pickup || !destination || busy} onClick={() => void getQuote()}>
          <Navigation size={18} /> Check fares
        </button>
      )}

      {quote && (
        <section className="fare-section">
          <header><div><p className="eyebrow">Upfront fare</p><h2>Choose your ride</h2></div><span>{formatDistance(quote.distanceMeters)} · {formatDuration(quote.durationSeconds)}</span></header>
          <div className="vehicle-options" role="radiogroup" aria-label="Vehicle type">
            <button type="button" role="radio" aria-checked={vehicle === "auto"} className={vehicle === "auto" ? "selected" : ""} onClick={() => setVehicle("auto")}>
              <CarFront size={24} /><span><strong>Auto</strong><small>{formatFare(quote.fares.auto.paise)}</small></span>
            </button>
            <button type="button" role="radio" aria-checked={vehicle === "bike"} className={vehicle === "bike" ? "selected" : ""} onClick={() => setVehicle("bike")}>
              <Bike size={24} /><span><strong>Bike</strong><small>{formatFare(quote.fares.bike.paise)}</small></span>
            </button>
          </div>
          <button className="primary-button ride-primary" type="button" disabled={busy} onClick={() => void book()}>
            Request {vehicle === "auto" ? "Auto" : "Bike"}
          </button>
        </section>
      )}
    </div>
  );
}

function ActiveRide({ ride, busy, error, onCancel, onReset }: {
  ride: RideSnapshot;
  busy: boolean;
  error?: string;
  onCancel: () => void;
  onReset: () => void;
}) {
  const finished = isFinishedRide(ride.status);
  return (
    <div className="active-ride">
      <header>
        <span className={`ride-status-icon ${finished ? "finished" : ""}`}><ShieldCheck size={25} /></span>
        <div><p className="eyebrow">{ride.vehicleType}</p><h1>{rideStatusLabel(ride.status)}</h1></div>
      </header>
      <div className="active-route">
        <div><span className="route-marker pickup-marker" /><p><small>Pickup</small><strong>{ride.pickup.label}</strong></p></div>
        <div><span className="route-marker destination-marker" /><p><small>Destination</small><strong>{ride.destination.label}</strong></p></div>
      </div>
      <dl className="ride-facts">
        <div><dt>Fare</dt><dd>{formatFare(ride.fare.paise)}</dd></div>
        <div><dt>Distance</dt><dd>{formatDistance(ride.distanceMeters)}</dd></div>
        <div><dt>ETA</dt><dd>{formatDuration(ride.durationSeconds)}</dd></div>
      </dl>
      {ride.driver && (
        <div className="driver-contact">
          <div><strong>{ride.driver.displayName}</strong><small>Your rider</small></div>
          {ride.driver.phoneNumber && <a href={`tel:${ride.driver.phoneNumber}`}><Phone size={17} /> Call</a>}
        </div>
      )}
      {ride.boardingCode && <div className="boarding-code"><small>Start code</small><strong>{ride.boardingCode}</strong></div>}
      {error && <p className="ride-error" role="alert">{error}</p>}
      <div className="ride-actions">
        {isCancellableRide(ride.status) && <button className="secondary-button" type="button" disabled={busy} onClick={onCancel}><X size={17} /> Cancel ride</button>}
        {finished && <button className="primary-button" type="button" onClick={onReset}><RefreshCw size={17} /> Book another ride</button>}
      </div>
    </div>
  );
}

function message(error: unknown) {
  return userFacingError(error, "Something went wrong. Please try again.");
}
