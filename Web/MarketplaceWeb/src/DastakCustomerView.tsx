import { useState } from "react";
import { ArrowLeft, Home, ReceiptText, Search, UserRound } from "lucide-react";
import { CatalogueView } from "./CatalogueView";
import { ParcelCustomerView } from "./ParcelCustomerView";

export type CustomerSection = "home" | "search" | "orders" | "account";

type Props = {
  accessToken: string;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  onSignOut: () => void;
};

export function DastakCustomerView(props: Props) {
  const [section, setSection] = useState<CustomerSection | "parcel">("home");
  const catalogueSection = section === "parcel" ? "home" : section;

  return (
    <div className="customer-workspace">
      <nav className="customer-navigation" aria-label="Dastak">
        <CustomerNavigationButton icon={<Home />} label="Home" selected={section === "home"} onClick={() => setSection("home")} />
        <CustomerNavigationButton icon={<Search />} label="Search" selected={section === "search"} onClick={() => setSection("search")} />
        <CustomerNavigationButton icon={<ReceiptText />} label="Orders" selected={section === "orders"} onClick={() => setSection("orders")} />
        <CustomerNavigationButton icon={<UserRound />} label="Account" selected={section === "account"} onClick={() => setSection("account")} />
      </nav>
      <div className="customer-view" hidden={section === "parcel"}>
        <CatalogueView
          {...props}
          section={catalogueSection}
          onNavigate={setSection}
          onOpenParcel={() => setSection("parcel")}
        />
      </div>
      {section === "parcel" && (
        <div className="customer-view parcel-experience">
          <button className="customer-back-button" type="button" onClick={() => setSection("home")}>
            <ArrowLeft size={18} /> Home
          </button>
          <ParcelCustomerView {...props} />
        </div>
      )}
    </div>
  );
}

function CustomerNavigationButton({ icon, label, selected, onClick }: {
  icon: React.ReactNode;
  label: string;
  selected: boolean;
  onClick: () => void;
}) {
  return (
    <button type="button" className={selected ? "selected" : ""} onClick={onClick} aria-current={selected ? "page" : undefined}>
      {icon}
      <span>{label}</span>
    </button>
  );
}
