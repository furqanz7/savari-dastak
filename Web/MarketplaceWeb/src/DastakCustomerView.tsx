import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ArrowLeft, Home, ReceiptText, Search, UserRound } from "lucide-react";
import { CatalogueView } from "./CatalogueView";
import { DastakV1CustomerExperience } from "./DastakV1CustomerExperience";
import { ParcelCustomerView } from "./ParcelCustomerView";
import {
  parseCustomerDestination,
  serializeCustomerDestination,
  type CustomerDestination,
  type CustomerSection,
} from "./customerNavigation";
import { useOrderRealtime } from "./orderRealtime";
import { useDastakWebPush } from "./useDastakWebPush";
import { WebNotificationOnboarding } from "./WebNotificationOnboarding";

type Props = {
  accessToken: string;
  accountId: string;
  client: SupabaseClient;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  legalLinks: { privacy: string; terms: string; support: string };
  webPushPublicKey: string;
  deliveryPartnerUrl: string;
  merchantUrl: string;
  onSignOut: () => void;
};

export function DastakCustomerView(props: Props) {
  const [orderRefreshToken, setOrderRefreshToken] = useState(0);
  const [destination, setDestination] = useState<CustomerDestination>(() =>
    parseCustomerDestination(typeof window === "undefined" ? undefined : window.location.hash)
  );
  const section = destination.section;
  const v1Section = section === "search" || section === "orders" || section === "wishlist" || section === "payments"
    ? section
    : "home";
  const webPushAuthentication = useMemo(() => ({
    accountId: props.accountId,
    accessToken: props.accessToken,
    supabaseUrl: props.supabaseUrl,
    publishableKey: props.publishableKey,
    publicKey: props.webPushPublicKey,
  }), [props.accountId, props.accessToken, props.publishableKey, props.supabaseUrl, props.webPushPublicKey]);
  const webPush = useDastakWebPush(webPushAuthentication);

  useOrderRealtime({
    client: props.client,
    accountId: props.accountId,
    accessToken: props.accessToken,
    onChange: () => setOrderRefreshToken((current) => current + 1),
  });

  const navigate = useCallback((next: CustomerDestination, replace = false) => {
    const hash = serializeCustomerDestination(next);
    setDestination(next);
    if (typeof window !== "undefined" && window.location.hash !== hash) {
      window.history[replace ? "replaceState" : "pushState"](null, "", hash);
    }
    window.scrollTo({ top: 0, behavior: "smooth" });
  }, []);

  useEffect(() => {
    const restore = () => setDestination(parseCustomerDestination(window.location.hash));
    window.addEventListener("hashchange", restore);
    window.addEventListener("popstate", restore);
    if (!window.location.hash) navigate({ section: "home" }, true);
    return () => {
      window.removeEventListener("hashchange", restore);
      window.removeEventListener("popstate", restore);
    };
  }, [navigate]);

  const navigateSection = (nextSection: CustomerSection) => navigate({ section: nextSection });

  return (
    <div className="customer-workspace">
      <nav className="customer-navigation" aria-label="Dastak">
        <CustomerNavigationButton icon={<Home />} label="Home" selected={section === "home"} onClick={() => navigateSection("home")} />
        <CustomerNavigationButton icon={<Search />} label="Search" selected={section === "search"} onClick={() => navigateSection("search")} />
        <CustomerNavigationButton icon={<ReceiptText />} label="Orders" selected={section === "orders"} onClick={() => navigateSection("orders")} />
        <CustomerNavigationButton icon={<UserRound />} label="Account" selected={section === "account" || section === "wishlist" || section === "payments"} onClick={() => navigateSection("account")} />
      </nav>
      <div className="customer-view" hidden={section === "parcel" || section === "account"}>
        <DastakV1CustomerExperience
          accessToken={props.accessToken}
          accountId={props.accountId}
          client={props.client}
          displayName={props.displayName}
          phoneNumber={props.phoneNumber}
          supabaseUrl={props.supabaseUrl}
          publishableKey={props.publishableKey}
          orderRefreshToken={orderRefreshToken}
          initialOrderId={destination.entityType === "dastakV1Order" ? destination.entityId : undefined}
          section={v1Section}
          onNavigate={navigateSection}
          onOpenParcel={() => navigate({ section: "parcel" })}
          onOpenOrder={(orderId) => navigate({
            section: "orders", entityType: "dastakV1Order", entityId: orderId,
          })}
          onCloseOrder={() => navigate({ section: "orders" })}
        />
      </div>
      {section === "account" && <div className="customer-view">
        <CatalogueView
          {...props}
          orderRefreshToken={orderRefreshToken}
          section="account"
          onNavigate={navigateSection}
          onOpenOrder={(orderId) => navigate({ section: "orders", entityType: "merchantOrder", entityId: orderId })}
          onCloseOrder={() => navigate({ section: "orders" })}
          onOpenParcel={() => navigate({ section: "parcel" })}
          legalLinks={props.legalLinks}
          webPush={webPush}
          merchantUrl={props.merchantUrl}
        />
      </div>}
      {section === "parcel" && (
        <div className="customer-view parcel-experience">
          {!destination.entityId && <button className="customer-back-button" type="button" onClick={() => navigate({ section: "home" })}>
            <ArrowLeft size={18} /> Home
          </button>}
          <ParcelCustomerView
            {...props}
            orderRefreshToken={orderRefreshToken}
            selectedParcelId={destination.entityType === "parcel" ? destination.entityId : undefined}
            onOpenParcel={(parcelId) => navigate({ section: "parcel", entityType: "parcel", entityId: parcelId })}
            onCloseParcel={() => navigate({ section: "parcel" })}
          />
        </div>
      )}
      {webPush.shouldPrompt && <WebNotificationOnboarding
        busy={webPush.status === "enabling"}
        onEnable={() => void webPush.enable()}
        onDismiss={webPush.dismiss}
      />}
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
