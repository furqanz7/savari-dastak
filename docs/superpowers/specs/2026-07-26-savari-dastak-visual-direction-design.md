# Savari and Dastak Visual Direction

**Status:** Approved  
**Date:** 2026-07-26

## Purpose

This specification defines the shared visual direction for Savari and Dastak
across iOS and web. It governs product UI, interaction, motion, accessibility,
and cross-platform consistency. It does not authorize implementation by itself.

## Direction

The shared direction is **Apple-native spatial minimalism**.

Both products should feel as deliberate, clear, responsive, and accessible as
products designed by Apple. This means applying Apple's product principles, not
copying Apple branding, artwork, or individual screens.

The interface should be:

- content-first and restrained;
- spatially coherent, with materials and motion explaining hierarchy;
- native to each platform;
- precise enough that every visible element has a purpose;
- usable across English, Tamil, Dynamic Type, and accessibility settings.

## Product Relationship

Savari and Dastak are sibling brands. They share typography, spacing,
iconography, materials, interaction rules, motion, and quality standards while
retaining distinct identities.

### Savari

- Map-first and movement-focused.
- MapKit, routes, vehicles, and live position form the visual canvas.
- Cooler navigational blues and route greens support the neutral interface.
- One stable spatial surface communicates the current ride state.

### Dastak

- Product and merchant-first during discovery.
- Products and merchant content provide most of the visible colour.
- A restrained warm coral or vermilion accent distinguishes the brand.
- The shopping experience combines Apple Store-like discovery, Apple Maps-like
  live delivery, and Apple Wallet-like orders, payments, and receipts.

## Shared Foundation

- Use SF Pro and native system typography with Dynamic Type on iOS.
- Render Tamil with Apple's system script typography.
- Support automatic light and dark appearances.
- Use neutral system backgrounds and black or white primary actions.
- Reserve semantic colours for navigation, success, warning, and destructive
  states.
- Use Liquid Glass or equivalent materials only for navigation, search,
  spatial overlays, floating controls, and live status.
- Prefer full-width lists and content shelves over decorative card layouts.
- Avoid nested cards, ornamental gradients, floating decoration, and excessive
  promotional surfaces.
- Use native icons, gestures, spring motion, and haptics where appropriate.
- Present one visually dominant next action for each product state.
- Maintain at least 44-point interactive targets and accessible contrast.

No exact production colour values are approved by this direction document.
Colour tokens require a separately reviewed visual proposal before they enter
product code.

## Brand Treatment

The permanent wordmark treatment is bilingual:

- **Savari | سواری**
- **Dastak | دستک**

The Latin and Urdu forms must be designed as balanced lockups rather than two
unrelated fonts placed together. The Urdu treatment should retain a refined
Nastaliq character while remaining legible at product sizes.

### Asset Ownership

The product team will design the bilingual wordmarks.

The owner will separately decide and provide:

- app icons;
- launch screens and launch animations;
- product, merchant, and brand imagery.

Development may use neutral temporary placeholders for these owner-supplied
assets. Placeholders must never be presented as final brand work.

## Dastak Customer

### Navigation

The primary navigation contains Home, Search, Orders, and Account. Delivery
Partner mode is entered through Account rather than competing with customer
navigation.

### Discovery

- Show the delivery address as navigation context.
- Place a prominent native search field beneath it.
- Lead with products and categories, with merchant attribution visible.
- Follow with personal and local shelves such as Buy Again, Nearby, and Daily
  Essentials.
- Use promotions selectively as editorial features, not persistent banner
  clutter.
- Use stable product-image proportions, clear quantities, prices, and compact
  purchase controls.

### Shopping and Checkout

- Product details open in a focused sheet or full-screen view.
- Adding an item uses subtle motion and haptic confirmation.
- A spatial cart control appears only after the cart contains an item.
- Checkout follows address, items, payment, and confirmation in that order.
- Loading, failure, dismissal, and retry states preserve user context.

### Live Delivery

After assignment, the experience transitions from product-first to map-first:

- MapKit becomes the full-screen canvas.
- Courier and route information remain visually unambiguous.
- One stable bottom sheet represents every delivery stage.
- Contact, verification, support, and cancellation appear contextually.
- Completion resolves into a receipt-style order summary.

## Dastak Delivery Partner

The Partner experience is map-first and task-first.

- Use full-screen MapKit, a compact top status surface, and one operational
  bottom sheet.
- Offline presents a clear Go Online action and a concise daily summary.
- Online waiting contains no fake activity, decorative pins, or irrelevant
  controls.
- Assignment offers show only merchant, delivery type, pickup and drop-off
  areas, distance, duration, payout, and response time.
- Each active stage exposes exactly one primary action: navigate to merchant,
  arrive, verify pickup, navigate to customer, arrive, verify delivery, and
  complete.
- Technical identifiers and backend state names never appear.
- Calls, support, details, and incident reporting remain secondary actions.
- Completion shows a compact earnings receipt before returning cleanly to
  online waiting.

## Dastak Merchant

- Primary navigation contains Orders, Catalogue, Store, and Account.
- Orders open first and group work by actionable state.
- New orders receive clear visual and haptic priority.
- Each order shows preparation, payment assurance, customer-safe details, and
  one next action.
- Catalogue management uses clear imagery placeholders, availability controls,
  and compact price editing.
- Product creation uses a focused sequence rather than a single dense form.
- Completed orders move into history instead of remaining mixed with active
  work.

## Dastak Admin

- Primary areas are Today, Orders, Accounts, Money, Incidents, and Settings.
- Today contains exceptions requiring owner attention, not decorative metrics.
- Approvals place identity evidence and decision controls together.
- Orders use searchable and filterable operational lists.
- Financial views use statement-like presentation rather than generic
  dashboard decoration.
- Incidents use semantic severity without making the entire interface alarming.
- Consequential actions require clear confirmation and expose their audit
  history.
- iOS uses `NavigationSplitView` where suitable; web expands the same hierarchy
  into a restrained operational sidebar.

## Motion and Interaction

- Motion explains origin, destination, hierarchy, or state change.
- Sheets rise from their originating controls and dismiss coherently.
- Product additions move subtly toward the cart.
- Delivery-stage changes reframe the map and update the stable spatial sheet.
- Navigation uses platform-native transitions.
- Success uses concise visual and haptic confirmation.
- Destructive actions require deliberate confirmation without theatrical
  animation.
- Use content-shaped loading placeholders; reserve blocking spinners for
  genuinely blocking work.
- Show errors beside the affected action and preserve entered information.
- Support Reduce Motion and increased contrast from the beginning.

## Cross-Platform Translation

iOS is the visual source of truth. Existing web workflows remain a behavioural
reference until their redesigned equivalents are complete.

Shared across platforms:

- brand and semantic colour roles;
- typography hierarchy;
- spacing, iconography, language, and imagery placement;
- product states and action hierarchy;
- light and dark appearances;
- motion intent and accessibility outcomes.

iOS uses native SwiftUI navigation, sheets, controls, haptics, gestures, and
MapKit. Web adapts the same system to responsive layouts, keyboard and pointer
input, and larger workspaces. Web must not look like a stretched iPhone or
imitate mobile sheets where desktop patterns are more appropriate.

Customer and Partner web experiences remain mobile-first. Merchant and Admin
expand into efficient desktop workspaces.

## Visual Completion Standard

A screen is not visually complete until:

- it has one clear purpose and one dominant next action;
- it contains no UUIDs, database states, or technical labels;
- loading, empty, populated, error, restricted, and offline states are stable;
- materials, spacing, corners, icons, and sheets follow the shared system;
- maps contain only information relevant to the current task;
- text and pricing remain understandable without relying on imagery;
- light mode, dark mode, Dynamic Type, increased contrast, Reduce Motion,
  English, and Tamil have been reviewed;
- representative iPhone and web viewport screenshots have been inspected;
- iOS approval precedes the equivalent web visual implementation.

The acceptance standard is not merely that the products resemble iOS. Every
decision must feel deliberate enough that Apple could plausibly have made it.
