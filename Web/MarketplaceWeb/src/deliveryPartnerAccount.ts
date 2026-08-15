import type { DeliveryPartnerSnapshot } from "./delivery";

export type DeliveryPartnerAccountState = DeliveryPartnerSnapshot["onboardingState"] | "loading" | "unavailable";

export type DeliveryPartnerAccountPresentation = {
  sectionTitle: string;
  title: string;
  detail: string;
  status?: string;
  tone: "apply" | "approved" | "pending" | "attention" | "neutral";
};

export function deliveryPartnerAccountPresentation(
  state: DeliveryPartnerAccountState,
): DeliveryPartnerAccountPresentation {
  switch (state) {
    case "approved":
      return {
        sectionTitle: "Delivery Partner",
        title: "Switch to Delivery Partner mode",
        detail: "Open your delivery workspace and continue earning.",
        status: "Approved",
        tone: "approved",
      };
    case "pending":
      return {
        sectionTitle: "Delivery Partner",
        title: "View your application",
        detail: "Your application is under review. We will notify you when it is approved.",
        status: "In review",
        tone: "pending",
      };
    case "rejected":
      return {
        sectionTitle: "Delivery Partner",
        title: "Update your application",
        detail: "Review the feedback, update your details and submit again.",
        status: "Action needed",
        tone: "attention",
      };
    case "not_applied":
      return {
        sectionTitle: "Earn with Dastak",
        title: "Become a Delivery Partner",
        detail: "Apply once, then choose when you want to earn.",
        tone: "apply",
      };
    case "loading":
      return {
        sectionTitle: "Delivery Partner",
        title: "Checking your partner access",
        detail: "This will only take a moment.",
        tone: "neutral",
      };
    case "unavailable":
      return {
        sectionTitle: "Delivery Partner",
        title: "Open Delivery Partner",
        detail: "Check your application or access your delivery workspace.",
        tone: "neutral",
      };
  }
}
