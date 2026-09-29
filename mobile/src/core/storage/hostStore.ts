import { hostFromJson, hostToJson, type Host } from '../models/host';
import { normalizeFingerprint } from '../api/pin';
import { SecureKeys, type SecureStore } from '../security/secureStore';

/** Non-secret key/value storage (host metadata, settings). Never used for tokens, pins or keys. */
export interface KeyValueStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}

export class MemoryKeyValueStore implements KeyValueStore {
  readonly data = new Map<string, string>();
  async get(key: string) {
    return this.data.get(key) ?? null;
  }
  async set(key: string, value: string) {
    this.data.set(key, value);
  }
  async remove(key: string) {
    this.data.delete(key);
  }
}

// Same key as the Flutter app (`rfe_hosts_v1`). The value here is one JSON
// array of host records; the Flutter StringList form is converted on import.
export const HOSTS_KEY = 'rfe_hosts_v1';
const lastSeenKey = (id: string) => `rfe_last_seen_${id}`;

export class HostStore {
  constructor(
    private readonly kv: KeyValueStore,
    private readonly secure: SecureStore,
  ) {}

  async listHosts(): Promise<Host[]> {
    const raw = await this.kv.get(HOSTS_KEY);
    if (!raw) return [];
    let arr: unknown;
    try {
      arr = JSON.parse(raw);
    } catch {
      return [];
    }
    if (!Array.isArray(arr)) return [];
    // One corrupt record must never hide the rest of the list (PR-54).
    return arr.map((e) => hostFromJson(typeof e === 'string' ? safeParse(e) : e)).filter((h): h is Host => h !== null);
  }

  private save(hosts: Host[]) {
    return this.kv.set(HOSTS_KEY, JSON.stringify(hosts.map(hostToJson)));
  }

  async addHost(host: Host) {
    const hosts = (await this.listHosts()).filter((h) => h.id !== host.id);
    hosts.push(host);
    await this.save(hosts);
  }

  async updateHost(host: Host) {
    const hosts = await this.listHosts();
    const i = hosts.findIndex((h) => h.id === host.id);
    if (i < 0) return this.addHost(host);
    hosts[i] = host;
    await this.save(hosts);
  }

  /**
   * Commits a freshly paired host, its token and pin as one unit. Secrets are
   * written first (pin before token) and the visible host record last, so a
   * failure at any step can never leave a listed host without its pin or token;
   * on failure everything written so far is removed.
   */
  async commitPairing(host: Host, o: { token: string; fingerprint: string }) {
    const pin = normalizeFingerprint(o.fingerprint);
    if (pin === null) throw new Error('refusing to commit pairing without a valid certificate pin');
    const done: string[] = [];
    try {
      await this.secure.write(SecureKeys.fingerprint(host.id), pin);
      done.push(SecureKeys.fingerprint(host.id));
      await this.secure.write(SecureKeys.token(host.id), o.token);
      done.push(SecureKeys.token(host.id));
      await this.addHost({ ...host, certFingerprint: pin });
    } catch (e) {
      for (const k of done) await this.secure.delete(k).catch(() => undefined);
      throw e;
    }
  }

  async touchHost(id: string) {
    const hosts = await this.listHosts();
    const i = hosts.findIndex((h) => h.id === id);
    if (i <= 0) return;
    hosts.unshift(...hosts.splice(i, 1));
    await this.save(hosts);
  }

  async removeHost(id: string) {
    await this.save((await this.listHosts()).filter((h) => h.id !== id));
    await this.secure.delete(SecureKeys.token(id));
    await this.secure.delete(SecureKeys.fingerprint(id));
    await this.kv.remove(lastSeenKey(id));
  }

  /** Last successful /health, shown on offline hosts. */
  async getLastSeen(id: string): Promise<Date | null> {
    const raw = await this.kv.get(lastSeenKey(id));
    const ms = raw === null ? NaN : Number(raw);
    return Number.isFinite(ms) ? new Date(ms) : null;
  }

  setLastSeen(id: string, at: Date = new Date()) {
    return this.kv.set(lastSeenKey(id), String(at.getTime()));
  }

  getToken(id: string) {
    return this.secure.read(SecureKeys.token(id));
  }

  /** The secure-store pin is authoritative; the host record's mirror is never used for trust. */
  async getPin(id: string): Promise<string | null> {
    return normalizeFingerprint(await this.secure.read(SecureKeys.fingerprint(id)));
  }
}

function safeParse(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}
