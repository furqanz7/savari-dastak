export const appVariants = [
  "savari-passenger",
  "savari-rider",
  "dastak-customer",
  "dastak-delivery",
  "dastak-merchant",
  "dastak-admin",
] as const;

export type AppVariant = (typeof appVariants)[number];
export type Product = "savari" | "dastak";
export type AppRole = "passenger" | "rider" | "customer" | "delivery" | "merchant" | "admin";

export type AppConfig = {
  variant: AppVariant;
  product: Product;
  role: AppRole;
  brand: string;
  roleLabel: string;
  supabaseUrl: string;
  supabasePublishableKey: string;
  legalLinks?: {
    privacy: string;
    terms: string;
    support: string;
  };
  webPushPublicKey?: string;
  deliveryPartnerUrl?: string;
  merchantUrl?: string;
};

type PublicEnvironment = {
  readonly [key: string]: unknown;
  VITE_APP_VARIANT?: string;
  VITE_SUPABASE_URL?: string;
  VITE_SUPABASE_PUBLISHABLE_KEY?: string;
  VITE_DASTAK_PRIVACY_URL?: string;
  VITE_DASTAK_TERMS_URL?: string;
  VITE_DASTAK_SUPPORT_URL?: string;
  VITE_DASTAK_WEB_PUSH_PUBLIC_KEY?: string;
  VITE_DASTAK_DELIVERY_URL?: string;
  VITE_DASTAK_MERCHANT_URL?: string;
};

const variants: Record<AppVariant, Omit<AppConfig, "supabaseUrl" | "supabasePublishableKey">> = {
  "savari-passenger": {
    variant: "savari-passenger",
    product: "savari",
    role: "passenger",
    brand: "Savari",
    roleLabel: "Passenger",
  },
  "savari-rider": {
    variant: "savari-rider",
    product: "savari",
    role: "rider",
    brand: "Savari",
    roleLabel: "Rider",
  },
  "dastak-customer": {
    variant: "dastak-customer",
    product: "dastak",
    role: "customer",
    brand: "Dastak",
    roleLabel: "Customer",
  },
  "dastak-delivery": {
    variant: "dastak-delivery",
    product: "dastak",
    role: "delivery",
    brand: "Dastak",
    roleLabel: "Delivery Partner",
  },
  "dastak-merchant": {
    variant: "dastak-merchant",
    product: "dastak",
    role: "merchant",
    brand: "Dastak",
    roleLabel: "Merchant",
  },
  "dastak-admin": {
    variant: "dastak-admin",
    product: "dastak",
    role: "admin",
    brand: "Dastak",
    roleLabel: "Admin",
  },
};

export function readAppConfig(environment: PublicEnvironment): AppConfig {
  const variant = environment.VITE_APP_VARIANT;
  if (!appVariants.includes(variant as AppVariant)) {
    throw new Error("VITE_APP_VARIANT must identify a supported web app.");
  }

  const supabaseUrl = environment.VITE_SUPABASE_URL?.trim() ?? "";
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(supabaseUrl)) {
    throw new Error("VITE_SUPABASE_URL must be a hosted Supabase project URL.");
  }

  const supabasePublishableKey = environment.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";
  assertBrowserSafeKey(supabasePublishableKey);

  const selectedVariant = variant as AppVariant;
  const customerLaunchConfiguration = selectedVariant === "dastak-customer"
    ? readCustomerLaunchConfiguration(environment)
    : {};
  const notificationConfiguration = ["dastak-customer", "dastak-merchant", "dastak-delivery"]
    .includes(selectedVariant)
    ? { webPushPublicKey: readDastakWebPushPublicKey(environment) }
    : {};

  return {
    ...variants[selectedVariant],
    supabaseUrl: supabaseUrl.replace(/\/$/, ""),
    supabasePublishableKey,
    ...customerLaunchConfiguration,
    ...notificationConfiguration,
  };
}

function readCustomerLaunchConfiguration(environment: PublicEnvironment) {
  const privacy = requiredPublicUrl("VITE_DASTAK_PRIVACY_URL", environment.VITE_DASTAK_PRIVACY_URL);
  const terms = requiredPublicUrl("VITE_DASTAK_TERMS_URL", environment.VITE_DASTAK_TERMS_URL);
  const support = requiredPublicUrl("VITE_DASTAK_SUPPORT_URL", environment.VITE_DASTAK_SUPPORT_URL);
  const deliveryPartnerUrl = requiredPublicUrl(
    "VITE_DASTAK_DELIVERY_URL",
    environment.VITE_DASTAK_DELIVERY_URL,
  );
  const merchantUrl = requiredPublicUrl(
    "VITE_DASTAK_MERCHANT_URL",
    environment.VITE_DASTAK_MERCHANT_URL,
  );
  return { legalLinks: { privacy, terms, support }, deliveryPartnerUrl, merchantUrl };
}

function readDastakWebPushPublicKey(environment: PublicEnvironment) {
  const webPushPublicKey = environment.VITE_DASTAK_WEB_PUSH_PUBLIC_KEY?.trim() ?? "";
  if (!/^[A-Za-z0-9_-]{80,100}$/.test(webPushPublicKey)) {
    throw new Error("VITE_DASTAK_WEB_PUSH_PUBLIC_KEY must be a VAPID public key.");
  }
  return webPushPublicKey;
}

function requiredPublicUrl(name: string, value: string | undefined) {
  const normalized = value?.trim() ?? "";
  let url: URL;
  try {
    url = new URL(normalized);
  } catch {
    throw new Error(`${name} must be a public HTTPS URL.`);
  }
  if (url.protocol !== "https:") throw new Error(`${name} must be a public HTTPS URL.`);
  return url.toString();
}

export function assertBrowserSafeKey(key: string) {
  if (!key) throw new Error("VITE_SUPABASE_PUBLISHABLE_KEY is required.");
  if (key.startsWith("sb_secret_")) {
    throw new Error("A Supabase secret key cannot be included in a browser app.");
  }
  if (key.startsWith("sb_publishable_")) return;

  const parts = key.split(".");
  if (parts.length !== 3) {
    throw new Error("Use a Supabase publishable or legacy anon key.");
  }
  try {
    const payload = JSON.parse(decodeBase64Url(parts[1])) as { role?: unknown };
    if (payload.role !== "anon") {
      throw new Error("Only the legacy anon JWT is browser-safe.");
    }
  } catch (error) {
    if (error instanceof Error && error.message === "Only the legacy anon JWT is browser-safe.") {
      throw error;
    }
    throw new Error("Use a valid Supabase publishable or legacy anon key.");
  }
}

function decodeBase64Url(value: string) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  if (typeof globalThis.atob === "function") return globalThis.atob(padded);
  return Buffer.from(padded, "base64").toString("utf8");
}
