export type PublicInformationKind = "privacy" | "terms" | "support";

export type PublicInformationSection = {
  title: string;
  paragraphs?: string[];
  bullets?: string[];
};

export type PublicInformationAction = {
  title: string;
  detail: string;
  href: string;
};

export type PublicInformationPage = {
  kind: PublicInformationKind;
  eyebrow: string;
  title: string;
  summary: string;
  updated: string;
  sections: PublicInformationSection[];
  actions?: PublicInformationAction[];
};

const updated = "24 August 2026";

export const publicInformationPages: Record<PublicInformationKind, PublicInformationPage> = {
  privacy: {
    kind: "privacy",
    eyebrow: "Your data",
    title: "Privacy Policy",
    summary: "How Dastak collects, uses and protects information when you browse, order and receive deliveries.",
    updated,
    sections: [
      {
        title: "Information we collect",
        bullets: [
          "Account and profile details, including your Apple or Google identity, name, email where supplied by the provider, and phone number.",
          "Delivery addresses, precise location when you choose to share it, cart and order history, item preferences, payment references, refunds and support cases.",
          "Photos or other evidence you submit for delivery, returns, safety or issue resolution.",
          "Device, browser, session and notification-subscription information used to keep your account secure and deliver service updates.",
        ],
      },
      {
        title: "Authentication and contact details",
        paragraphs: [
          "Customers sign in with Apple or Google. Your phone number is collected after sign-in as contact information; it is not proof of account ownership and Dastak does not use SMS OTP for customer sign-in.",
          "We do not automatically merge accounts because an email address or phone number matches. Linking Apple and Google identities requires an explicit authenticated linking flow.",
        ],
      },
      {
        title: "How we use information",
        bullets: [
          "Provide catalogue discovery, matching, payment, preparation, pickup, delivery, refunds, returns and customer support.",
          "Confirm service availability, calculate routes and transport eligibility, prevent fraud, secure handoffs and enforce account permissions.",
          "Send transactional order and security notifications and maintain reliable operational and audit records.",
          "Meet legal, accounting, safety and dispute-resolution obligations.",
        ],
      },
      {
        title: "Who receives information",
        paragraphs: [
          "We disclose only what is reasonably needed to fulfil the service. Assigned merchants receive the relevant request and operational contact details; assigned delivery partners receive pickup and delivery information. Retail merchant identity remains hidden from customers, while Restaurant/Cafe identity may be shown as part of the selected food order.",
          "We also use service providers for hosting and authentication (Supabase), customer payments (Razorpay), Apple or Google sign-in, notifications (Apple Push Notification service and Web Push), and web delivery (Vercel). They process information for those services under their own security and legal obligations.",
          "We may disclose information when required by law or when necessary to protect customers, partners, Dastak or the public. We do not sell personal data or use it for third-party behavioural advertising.",
        ],
      },
      {
        title: "Payments",
        paragraphs: [
          "Razorpay processes customer payment credentials. Dastak records the amount, provider references, status, reconciliation and refund information needed to operate and audit an order; Dastak does not ask customers to send card or UPI credentials through support.",
        ],
      },
      {
        title: "Your choices and rights",
        bullets: [
          "You can update profile and address information, review active sessions and revoke other sessions from your account.",
          "Location, camera and notification access use device or browser permission controls and can be changed there.",
          "You can request account deletion from the signed-in account flow. Dastak revokes access and anonymises or removes personal data where permitted, while preserving required order, payment, refund, custody, settlement and audit history.",
          "You can report an order issue, request an eligible refund or raise a privacy concern through the tracked support paths described on the Support page.",
        ],
      },
      {
        title: "Retention and security",
        paragraphs: [
          "We retain information only as needed for the service, security, legal compliance, accounting and dispute resolution. Transactional history may be retained after account deletion with identifying data minimised or anonymised where permitted.",
          "Dastak uses authenticated access, role-based permissions, encrypted network transport, immutable financial and custody records, audit history and operational monitoring. No system is risk-free, so report suspected account misuse promptly through the signed-in account or order flow.",
        ],
      },
      {
        title: "Policy updates",
        paragraphs: [
          "We may update this policy when the service or legal requirements change. The current version and effective date will remain available at this URL. Material changes will be communicated through an appropriate in-product notice where required.",
        ],
      },
    ],
  },
  terms: {
    kind: "terms",
    eyebrow: "Using Dastak",
    title: "Terms of Service",
    summary: "The customer terms for browsing, ordering, payment, fulfilment, delivery and support through Dastak.",
    updated,
    sections: [
      {
        title: "Your account",
        paragraphs: [
          "By using Dastak, you agree to these terms and the Privacy Policy. Customer access requires an Apple or Google account followed by completion of the Dastak profile. Keep your provider account and device secure and give accurate profile, address and contact information.",
          "An account belongs to the authenticated identity that created it. A phone number or matching email alone does not prove ownership. Do not share verification codes, impersonate another person or use Dastak for unlawful activity.",
        ],
      },
      {
        title: "The service",
        paragraphs: [
          "Dastak coordinates catalogue discovery, merchant confirmation, payment, preparation, multi-stop pickup and delivery. Service availability depends on the delivery zone, item availability, merchant capacity, route feasibility and eligible delivery partners.",
          "Retail products use Dastak's canonical catalogue and retail merchant identity is not displayed to customers. Restaurant/Cafe identity and its managed menu remain visible for food orders. Dastak never silently substitutes an item or reroutes a selected Restaurant/Cafe request to another restaurant.",
        ],
      },
      {
        title: "Orders and pricing",
        bullets: [
          "Your basket may contain retail items and at most one Restaurant/Cafe. Dastak must secure every required fulfilment before payment becomes available.",
          "The final payable amount displayed by Dastak before payment is server-authoritative. Review the basket, address and total before paying.",
          "Launch orders are prepaid only. Cash on delivery, substitutions and scheduled orders are not supported.",
          "Adding an item to the cart or submitting a request does not guarantee availability; an order is secured only when Dastak confirms the complete plan.",
        ],
      },
      {
        title: "Payment, cancellation and refunds",
        paragraphs: [
          "Customer payments are processed through Razorpay. A failed payment may be retried while the reservation remains active. A late provider success after reservation expiry will not revive the order and will be reconciled or reversed through the payment process.",
          "Customers may cancel before successful payment. After payment, normal cancellation is unavailable because merchants and delivery operations may already be committed. Use the order's help flow for missing, damaged, incorrect or undelivered items. Approved refunds are issued to the original payment method; bank or payment-provider posting times may vary.",
        ],
      },
      {
        title: "Preparation and delivery",
        paragraphs: [
          "Preparation estimates are estimates, not guarantees. Dastak may coordinate multiple pickup stops while presenting one customer order. Keep the delivery address and contact number current and provide safe, lawful access to the destination.",
          "Dastak uses in-app verification codes and evidence for secure pickup and delivery. The buyer may share the final delivery code with an intended recipient, who does not need a Dastak account. Treat active codes as confidential and provide them only at the correct handoff stage.",
        ],
      },
      {
        title: "Issues, returns and recovery",
        paragraphs: [
          "Report an issue promptly from the relevant order and provide truthful details or evidence when requested. Some retail items may be eligible for physical return or exact-item recovery. Prepared food is not physically returnable; food complaints are investigated for an appropriate refund or other resolution.",
          "Dastak may use delivery recovery and authorised Operations actions when a normal custody handoff cannot safely continue. Every exceptional action is recorded separately from normal verification.",
        ],
      },
      {
        title: "Fair use and account action",
        paragraphs: [
          "Do not interfere with matching, payments, verification, evidence, support or another person's account; submit fraudulent requests; abuse merchants or delivery partners; or attempt to bypass security controls. Dastak may restrict access when reasonably necessary for security, safety, law or serious breach, while preserving valid financial and consumer obligations.",
        ],
      },
      {
        title: "Availability and responsibility",
        paragraphs: [
          "Dastak works to provide a reliable service, but availability can be affected by inventory, traffic, weather, device connectivity, provider outages and events outside reasonable control. Nothing in these terms excludes rights or remedies that cannot lawfully be excluded under Indian consumer law.",
        ],
      },
      {
        title: "Law, changes and support",
        paragraphs: [
          "These terms are governed by the laws of India, subject to applicable consumer protections and the jurisdiction available to you by law. We may update these terms as the service or law changes; the current version and effective date will remain at this URL.",
          "For order, account or privacy assistance, use Dastak's Support page and the tracked help flow inside the relevant signed-in order or account.",
        ],
      },
    ],
  },
  support: {
    kind: "support",
    eyebrow: "Help centre",
    title: "Dastak Support",
    summary: "Use the signed-in order and account flows so Dastak can securely connect each request to the right customer and history.",
    updated,
    actions: [
      {
        title: "Help with an order",
        detail: "Open an order to report items, payment, delivery, refund or safety issues and follow the recorded case.",
        href: "/#/orders",
      },
      {
        title: "Account and privacy",
        detail: "Update your profile, review sessions, manage linked identities or request account deletion.",
        href: "/#/account",
      },
      {
        title: "Read the Privacy Policy",
        detail: "Understand what Dastak collects, why it is used and the choices available to you.",
        href: "/privacy",
      },
    ],
    sections: [
      {
        title: "Order help",
        paragraphs: [
          "Sign in, open Orders, select the affected order and choose the available help or issue action. Select the closest category, describe what happened and attach a clear photo when useful. The resulting issue and its status remain attached to the order for Operations review.",
          "For an active delivery or safety concern, report it from that order immediately. If anyone is in immediate danger, contact local emergency services first.",
        ],
      },
      {
        title: "Payment and refund help",
        paragraphs: [
          "Check the order state before trying payment again. A failed attempt can be retried only while the secured payment window is active. If money is confirmed after an expired window, Dastak records it for reconciliation rather than reviving the order.",
          "Approved customer refunds go to the original payment method. Dastak shows the recorded refund state, while the final posting time depends on the payment provider or bank.",
        ],
      },
      {
        title: "Sign-in and account recovery",
        paragraphs: [
          "Use the same Apple or Google identity that created the Dastak account. Dastak does not use phone numbers or SMS OTP as proof of ownership and does not merge accounts merely because an email or phone number matches.",
          "If you can sign in to an existing Dastak account, use its account-security flow to link a second Apple or Google identity explicitly. You must prove control of both identities.",
        ],
      },
      {
        title: "Privacy and account deletion",
        paragraphs: [
          "Open Account to update contact information, inspect sessions, sign out other devices or request deletion. Deletion invalidates access and anonymises eligible personal data while legally required transaction and audit history is preserved.",
        ],
      },
      {
        title: "Keep your account safe",
        bullets: [
          "Never share an active payment, pickup or delivery verification code before the correct in-person handoff.",
          "Dastak support will not ask for your Apple or Google password, full card details, UPI PIN or device passcode.",
          "Use only the Dastak customer app or this official website for account and order actions.",
        ],
      },
      {
        title: "Support channel",
        paragraphs: [
          "Dastak handles customer support through the secure signed-in order and account experiences linked above. This public page is the official support URL; no public support email is used.",
        ],
      },
    ],
  },
};

export function publicInformationKindForPath(pathname: string): PublicInformationKind | undefined {
  const normalized = pathname.trim().replace(/\/+$/, "") || "/";
  if (normalized === "/privacy") return "privacy";
  if (normalized === "/terms") return "terms";
  if (normalized === "/support") return "support";
  return undefined;
}
