import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { MerchantOperationsStatus } from "./MerchantV1Opportunities";
import {
  initialMerchantFeedStates,
  merchantFeedFailed,
  merchantFeedSucceeded,
  type MerchantFeedKey,
} from "./merchantOperationsState";

describe("Merchant operations status", () => {
  it("keeps loading, error, and empty states mutually exclusive", () => {
    const loading = renderToStaticMarkup(
      <MerchantOperationsStatus states={initialMerchantFeedStates()} hasContent={false} />,
    );
    expect(loading).toContain("Loading fulfilments");
    expect(loading).not.toContain("New exact-item requests");

    const failedStates = merchantFeedFailed(
      initialMerchantFeedStates(),
      "retail",
      { code: "network_error" },
    );
    const failed = renderToStaticMarkup(
      <MerchantOperationsStatus states={failedStates} hasContent={false} />,
    );
    expect(failed).toContain("Incoming retail requests could not update");
    expect(failed).not.toContain("New exact-item requests");
    expect(failed).not.toContain("Loading fulfilments");

    let settled = initialMerchantFeedStates();
    const feeds: MerchantFeedKey[] = ["retail", "restaurant", "fulfilments", "recovery", "returns", "settlements", "legacy"];
    feeds.forEach((feed) => { settled = merchantFeedSucceeded(settled, feed); });
    const empty = renderToStaticMarkup(
      <MerchantOperationsStatus states={settled} hasContent={false} />,
    );
    expect(empty).toContain("New exact-item requests will appear here");
    expect(empty).not.toContain("could not update");
  });

  it("preserves populated content semantics during a non-blocking feed failure", () => {
    const states = merchantFeedFailed(
      initialMerchantFeedStates(),
      "settlements",
      new Error("temporary failure"),
    );
    const markup = renderToStaticMarkup(
      <MerchantOperationsStatus states={states} hasContent />,
    );
    expect(markup).toContain("Settlements could not update");
    expect(markup).toContain("Previously loaded information remains visible");
    expect(markup).not.toContain("New exact-item requests");
  });

  it("presents session expiry as recovery rather than an empty desk", () => {
    const states = merchantFeedFailed(
      initialMerchantFeedStates(),
      "fulfilments",
      { status: 401, code: "jwt_expired" },
    );
    const markup = renderToStaticMarkup(
      <MerchantOperationsStatus states={states} hasContent={false} />,
    );
    expect(markup).toContain("Your session expired");
    expect(markup).toContain("returning you to sign in");
    expect(markup).not.toContain("New exact-item requests");
  });
});
