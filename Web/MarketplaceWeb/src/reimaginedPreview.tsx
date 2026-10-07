import { useReducer, useState } from "react";
import { createRoot } from "react-dom/client";
import mapMigration from "../../../Backends/Dastak/supabase/migrations/20260925222726_reference_catalogue_browse_map.sql?raw";
import { ReimaginedShell } from "./ReimaginedShell";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
import type { V1CatalogueBrowseMap } from "./dastakV1";
import { ReimaginedGrocery, ReimaginedGrocerySuggestions } from "./ReimaginedGrocery";
import { parseReimaginedCatalogueImport } from "./reimaginedCatalogueImport";
import type { ReimaginedCatalogue } from "./reimaginedCatalogue";

// Local presentation snapshot from the checked-in migration, not a second taxonomy.
// Production integration will pass the authenticated catalogue response instead.
const nodes: V1CatalogueBrowseMap["nodes"] = Array.from(mapMigration.matchAll(/\(1,'([^']+)',(null|'[^']+'),'(SECTION|DESTINATION|RAIL)','((?:[^']|'')*)',(\d+)\)/g), match => ({
  key: match[1], parentKey: match[2] === "null" ? null : match[2].slice(1, -1),
  kind: match[3] as V1CatalogueBrowseMap["nodes"][number]["kind"], label: match[4].replaceAll("''", "'"), sortOrder: Number(match[5]), sources: [],
}));
const directory = reimaginedDirectory({ version: 1, nodes });

export function Preview() {
  const [state, dispatch] = useReducer(reimaginedReducer, undefined, initialReimaginedState);
  const [catalogue, setCatalogue] = useState<ReimaginedCatalogue>();
  const [importError, setImportError] = useState<string>();
  const [imageOrigin, setImageOrigin] = useState("");
  const exploration = state.exploration[state.service];
  return <>
    <div className="reimagined-preview-banner">LOCAL SHELL PREVIEW · Sign-in and shopping controls below are simulations. No production data is changed.</div>
    <ReimaginedShell state={state} dispatch={dispatch} directory={catalogue ? reimaginedDirectory(catalogue.map) : directory} greeting="Welcome" displayName="Furqan" locationLabel="Choose your location"
      locationContent={<p>The existing address picker will connect here. This preview does not save an address.</p>}
      onSignIn={() => dispatch({ type: "signedIn", accountId: "local-preview" })}
      onOpenActiveOrder={() => dispatch({ type: "navigate", section: "orders" })}
      searchSuggestions={state.service === "grocery" ? <ReimaginedGrocerySuggestions data={catalogue} query={exploration.searchDraft} dispatch={dispatch} /> : <p>Food suggestions will use the restaurant and menu catalogue.</p>}
      sectionContent={{ orders: <p>Your real order history will connect here.</p>, profile: <p>Your existing account profile will connect here.</p>, settings: <><p>Existing preferences will connect here.</p><button type="button" onClick={() => dispatch({ type: "signedOut" })}>Leave preview session</button></> }}>
      <div className="reimagined-preview-content">
        <details className="reimagined-preview-import"><summary>Load a real catalogue snapshot locally</summary><p>Choose a JSON bundle containing the canonical map and complete catalogue responses. It stays in this browser’s memory; it is not uploaded. Cart actions remain simulations and prices are snapshot prices, not checkout quotes.</p>
          <label>Public catalogue image project URL (optional)<input type="url" placeholder="https://your-project.supabase.co" value={imageOrigin} onChange={event => setImageOrigin(event.target.value)} /></label>
          <input type="file" accept="application/json,.json" aria-label="Import catalogue snapshot" onChange={async event => {
            const file = event.target.files?.[0];
            if (!file) return;
            if (file.size > 20_000_000) { setImportError("Choose a snapshot smaller than 20 MB."); return; }
            try { const imported = parseReimaginedCatalogueImport(JSON.parse(await file.text())); setCatalogue(imported); setImportError(undefined); dispatch({ type: "signedOut" }); dispatch({ type: "signedIn", accountId: "local-preview" }); }
            catch { setImportError("Could not import that complete catalogue/map bundle. Check the JSON format and canonical relationships."); }
          }} />{importError ? <p role="alert">{importError}</p> : null}
        </details>
        {catalogue && state.service === "grocery" ? <ReimaginedGrocery state={state} dispatch={dispatch} data={catalogue} status="ready" onRetry={() => undefined} supabaseUrl={/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(imageOrigin) ? imageOrigin : ""} eligibility={() => ({ canAdd: true, maximumQuantity: 99, reason: "Local cart simulation only. Live availability is not connected." })} checkoutContent={<p>No order can be placed in this preview. Continue Shopping keeps your simulated Bucket.</p>} /> : <>
        <p className="reimagined-kicker">LAYOUT AND INTERACTION STUDY</p>
        <p>{exploration.checkout ? "You are at the billing counter. No order can be placed in this preview." : "The next step connects real products and restaurants to this panel. Use the directory to review category navigation."}</p>
        <div className="reimagined-preview-shelf"><span>Real product shelves connect next</span></div>
        <details><summary>Local test controls — not real products or orders</summary>
          <div className="reimagined-preview-controls">
            <button type="button" onClick={() => state.service === "grocery" ? dispatch({ type: "setGroceryQuantity", skuId: "preview-only-sku", quantity: (state.shopping.retail["preview-only-sku"] ?? 0) + 1 }) : dispatch({ type: "setFoodQuantity", line: { branchId: "preview-only-branch", itemId: "preview-only-item", optionIds: [], quantity: 1 } })}>Simulate adding an item</button>
            <button type="button" onClick={() => dispatch({ type: "checkoutSucceeded", service: state.service, orderId: "preview-only-order", purchased: state.shopping })}>Simulate confirmed order</button>
          </div>
        </details>
        </>}
      </div>
    </ReimaginedShell>
  </>;
}

createRoot(document.getElementById("root")!).render(<Preview />);
