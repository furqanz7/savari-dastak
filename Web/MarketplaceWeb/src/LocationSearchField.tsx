import { useEffect, useState, type KeyboardEvent } from "react";
import { LocateFixed, MapPin, Search } from "lucide-react";
import { reverseGeocodeLocation, searchLocations, type LocationSearchResult } from "./location-search";

export type SelectedPlace = { address: string; latitude: number; longitude: number };

export function LocationSearchField({ label, value, onChange, disabled }: {
  label: string;
  value?: SelectedPlace;
  onChange: (place: SelectedPlace) => void;
  disabled?: boolean;
}) {
  const [query, setQuery] = useState(value?.address ?? "");
  const [results, setResults] = useState<LocationSearchResult[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    if (value?.address) setQuery(value.address);
  }, [value?.address]);

  const search = async () => {
    if (query.trim().length < 3) return;
    setBusy(true);
    setError(undefined);
    try { setResults(await searchLocations(query)); }
    catch (searchError) { setError(searchError instanceof Error ? searchError.message : "Location search failed."); }
    finally { setBusy(false); }
  };

  const searchOnEnter = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    void search();
  };

  const locate = () => {
    if (!navigator.geolocation) {
      setError("This browser cannot provide your location.");
      return;
    }
    setBusy(true);
    navigator.geolocation.getCurrentPosition((position) => {
      void (async () => {
        const latitude = position.coords.latitude;
        const longitude = position.coords.longitude;
        const address = await reverseGeocodeLocation(latitude, longitude).catch(() => "Current location");
        const place = { address, latitude, longitude };
        setQuery(place.address);
        setResults([]);
        setError(undefined);
        onChange(place);
        setBusy(false);
      })();
    }, () => {
      setError("Location access was not allowed.");
      setBusy(false);
    }, { enableHighAccuracy: true, timeout: 12_000, maximumAge: 60_000 });
  };

  const choose = (result: LocationSearchResult) => {
    const place = { address: result.label, latitude: result.latitude, longitude: result.longitude };
    setQuery(result.label);
    setResults([]);
    setError(undefined);
    onChange(place);
  };

  return (
    <div className="place-search-field">
      <label>{label}</label>
      <div className="place-search-input">
        <MapPin size={18} />
        <input value={query} disabled={disabled || busy} placeholder={`Search ${label.toLowerCase()}`} onKeyDown={searchOnEnter} onChange={(event) => { setQuery(event.target.value); setResults([]); }} />
        <button className="icon-button" type="button" onClick={() => void search()} disabled={disabled || busy || query.trim().length < 3} aria-label={`Search ${label.toLowerCase()}`} title="Search"><Search size={17} /></button>
        <button className="icon-button" type="button" disabled={disabled || busy} onClick={locate} aria-label={`Use current location for ${label.toLowerCase()}`} title="Use current location"><LocateFixed size={17} /></button>
      </div>
      {results.length > 0 && <div className="place-search-results">{results.map((result) => <button type="button" key={result.id} onClick={() => choose(result)}><MapPin size={16} /><span>{result.label}</span></button>)}</div>}
      {value && <small>{value.latitude.toFixed(5)}, {value.longitude.toFixed(5)}</small>}
      {error && <small className="error-text" role="alert">{error}</small>}
    </div>
  );
}
