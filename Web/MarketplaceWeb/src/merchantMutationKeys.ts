export class MerchantMutationKeys {
  private readonly keys = new Map<string, { fingerprint: string; key: string }>();

  keyFor(identity: string, payload: unknown) {
    const fingerprint = JSON.stringify(payload);
    const existing = this.keys.get(identity);
    if (existing?.fingerprint === fingerprint) return existing.key;
    const key = crypto.randomUUID();
    this.keys.set(identity, { fingerprint, key });
    return key;
  }

  clear(identity: string) {
    this.keys.delete(identity);
  }
}
