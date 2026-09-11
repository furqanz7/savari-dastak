// @vitest-environment jsdom
import { act, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AdminPrivilegedActionDialog } from "./AdminPrivilegedActionDialog";
import {
  resetAdminMutationStateForTests,
  runAdminPrivilegedMutation,
} from "./adminPrivilegedMutation";

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

describe("Admin privileged mutation reliability", () => {
  beforeEach(() => resetAdminMutationStateForTests());

  it("reconciles an uncertain result and reuses the logical operation key", async () => {
    const keys: string[] = [];
    const reconcile = vi.fn().mockResolvedValue(undefined);
    const first = await runAdminPrivilegedMutation({
      operationIdentity: "refund:one",
      mutate: async (key) => {
        keys.push(key);
        throw Object.assign(new Error("timeout"), { code: "request_timeout", status: 0 });
      },
      reconcile,
    });
    const second = await runAdminPrivilegedMutation({
      operationIdentity: "refund:one",
      mutate: async (key) => { keys.push(key); },
      reconcile,
    });
    const third = await runAdminPrivilegedMutation({
      operationIdentity: "refund:one",
      mutate: async (key) => { keys.push(key); },
      reconcile,
    });

    expect(first.kind).toBe("uncertain_reconciled");
    expect(second.kind).toBe("completed");
    expect(third.kind).toBe("completed");
    expect(keys[1]).toBe(keys[0]);
    expect(keys[2]).not.toBe(keys[1]);
    expect(reconcile).toHaveBeenCalledTimes(3);
  });

  it.each(["stale_version", "invalid_state", "not_found"])(
    "quietly reconciles %s as authoritative concurrency",
    async (code) => {
      const reconcile = vi.fn().mockResolvedValue(undefined);
      const result = await runAdminPrivilegedMutation({
        operationIdentity: `operation:${code}`,
        mutate: async () => { throw Object.assign(new Error(code), { code, status: 409 }); },
        reconcile,
      });
      expect(result.kind).toBe("reconciled");
      expect(reconcile).toHaveBeenCalledOnce();
    },
  );

  it("locks an unknown outcome when authoritative reconciliation also fails", async () => {
    const result = await runAdminPrivilegedMutation({
      operationIdentity: "handoff:one",
      mutate: async () => { throw Object.assign(new Error("offline"), { code: "network_error", status: 0 }); },
      reconcile: async () => { throw new Error("still offline"); },
    });
    expect(result.kind).toBe("uncertain_blocked");
  });

  it("locks replay when a successful command cannot be authoritatively reloaded", async () => {
    const keys: string[] = [];
    const first = await runAdminPrivilegedMutation({
      operationIdentity: "settlement:one",
      mutate: async (key) => { keys.push(key); },
      reconcile: async () => { throw new Error("reload failed"); },
    });
    const second = await runAdminPrivilegedMutation({
      operationIdentity: "settlement:one",
      mutate: async (key) => { keys.push(key); },
      reconcile: async () => undefined,
    });
    expect(first.kind).toBe("uncertain_blocked");
    expect(keys[1]).toBe(keys[0]);
    expect(second.kind).toBe("completed");
  });

  it("prevents concurrent double submission of the same logical action", async () => {
    let release!: () => void;
    const pending = new Promise<void>((resolve) => { release = resolve; });
    const first = runAdminPrivilegedMutation({
      operationIdentity: "executive:seat-one",
      mutate: () => pending,
      reconcile: async () => undefined,
    });
    const duplicate = await runAdminPrivilegedMutation({
      operationIdentity: "executive:seat-one",
      mutate: async () => undefined,
      reconcile: async () => undefined,
    });
    expect(duplicate.kind).toBe("failed");
    release();
    expect((await first).kind).toBe("completed");
  });
});

describe("Admin privileged confirmation dialog", () => {
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
  const render = async (node: ReactNode) => { await act(async () => root.render(node)); };

  it("shows exact impact and requires the reviewed Executive email", async () => {
    const confirm = vi.fn();
    await render(<AdminPrivilegedActionDialog intent={{
      title: "Assign Executive Admin 1?",
      entityLabel: "Reviewed account email",
      entityValue: "executive@example.com",
      currentState: "Empty seat",
      resultingState: "Executive Admin 1",
      consequence: "Receives full operational capabilities across orders, finance and safety.",
      confirmLabel: "Grant full Admin access",
      reasonOptions: ["Role assignment", "Security response"],
      confirmationValue: "executive@example.com",
    }} onDismiss={() => undefined} onConfirm={confirm} />);

    expect(host.querySelector('[role="alertdialog"]')).not.toBeNull();
    expect(host.textContent).toContain("executive@example.com");
    expect(host.textContent).toContain("Empty seat");
    expect(host.textContent).toContain("Executive Admin 1");
    expect(host.textContent).toContain("full operational capabilities");
    const submit = [...host.querySelectorAll("button")].find((button) => button.textContent?.includes("Grant full Admin access"))!;
    expect(submit.disabled).toBe(true);
    const match = host.querySelector(".admin-confirmation-match input") as HTMLInputElement;
    await act(async () => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
      setter?.call(match, "executive@example.com");
      match.dispatchEvent(new Event("input", { bubbles: true }));
    });
    expect(submit.disabled).toBe(false);
    await act(async () => submit.click());
    expect(confirm).toHaveBeenCalledWith("Role assignment");
  });
});
