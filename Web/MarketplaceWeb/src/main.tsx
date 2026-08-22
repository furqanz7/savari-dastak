import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./styles.css";
import "./design/customer.css";
import "./design/v1-customer.css";
import "./design/v1-admin.css";
import "./design/v1-merchant.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
