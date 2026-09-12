import type { AppVariant } from "./config";

export type VariantMetadata = { title: string; description: string; applicationName: string };

const metadata: Record<AppVariant, VariantMetadata> = {
  "savari-passenger": { title: "Savari", description: "Book and manage your Savari journeys.", applicationName: "Savari" },
  "savari-rider": { title: "Savari Driver", description: "The Savari workspace for drivers.", applicationName: "Savari Driver" },
  "dastak-customer": { title: "Dastak", description: "Everyday essentials and food, delivered to your doorstep.", applicationName: "Dastak" },
  "dastak-delivery": { title: "Dastak Delivery Partner", description: "The operational delivery workspace for Dastak riders.", applicationName: "Dastak Delivery Partner" },
  "dastak-merchant": { title: "Dastak Merchant", description: "Orders, fulfilment, store operations and earnings for Dastak merchants.", applicationName: "Dastak Merchant" },
  "dastak-admin": { title: "Dastak Admin — Operations Control", description: "Secure operational control for the Dastak marketplace.", applicationName: "Dastak Admin" },
};

export function metadataForVariant(variant: string): VariantMetadata {
  return metadata[variant as AppVariant] ?? metadata["savari-passenger"];
}
