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

const updated = "17 October 2026";

export const publicInformationPages: Record<PublicInformationKind, PublicInformationPage> = {
  privacy: {
    kind: "privacy",
    eyebrow: "Your data",
    title: "Privacy Policy",
    summary: "How Dastak collects, uses and protects information when you shop, operate a Merchant store or fulfil deliveries.",
    updated: "28 October 2026",
    sections: [
      {
        title: "Information we collect",
        bullets: [
          "Account and profile details, including your Apple or Google identity, name, email where supplied by the provider, and phone number.",
          "Delivery addresses, precise location when you choose to share it, cart and order history, item preferences, payment references, refunds and support cases.",
          "Photos or other evidence you submit for delivery, returns, safety or issue resolution.",
          "Device, browser, session and notification-subscription information used to keep your account secure and deliver service updates.",
          "For delivery-partner onboarding and account operations: submitted identity and applicable vehicle documents, earnings, balances, withdrawals and any bank-account or UPI payout details you provide through an available registration flow.",
          "Operational diagnostics, including request timestamps, IP addresses, user-agent information, account or session identifiers where present, response status, processing times and server runtime or error information. These records may be linked to your account and are used to operate, secure and troubleshoot the service, not for third-party behavioural advertising.",
        ],
      },
      {
        title: "Authentication and contact details",
        paragraphs: [
          "Customers and Merchants sign in with the Apple or Google options offered by the app. We receive the identity information supplied through that sign-in, such as an account identifier, name and email address. Your profile phone number is contact information, not proof of account ownership. Merchant workspace access also requires an approved application and the appropriate business permissions. Signing in or editing a profile does not approve a Merchant application.",
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
          "We also use service providers for hosting, authentication and operational logging (Supabase), Apple or Google sign-in, notifications (Apple Push Notification service and Web Push), and web delivery (Vercel). Where an older supported online-payment flow uses Razorpay, it processes the payment for that flow. They process information for those services under their own security and legal obligations.",
          "For Merchant operations, Dastak uses Supabase for authentication, application and operational records, evidence storage and service/security logging; Apple or Google for the sign-in option you choose; Apple Push Notification service for native notifications; Apple's map/location services for place lookup; and Vercel for public web pages, including the Merchant support interface. Where an enabled payout flow uses a configured gateway or RazorpayX, the information needed to set up the destination or process and reconcile that payout is sent through that service. Access to private Merchant records is limited by the authorized workspace and operational/service-provider access required for those purposes. These uses are not Dastak's third-party behavioural advertising or sale of personal data. Providers also process data under their applicable terms and security/legal obligations.",
          "We may disclose information when required by law or when necessary to protect customers, partners, Dastak or the public. We do not sell personal data or use it for third-party behavioural advertising.",
        ],
      },
      {
        title: "Merchant applications and store verification",
        paragraphs: [
          "When you apply to become a Merchant, we collect the legal and customer-facing business names, business address, selected pickup location and the government identity or business-registration document you submit. The document can include your photograph, address and identity or registration information. Submit only the document needed for the application; do not upload unrelated personal records. We use these details to review the application, verify store access, prevent misuse and coordinate fulfilment. Verification documents are private evidence, not public storefront images.",
          "You can search for a pickup address or choose a map pin. If you explicitly use your current location, the iOS app requests location access while you are using it. The map, place search and address lookup use Apple's map/location services. The pickup address and the precise coordinates you choose are sent to Dastak and associated with the application/store. Merchant pickup selection is not a continuous background location-tracking feature. You can change location permission in device Settings and choose an address or pin without a GPS fix.",
        ],
      },
      {
        title: "Operating a Merchant store",
        paragraphs: [
          "Dastak records catalogue selections, stock and availability, restaurant menu items and add-ons where applicable, descriptions, prices, operating settings, order responses, preparation estimates, package counts, ready photos, handoffs, problem reports and related operational history. These records are associated with the authorized account and business so Dastak can manage fulfilment, resolve disputes and maintain an audit trail. Restaurant/Café identity, menus and published images may be visible to customers. Private verification documents and fulfilment evidence are not treated as public storefront media.",
          "Grocery catalogue search sends the search text to Dastak to find matching products. Restaurant menu filtering may be performed on your device. Technical request and error records may be retained as described under Retention and security; this policy does not promise that all search requests are unlogged.",
        ],
      },
      {
        title: "Merchant earnings and payout information",
        paragraphs: [
          "Merchant financial records include Royalty ledger entries, adjustments, settlements, available balances and withdrawal requests. When payout-destination setup is available for your business and you choose to use it, the app collects the holder name and bank-account/IFSC or UPI details you enter. Dastak may send the required destination information to the configured payout service, including RazorpayX where used, and retain provider references, masked destination details, verification fingerprints and transaction/status records needed to operate, secure and audit the service.",
          "Available payout actions depend on current business permissions and service configuration. A displayed balance does not guarantee that withdrawals are enabled or that money has reached a bank. Destination setup and withdrawal requests are separate actions. Never send bank passwords or UPI PINs to Dastak support. The current Customer iOS doorstep-payment flow is separate from Merchant earnings and payout processing.",
        ],
      },
      {
        title: "Merchant data kept on your device",
        paragraphs: [
          "The app may keep unsaved menu drafts, account-scoped preferences and the original details of an uncertain action on your device so you can review or recover it without silently changing the request. Submitted changes and their operational records are handled by the server; an unresolved local action is not proof that the server action failed.",
          "Merchant payout-destination recovery details use device-only Keychain storage, not menu draft files, UserDefaults or iCloud synchronization. The app retains those original details for recovery until its confirmed cleanup flow completes. Refreshing Earnings does not itself request a withdrawal. Local-only information is not automatically a remote collection; data you submit for a real operation is considered separately.",
        ],
      },
      {
        title: "Exploring the Merchant demo",
        paragraphs: [
          "Explore the demo opens a clearly labelled sample workspace without signing in. Its orders, store changes, evidence and financial actions are simulated locally; they do not create real orders, upload your documents, dispatch a rider or transfer money. Reset or Exit discards the sample session, and the demo's changes are not added to a real Merchant account. Merchant support is disabled inside the sample; exit the demo to use the real support page. The demo does not test remote push delivery or actual provider operations.",
        ],
      },
      {
        title: "Merchant support conversations",
        paragraphs: [
          "You can contact Merchant support through the form at https://dastak-merchant.vercel.app/merchant-support without signing in or providing an email address. We store the category, summary and message you submit, request and message references, conversation status, replies and their timestamps. Authorized Dastak Admin staff can review and respond, and staff replies are associated with the replying Admin account. If your message includes an order reference or identifying details, that information is part of the conversation. No sign-in requirement does not mean a message is anonymous.",
          "A private recovery code is generated in your browser. The code is sent securely to the support service when you create, open or reply to the request. The service hashes its secret before sending it to ticket storage, which stores the hash rather than the original secret. This statement concerns ticket storage, not a promise that no hosting/security request record can contain submitted data. Anyone with the complete code can read and reply to that conversation. Keep it private; do not send it to support. Save it before leaving, because a lost code cannot be recovered through the form.",
          "We do not email replies or guarantee a response time. Return to the page with your saved code to check replies. Do not submit passwords, UPI PINs, bank-account numbers, identity documents or active handoff codes. A support message is not proof of account ownership and cannot authorize account approval, an account change, an order change or a payment. This is not an emergency service.",
        ],
      },
      {
        title: "Optional weather scenery on iOS",
        paragraphs: [
          "Before sign-in, you may choose to connect the scenery to local weather. With your permission, the iOS app rounds your nearby-area latitude and longitude to two decimal places and sends that approximate location to Apple Weather through WeatherKit. Weather-location requests run while the sign-in scenery is visible, refresh no more often than every 15 minutes, and stop when the app is inactive or the scenery closes.",
          "Dastak does not send your saved delivery address, Dastak account credentials or account identifier with these weather requests, and does not retain weather-location fixes or attach them to your Dastak account. The weather data is transformed into scenery effects. You can disconnect weather in Settings; the scenery then follows the device clock. Apple processes weather requests under its own privacy terms, and the app provides Apple Weather attribution and data-source information.",
        ],
      },
      {
        title: "Payments",
        paragraphs: [
          "The current Customer iOS Grocery and Food checkout uses Pay via UPI/Cash on Delivery. Payment is collected by the delivery partner at the doorstep; Dastak records the selected collection method, amount and collection status. This release does not include Razorpay checkout or online-payment retries for older merchant or parcel orders.",
          "Where an older supported online-payment flow is available on another Dastak platform, Razorpay processes its payment credentials. Dastak records the amount, provider references, status, reconciliation and refund information needed to operate and audit that order. Dastak does not ask customers to send card, bank or UPI credentials through support.",
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
        title: "Merchant account and privacy choices",
        paragraphs: [
          "Merchant Account provides available profile, identity-linking, session and privacy controls. You can request account deletion through its confirmed signed-in flow. Required transactional, financial, custody and audit records may remain, with personal identifiers minimized or anonymized where permitted. The public support conversation is not automatically connected to your login; signing out or deleting an account does not by itself identify and erase every support conversation. You may raise a privacy concern through Merchant support, but unverified text does not establish account ownership or authorize a change.",
        ],
      },
      {
        title: "Retention and security",
        paragraphs: [
          "We retain information only as needed for the service, security, legal compliance, accounting and dispute resolution. Transactional history may be retained after account deletion with identifying data minimised or anonymised where permitted.",
          "Merchant applications, evidence, store operations and financial records are kept as needed to operate the service, secure access, review applications, maintain required history and handle accounting, legal obligations or disputes. Technical hosting/authentication records may include request times, IP-derived network or approximate geographic information, user agent, account/session identifiers, response status, processing times and runtime/error details. Provider retention depends on service configuration. Dastak does not promise a fixed deletion date for those records in this policy.",
          "The Merchant support service currently has storage-capacity limits but no automatic conversation-expiry schedule. Closing or resolving a conversation does not mean its stored messages have been deleted. Privacy requests and retention decisions must take account of security, recordkeeping and applicable obligations; this policy does not promise immediate or automatic erasure.",
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
          "Your basket may contain retail items and at most one Restaurant/Cafe. Dastak must secure every required fulfilment before order confirmation becomes available.",
          "The final payable amount displayed by Dastak before confirmation is server-authoritative. Review the basket, address and total before confirming.",
          "Current Grocery and Food orders use Pay via UPI/Cash on Delivery. Review the secured basket and final total before confirming. Confirmation starts preparation; payment is collected by the delivery partner at the doorstep. No payment is taken when you confirm.",
          "Adding an item to the cart or submitting a request does not guarantee availability; an order is secured only when Dastak confirms the complete plan.",
        ],
      },
      {
        title: "Payment, cancellation and refunds",
        paragraphs: [
          "The current Customer iOS release does not offer Razorpay checkout, online-payment retries for older orders, or new prepaid parcel orders. Older order history remains viewable. Where an older supported online-payment flow is available on another Dastak platform, its provider and available payment actions are shown for that order.",
          "Use Cancel order while it is available before confirmation. Confirmation starts preparation, after which normal customer cancellation is unavailable. For an issue with a confirmed order or a payment already collected, use that order’s help flow. Any approved resolution, refund method and timing will be communicated for the case. Do not make a second payment to resolve an uncertain payment result without checking the recorded order state and contacting support.",
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
          "For current Grocery and Food orders, confirm the secured basket in the app, then pay the assigned delivery partner by UPI or cash at the doorstep. Check the recorded amount and collection status before paying again. If the payment result is uncertain or incorrect, open the affected order’s help flow.",
          "Online-payment retries for older orders are unavailable in the current Customer iOS release. Older order history remains available for reference. Report a payment or refund issue from the affected order; the applicable resolution, refund method and timing will be communicated for the case. Never send a UPI PIN, bank password or full card credentials through support.",
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
