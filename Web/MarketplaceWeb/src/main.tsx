import { lazy, StrictMode, Suspense } from "react";
import { createRoot } from "react-dom/client";
import { PublicInformationPage } from "./PublicInformationPage";
import { publicInformationKindForPath } from "./publicInformation";
import "./styles.css";
import "./design/customer.css";
import "./design/v1-customer.css";
import "./design/v1-admin.css";
import "./design/v1-merchant.css";

const App = lazy(() => import("./App"));
const publicInformationKind = publicInformationKindForPath(window.location.pathname);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    {publicInformationKind
      ? <PublicInformationPage kind={publicInformationKind} />
      : <Suspense fallback={<main className="app product-dastak"><div className="loading" role="status"><span /> Opening Dastak</div></main>}><App /></Suspense>}
  </StrictMode>,
);
