import type { ReplayStore } from "./handler.ts";

type ReplayRecord = { digest: string; expiresAt: string };

export class FileReplayStore implements ReplayStore {
  private readonly entries = new Map<string, number>();
  private writeChain = Promise.resolve();
  private writesSinceCompaction = 0;

  private constructor(
    private readonly path: string,
    private readonly now: () => Date,
  ) {}

  static async open(path: string, now: () => Date = () => new Date()) {
    if (!path.startsWith("/") || path.endsWith("/")) {
      throw new Error("Replay store path must be an absolute file path");
    }
    const store = new FileReplayStore(path, now);
    await store.load();
    return store;
  }

  async claim(digest: string, expiresAt: Date) {
    if (!/^[0-9a-f]{64}$/.test(digest) || !Number.isFinite(expiresAt.valueOf())) {
      throw new Error("Invalid replay claim");
    }
    const now = this.now().valueOf();
    this.prune(now);
    if ((this.entries.get(digest) ?? 0) > now) return false;
    this.entries.set(digest, expiresAt.valueOf());
    try {
      await this.serializeWrite(async () => {
        await this.append({ digest, expiresAt: expiresAt.toISOString() });
        this.writesSinceCompaction += 1;
        if (this.writesSinceCompaction >= 1_000) await this.compact();
      });
    } catch (error) {
      this.entries.delete(digest);
      throw error;
    }
    return true;
  }

  private async load() {
    const directory = this.path.slice(0, this.path.lastIndexOf("/")) || "/";
    await Deno.mkdir(directory, { recursive: true, mode: 0o700 });
    let contents = "";
    try {
      contents = await Deno.readTextFile(this.path);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      const file = await Deno.open(this.path, {
        createNew: true,
        write: true,
        mode: 0o600,
      });
      file.close();
      return;
    }
    const now = this.now().valueOf();
    for (const line of contents.split("\n")) {
      if (!line) continue;
      let record: ReplayRecord;
      try {
        record = JSON.parse(line) as ReplayRecord;
      } catch {
        throw new Error("Replay store is corrupt");
      }
      const expiresAt = new Date(record.expiresAt).valueOf();
      if (!/^[0-9a-f]{64}$/.test(record.digest) || !Number.isFinite(expiresAt)) {
        throw new Error("Replay store is corrupt");
      }
      if (expiresAt > now) {
        this.entries.set(record.digest, Math.max(this.entries.get(record.digest) ?? 0, expiresAt));
      }
    }
    await this.compact();
  }

  private prune(now: number) {
    for (const [digest, expiresAt] of this.entries) {
      if (expiresAt <= now) this.entries.delete(digest);
    }
  }

  private async append(record: ReplayRecord) {
    const file = await Deno.open(this.path, { append: true, write: true, mode: 0o600 });
    try {
      await file.write(new TextEncoder().encode(`${JSON.stringify(record)}\n`));
      await file.sync();
    } finally {
      file.close();
    }
  }

  private async compact() {
    this.prune(this.now().valueOf());
    const temporaryPath = `${this.path}.tmp`;
    const body = Array.from(
      this.entries,
      ([digest, expiresAt]) =>
        JSON.stringify({ digest, expiresAt: new Date(expiresAt).toISOString() }),
    ).join("\n");
    await Deno.writeTextFile(temporaryPath, body ? `${body}\n` : "", {
      create: true,
      mode: 0o600,
    });
    await Deno.rename(temporaryPath, this.path);
    this.writesSinceCompaction = 0;
  }

  private serializeWrite(operation: () => Promise<void>) {
    const next = this.writeChain.then(operation, operation);
    this.writeChain = next.catch(() => undefined);
    return next;
  }
}
