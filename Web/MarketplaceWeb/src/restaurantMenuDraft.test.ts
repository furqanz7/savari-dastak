import { describe, expect, it } from "vitest";
import { createVersionedDraft, editVersionedDraft, reconcileVersionedDraft, useLatestVersionedDraft } from "./restaurantMenuDraft";

describe("restaurant menu draft concurrency", () => {
  it("adopts a newer server version when the draft is pristine", () => {
    const draft = createVersionedDraft({ name: "Tea", price: "20" }, 1);
    expect(reconcileVersionedDraft(draft, { name: "Masala tea", price: "25" }, 2)).toEqual({
      value: { name: "Masala tea", price: "25" }, serverValue: { name: "Masala tea", price: "25" },
      loadedVersion: 2, dirty: false, stale: false,
    });
  });

  it("keeps a dirty local draft and marks it stale when different server data arrives", () => {
    const dirty = editVersionedDraft(createVersionedDraft({ name: "Tea" }, 3), { name: "My tea" });
    const stale = reconcileVersionedDraft(dirty, { name: "Server tea" }, 4);
    expect(stale).toMatchObject({ value: { name: "My tea" }, serverValue: { name: "Server tea" }, loadedVersion: 4, dirty: true, stale: true });
    expect(useLatestVersionedDraft(stale)).toMatchObject({ value: { name: "Server tea" }, dirty: false, stale: false, loadedVersion: 4 });
  });

  it("recognizes an authoritative response matching the submitted draft", () => {
    const dirty = editVersionedDraft(createVersionedDraft({ name: "Tea" }, 3), { name: "Updated tea" });
    expect(reconcileVersionedDraft(dirty, { name: "Updated tea" }, 4)).toMatchObject({ dirty: false, stale: false, loadedVersion: 4 });
  });
});
