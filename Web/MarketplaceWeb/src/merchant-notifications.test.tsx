import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { MerchantNotificationStatus } from "./MerchantOrdersView";
import type { DastakWebPushController } from "./useDastakWebPush";

function controller(status: DastakWebPushController["status"]): DastakWebPushController {
  return { status, shouldPrompt: status === "prompt", enable: vi.fn(), dismiss: vi.fn(), refresh: vi.fn() };
}

describe("merchant notification status", () => {
  it("offers merchant-specific new request onboarding", () => {
    const markup = renderToStaticMarkup(<MerchantNotificationStatus controller={controller("prompt")} />);
    expect(markup).toContain("Don’t miss a new request");
    expect(markup).toContain("incoming retail and restaurant requests");
    expect(markup).toContain("Enable alerts");
  });

  it("shows enabled and blocked states truthfully", () => {
    expect(renderToStaticMarkup(<MerchantNotificationStatus controller={controller("enabled")} />))
      .toContain("New-order alerts on");
    expect(renderToStaticMarkup(<MerchantNotificationStatus controller={controller("blocked")} />))
      .toContain("Order alerts are blocked");
  });
});
