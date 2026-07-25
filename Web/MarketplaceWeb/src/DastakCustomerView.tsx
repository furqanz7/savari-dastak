import { useState } from "react";
import { Package, ShoppingBag } from "lucide-react";
import { CatalogueView } from "./CatalogueView";
import { ParcelCustomerView } from "./ParcelCustomerView";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
};

export function DastakCustomerView(props: Props) {
  const [section, setSection] = useState<"shop" | "parcel">("shop");
  return (
    <div className="customer-workspace">
      <nav className="workspace-tabs customer-tabs" aria-label="Dastak services">
        <button type="button" className={section === "shop" ? "selected" : ""} onClick={() => setSection("shop")}><ShoppingBag size={17} /> Shop</button>
        <button type="button" className={section === "parcel" ? "selected" : ""} onClick={() => setSection("parcel")}><Package size={17} /> Parcel</button>
      </nav>
      {section === "shop" ? <CatalogueView {...props} /> : <ParcelCustomerView {...props} />}
    </div>
  );
}
