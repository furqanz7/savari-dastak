// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { refreshVisibleAdminWorkspaces, useAdminWorkspaceRefresh } from "./adminRefresh";

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

function RegisteredRefreshes({ liveOrders, network }: {
  liveOrders: () => Promise<void>;
  network: () => Promise<void>;
}) {
  useAdminWorkspaceRefresh("liveOrders", liveOrders);
  useAdminWorkspaceRefresh("network", network);
  return null;
}

describe("Admin targeted refresh registry", () => {
  let host: HTMLDivElement;
  let root: Root;
  beforeEach(() => {
    host = document.createElement("div");
    document.body.append(host);
    root = createRoot(host);
  });
  afterEach(async () => {
    await act(async () => root.unmount());
    host.remove();
  });

  it("routes a realtime invalidation only to the affected workspace", async () => {
    const liveOrders = vi.fn().mockResolvedValue(undefined);
    const network = vi.fn().mockResolvedValue(undefined);
    await act(async () => root.render(<RegisteredRefreshes liveOrders={liveOrders} network={network} />));

    await refreshVisibleAdminWorkspaces(["liveOrders"]);
    expect(liveOrders).toHaveBeenCalledOnce();
    expect(network).not.toHaveBeenCalled();

    await refreshVisibleAdminWorkspaces();
    expect(liveOrders).toHaveBeenCalledTimes(2);
    expect(network).toHaveBeenCalledOnce();
  });
});
