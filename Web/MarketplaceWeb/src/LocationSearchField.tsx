import { useCallback, useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { LocateFixed, MapPin, Search } from "lucide-react";
import { reverseGeocodeLocation, searchLocations, type LocationSearchResult } from "./location-search";
import { userFacingError } from "./userFacingError";
import { DastakMap } from "./DastakMap";

export type SelectedPlace = { address: string; latitude: number; longitude: number };

export function LocationSearchField({ label, value, onChange, onSelectionCleared, disabled }: {
  label: string;
  value?: SelectedPlace;
  onChange: (place: SelectedPlace) => void;
  onSelectionCleared?: () => void;
  disabled?: boolean;
}) {
  const inputId = useId();
  const [query, setQuery] = useState(value?.address ?? "");
  const [results, setResults] = useState<LocationSearchResult[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [dirty, setDirty] = useState(false);
  const [active, setActive] = useState(-1);
  const [locating, setLocating] = useState(false);
  const [searched, setSearched] = useState(false);
  const request = useRef(0);
  const controller = useRef<AbortController | undefined>(undefined);
  const reverseTimer = useRef<number | undefined>(undefined);
  const current = useRef({ onChange, disabled });
  useEffect(() => { current.current = { onChange, disabled }; }, [onChange, disabled]);

  useEffect(() => {
    if (value?.address) { setQuery(value.address); setDirty(false); }
  }, [value?.address]);
  useEffect(() => () => { request.current++; controller.current?.abort(); window.clearTimeout(reverseTimer.current); }, []);
  useEffect(() => { if (disabled) { request.current++; controller.current?.abort(); window.clearTimeout(reverseTimer.current); setLocating(false); setBusy(false); } }, [disabled]);

  const search = useCallback(async () => {
    if (query.trim().length < 3 || disabled) return;
    controller.current?.abort();
    const abort = new AbortController(); controller.current = abort;
    const version = ++request.current;
    setBusy(true);
    setError(undefined);
    try {
      const found = await searchLocations(query, undefined, abort.signal);
      if (version === request.current && !abort.signal.aborted) { setResults(found); setActive(-1); setSearched(true); }
    } catch (searchError) { if (version === request.current && !abort.signal.aborted) setError(userFacingError(searchError, "Location search failed.")); }
    finally { if (version === request.current) setBusy(false); }
  }, [query, disabled]);
  useEffect(() => {
    if (!dirty || disabled || query.trim().length < 3) return;
    const timer = window.setTimeout(() => void search(), 650);
    return () => { window.clearTimeout(timer); controller.current?.abort(); };
  }, [dirty, disabled, query, search]);

  const searchOnEnter = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); setResults([]); setActive(-1); return; }
    if ((event.key === "ArrowDown" || event.key === "ArrowUp") && results.length) {
      event.preventDefault(); setActive(previous => event.key === "ArrowDown" ? (previous + 1) % results.length : (previous <= 0 ? results.length : previous) - 1); return;
    }
    if (event.key !== "Enter") return;
    event.preventDefault();
    if (active >= 0 && results[active]) choose(results[active]); else void search();
  };

  const choosePin = (latitude: number, longitude: number) => {
    if (disabled) return;
    controller.current?.abort(); window.clearTimeout(reverseTimer.current); const abort = new AbortController(); controller.current = abort;
    const version = ++request.current;
    const address = "Selected map location";
    setQuery(address); setDirty(false); setResults([]); setBusy(false); setError(undefined);
    onChange({ address, latitude, longitude });
    reverseTimer.current = window.setTimeout(() => {
      if (version !== request.current || abort.signal.aborted) return;
      void reverseGeocodeLocation(latitude, longitude, undefined, abort.signal).then(resolved => {
        if (version === request.current && !abort.signal.aborted && !current.current.disabled) {
          setQuery(resolved); current.current.onChange({ address: resolved, latitude, longitude });
        }
      }).catch(() => { if (version === request.current && !abort.signal.aborted) setError("Pin selected. The nearby address could not be found; add your building and landmark below."); });
    }, 400);
  };

  const locate = () => {
    if (!navigator.geolocation) {
      setError("This browser cannot provide your location.");
      return;
    }
    controller.current?.abort();
    const version = ++request.current;
    setLocating(true);
    navigator.geolocation.getCurrentPosition((position) => {
      if (version !== request.current || current.current.disabled) return;
      setLocating(false); void choosePin(position.coords.latitude, position.coords.longitude);
    }, () => {
      if (version !== request.current) return;
      setError("Location access was not allowed. Search or choose your pin on the map.");
      setLocating(false);
    }, { enableHighAccuracy: true, timeout: 12_000, maximumAge: 60_000 });
  };

  const choose = (result: LocationSearchResult) => {
    controller.current?.abort(); request.current++;
    const place = { address: result.label, latitude: result.latitude, longitude: result.longitude };
    setQuery(result.label);
    setResults([]);
    setError(undefined);
    setDirty(false); setBusy(false); setActive(-1);
    onChange(place);
  };

  return (
    <div className="place-search-field" onBlur={event => { if (!event.currentTarget.contains(event.relatedTarget as Node | null)) { setResults(previous => previous.length ? [] : previous); setActive(-1); } }}>
      <label htmlFor={inputId}>{label}</label>
      <div className="place-search-input">
        <MapPin size={18} />
        <input id={inputId} role="combobox" aria-autocomplete="list" aria-expanded={results.length > 0} aria-controls={`${inputId}-results`} aria-activedescendant={active >= 0 ? `${inputId}-option-${active}` : undefined} autoComplete="off" maxLength={180} value={query} disabled={disabled || locating} placeholder={`Search ${label.toLowerCase()}`} onKeyDown={searchOnEnter} onChange={(event) => {
          controller.current?.abort(); request.current++;
          const nextQuery = event.target.value;
          setQuery(nextQuery);
          setResults([]);
          setDirty(true); setSearched(false); setBusy(false); setActive(-1); setError(undefined);
          if (value && nextQuery !== value.address) onSelectionCleared?.();
        }} />
        <button className="icon-button" type="button" onClick={() => void search()} disabled={disabled || busy || query.trim().length < 3} aria-label={`Search ${label.toLowerCase()}`} title="Search"><Search size={17} /></button>
        <button className="icon-button" type="button" disabled={disabled || locating} onClick={locate} aria-label={`Use current location for ${label.toLowerCase()}`} title="Use current location"><LocateFixed size={17} /></button>
      </div>
      {results.length > 0 && <div id={`${inputId}-results`} className="place-search-results" role="listbox" aria-label="Address suggestions">{results.map((result, index) => <button role="option" id={`${inputId}-option-${index}`} aria-selected={active === index} type="button" key={result.id} disabled={disabled} onMouseDown={event => event.preventDefault()} onClick={() => choose(result)}><MapPin size={16} /><span>{result.label}</span></button>)}</div>}
      {busy || locating || (searched && !results.length && dirty && !error) ? <small className="place-search-status" role="status">{locating ? "Finding your location…" : busy ? "Finding nearby addresses…" : "No matches found. Try an area or landmark, or choose your pin on the map."}</small> : null}
      <DastakMap points={value ? [{ ...value, label: value.address, kind: "dropoff" }] : []} editable disabled={disabled || locating} onPinChange={point => { void choosePin(point.latitude, point.longitude); }} label={`${label} map`} />
      <small className="place-search-status">Search data © OpenStreetMap contributors · Photon</small>
      {value && <small>{value.latitude.toFixed(5)}, {value.longitude.toFixed(5)}</small>}
      {error && <small className="error-text" role="alert">{error}</small>}
    </div>
  );
}
