export type VersionedDraft<T> = {
  value: T;
  serverValue: T;
  loadedVersion: number;
  dirty: boolean;
  stale: boolean;
};

export function createVersionedDraft<T>(value: T, version: number): VersionedDraft<T> {
  return { value, serverValue: value, loadedVersion: version, dirty: false, stale: false };
}

export function editVersionedDraft<T>(draft: VersionedDraft<T>, value: T): VersionedDraft<T> {
  return { ...draft, value, dirty: !equal(value, draft.serverValue) };
}

export function reconcileVersionedDraft<T>(
  draft: VersionedDraft<T>,
  serverValue: T,
  serverVersion: number,
): VersionedDraft<T> {
  if (serverVersion <= draft.loadedVersion) return draft;
  if (equal(serverValue, draft.value)) return createVersionedDraft(serverValue, serverVersion);
  if (!draft.dirty) return createVersionedDraft(serverValue, serverVersion);
  return { ...draft, serverValue, loadedVersion: serverVersion, stale: true };
}

export function useLatestVersionedDraft<T>(draft: VersionedDraft<T>): VersionedDraft<T> {
  return createVersionedDraft(draft.serverValue, draft.loadedVersion);
}

function equal<T>(left: T, right: T) {
  return JSON.stringify(left) === JSON.stringify(right);
}
