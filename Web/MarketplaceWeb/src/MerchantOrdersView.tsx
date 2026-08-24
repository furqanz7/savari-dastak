import { useMemo, useState, type ReactNode } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { BookOpen, ClipboardList, UserRound, WalletCards } from "lucide-react";
import { MerchantV1CommerceControl } from "./MerchantV1CommerceControl";
import { MerchantV1Opportunities } from "./MerchantV1Opportunities";
import { RoleAccountView } from "./RoleAccountView";
import { RoyaltyPanel } from "./RoyaltyPanel";

type Props = {
  accessToken: string;
  accountId: string;
  client: SupabaseClient;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  onSignOut: () => void;
};

type MerchantSection = "orders" | "catalogue" | "royalty" | "account";

export function MerchantOrdersView({
  accessToken,
  accountId,
  client,
  displayName,
  email,
  phoneNumber,
  supabaseUrl,
  publishableKey,
  onSignOut,
}: Props) {
  const auth = useMemo(
    () => ({ accessToken, supabaseUrl, publishableKey }),
    [accessToken, publishableKey, supabaseUrl],
  );
  const [section, setSection] = useState<MerchantSection>("orders");

  return (
    <div className="merchant-workspace">
      <nav className="workspace-tabs merchant-tabs" aria-label="Merchant workspace" role="tablist">
        <MerchantTab selected={section === "orders"} onSelect={() => setSection("orders")} icon={<ClipboardList size={18} />} label="Orders" />
        <MerchantTab selected={section === "catalogue"} onSelect={() => setSection("catalogue")} icon={<BookOpen size={18} />} label="Catalogue" />
        <MerchantTab selected={section === "royalty"} onSelect={() => setSection("royalty")} icon={<WalletCards size={18} />} label="Royalty" />
        <MerchantTab selected={section === "account"} onSelect={() => setSection("account")} icon={<UserRound size={18} />} label="Account" />
      </nav>

      {section === "catalogue" ? (
        <MerchantV1CommerceControl auth={auth} />
      ) : section === "royalty" ? (
        <RoyaltyPanel auth={auth} kind="MERCHANT" />
      ) : section === "account" ? (
        <RoleAccountView
          accessToken={accessToken}
          displayName={displayName}
          email={email}
          phoneNumber={phoneNumber}
          roleName="Merchant"
          supabaseUrl={supabaseUrl}
          publishableKey={publishableKey}
          onOpenWorkspace={() => setSection("catalogue")}
          onSignOut={onSignOut}
        />
      ) : (
        <div className="merchant-orders-shell">
          <header className="merchant-orders-heading">
            <div>
              <p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak merchant"}</p>
              <h1>Orders</h1>
              <p>Live exact-item requests and fulfilments.</p>
            </div>
          </header>
          <MerchantV1Opportunities auth={auth} client={client} accountId={accountId} />
        </div>
      )}
    </div>
  );
}

function MerchantTab({
  selected,
  onSelect,
  icon,
  label,
}: {
  selected: boolean;
  onSelect: () => void;
  icon: ReactNode;
  label: string;
}) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={selected}
      className={selected ? "selected" : ""}
      onClick={onSelect}
    >
      {icon}
      <span>{label}</span>
    </button>
  );
}
