import { routeAddresses, routeForAddress, type Host, type HostRoute } from '../models/host';
import {
  parseDrive,
  parseHealth,
  parseArchiveEntry,
  parseBatchResult,
  parseEntry,
  parseListing,
  parseTrashEntry,
  type ArchiveEntry,
  type BatchResult,
  type Entry,
  type TrashEntry,
  parseStatus,
  type AgentStatus,
  parsePairResponse,
  parseSearchResult,
  parseShareLink,
  type SearchResult,
  type ShareLink,
  type Drive,
  type Health,
  type Listing,
  type PairResponse,
} from './models';
import { CertPinMismatch, MissingCertPin, normalizeFingerprint } from './pin';

/** Native transport surface (implemented by modules/rfe-transport; faked in tests). */
export type TransportResponse = { status: number; headers: Record<string, string>; bodyText: string };

export interface Transport {
  request(args: {
    url: string;
    method: string;
    headers: Record<string, string>;
    bodyText: string | null;
    pin: string | null;
    timeoutMs?: number;
  }): Promise<TransportResponse>;
}

/** Error codes the native transport rejects with. */
export const ERR_CERT_PIN_MISMATCH = 'ERR_CERT_PIN_MISMATCH';
export const ERR_PIN_POLICY = 'ERR_PIN_POLICY';
export const ERR_CONNECTION = 'ERR_CONNECTION';

export class AgentApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'AgentApiError';
  }
}

const isSafeToRetryOnFallback = (m: string) => m === 'GET' || m === 'HEAD';

/** Only these two calls may run before a pin exists; neither carries a secret. */
export function isSafeUnpinnedPreflight(method: string, path: string): boolean {
  return (method === 'GET' && path === '/health') || (method === 'POST' && path === '/auth/challenge');
}

const errCode = (e: unknown): string | undefined =>
  typeof e === 'object' && e !== null && 'code' in e ? String((e as { code: unknown }).code) : undefined;

export type AgentClientOptions = {
  transport: Transport;
  deviceToken?: string;
  /** Secure-store pin (never the metadata mirror). */
  pinnedFingerprint?: string | null;
  clientVersion?: string;
  /** Start from LAN (health probes) instead of the last good route. */
  probeLanFirst?: boolean;
  /** Per-request timeout for the native transport (connect/read/write). */
  timeoutMs?: number;
};

/**
 * Pinned agent client. Mirrors agent_client.dart: bearer token only after a
 * valid pin exists, no redirects, GET/HEAD-only route fallback, and pin
 * failures never trigger fallback.
 */
export class AgentClient {
  private static lastGoodRoute = new Map<string, number>();

  private readonly pin: string | null;
  private readonly addresses: string[];
  private addrIndex: number;

  constructor(
    readonly host: Host,
    private readonly opts: AgentClientOptions,
  ) {
    this.pin = normalizeFingerprint(opts.pinnedFingerprint ?? null);
    if (opts.pinnedFingerprint != null && this.pin === null) throw new MissingCertPin();
    if (opts.deviceToken && this.pin === null) throw new MissingCertPin();
    this.addresses = routeAddresses(host).map((r) => r.address);
    this.addrIndex = opts.probeLanFirst
      ? 0
      : Math.min(Math.max(AgentClient.lastGoodRoute.get(host.id) ?? 0, 0), this.addresses.length - 1);
  }

  get activeAddress(): string {
    return this.addresses[this.addrIndex];
  }

  get activeRoute(): HostRoute {
    return routeForAddress(this.host, this.activeAddress);
  }

  private async send(
    addrIndex: number,
    method: string,
    path: string,
    query: Record<string, string | number | undefined> | undefined,
    json: unknown,
    text?: string,
  ) {
    if (this.pin === null && !isSafeUnpinnedPreflight(method, path)) throw new MissingCertPin();
    const qs = query
      ? Object.entries(query)
          .filter(([, v]) => v !== undefined)
          .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
          .join('&')
      : '';
    const url = `https://${this.addresses[addrIndex]}/v1${path}${qs ? `?${qs}` : ''}`;
    const headers: Record<string, string> = { 'X-RFE-Client-Version': this.opts.clientVersion ?? 'rn' };
    if (json !== undefined) headers['Content-Type'] = 'application/json';
    else if (text !== undefined) headers['Content-Type'] = 'application/octet-stream';
    if (this.pin !== null && this.opts.deviceToken) headers.Authorization = `Bearer ${this.opts.deviceToken}`;
    return this.opts.transport.request({
      url,
      method,
      headers,
      bodyText: json !== undefined ? JSON.stringify(json) : (text ?? null),
      pin: this.pin,
      timeoutMs: this.opts.timeoutMs,
    });
  }

  private async call(
    method: string,
    path: string,
    o: { query?: Record<string, string | number | undefined>; json?: unknown; text?: string } = {},
  ): Promise<unknown> {
    return (await this.callFull(method, path, o)).body;
  }

  /** Like [call] but also returns the response headers (search reports truncation there). */
  private async callFull(
    method: string,
    path: string,
    o: { query?: Record<string, string | number | undefined>; json?: unknown; text?: string } = {},
  ): Promise<{ body: unknown; headers: Record<string, string> }> {
    let res;
    try {
      res = await this.send(this.addrIndex, method, path, o.query, o.json, o.text);
    } catch (e) {
      const code = errCode(e);
      if (code === ERR_CERT_PIN_MISMATCH) throw new CertPinMismatch();
      if (code === ERR_PIN_POLICY) throw new MissingCertPin();
      if (code !== ERR_CONNECTION || !isSafeToRetryOnFallback(method) || this.addresses.length < 2) {
        throw this.toApiError(e);
      }
      res = await this.fallback(method, path, o, e);
    }
    return { body: this.parse(res), headers: res.headers };
  }

  private async fallback(
    method: string,
    path: string,
    o: { query?: Record<string, string | number | undefined>; json?: unknown },
    first: unknown,
  ) {
    const source = this.addrIndex;
    let last: unknown = first;
    for (let i = 0; i < this.addresses.length; i++) {
      if (i === source) continue;
      try {
        const res = await this.send(i, method, path, o.query, o.json);
        this.addrIndex = i;
        AgentClient.lastGoodRoute.set(this.host.id, i);
        return res;
      } catch (e) {
        // A pin mismatch is a security failure, not a reason to try another URL.
        if (errCode(e) === ERR_CERT_PIN_MISMATCH) throw new CertPinMismatch();
        if (errCode(e) !== ERR_CONNECTION) throw this.toApiError(e);
        last = e;
      }
    }
    throw this.toApiError(last);
  }

  private toApiError(e: unknown): Error {
    if (e instanceof AgentApiError || e instanceof CertPinMismatch || e instanceof MissingCertPin) return e;
    if (errCode(e) === ERR_CONNECTION) {
      return new AgentApiError(0, 'CONNECTION', 'Connection lost — check your network and try again.');
    }
    return new AgentApiError(0, 'UNKNOWN', e instanceof Error ? e.message : String(e));
  }

  private parse(res: TransportResponse): unknown {
    let body: unknown;
    try {
      body = res.bodyText.length ? JSON.parse(res.bodyText) : null;
    } catch {
      body = null;
    }
    if (res.status >= 200 && res.status < 300) return body;
    const b = (typeof body === 'object' && body !== null ? body : {}) as Record<string, unknown>;
    throw new AgentApiError(
      res.status,
      typeof b.code === 'string' ? b.code : 'UNKNOWN',
      typeof b.message === 'string' ? b.message : `HTTP ${res.status}`,
    );
  }

  /**
   * Everything the native streaming downloader needs. Credentials are attached
   * only with a valid pin; the native side re-checks the pin during the TLS
   * handshake before any header is written.
   */
  downloadSpec(remotePath: string): { url: string; headers: Record<string, string>; pin: string } {
    if (this.pin === null) throw new MissingCertPin();
    const headers: Record<string, string> = { 'X-RFE-Client-Version': this.opts.clientVersion ?? 'rn' };
    if (this.opts.deviceToken) headers.Authorization = `Bearer ${this.opts.deviceToken}`;
    return {
      url: `https://${this.activeAddress}/v1/content?path=${encodeURIComponent(remotePath)}`,
      headers,
      pin: this.pin,
    };
  }

  /** URL + credentials for the native thumbnail fetch (`GET /thumb`, JPEG, longest side ~[size] px). */
  thumbnailSpec(remotePath: string, size = 256): { url: string; headers: Record<string, string>; pin: string } {
    if (this.pin === null) throw new MissingCertPin();
    const headers: Record<string, string> = { 'X-RFE-Client-Version': this.opts.clientVersion ?? 'rn' };
    if (this.opts.deviceToken) headers.Authorization = `Bearer ${this.opts.deviceToken}`;
    return { url: `https://${this.activeAddress}/v1/thumb?path=${encodeURIComponent(remotePath)}&size=${size}`, headers, pin: this.pin };
  }

  async health(): Promise<Health> {
    return parseHealth((await this.call('GET', '/health')) as Record<string, unknown>);
  }

  /** Effective scope, roots and read-only policy for this device (`GET /settings`). */
  async status(): Promise<AgentStatus> {
    return parseStatus((await this.call('GET', '/settings')) as Record<string, unknown>);
  }

  async challenge(): Promise<string> {
    const d = (await this.call('POST', '/auth/challenge')) as Record<string, unknown>;
    return d.nonce as string;
  }

  async login(a: {
    username: string;
    password: string;
    deviceLabel: string;
    devicePublicKey: string;
    nonce: string;
    signature: string;
    deviceId?: string;
  }): Promise<PairResponse> {
    const { deviceId, ...rest } = a;
    const d = await this.call('POST', '/login', { json: { ...rest, ...(deviceId ? { deviceId } : {}) } });
    return parsePairResponse(d as Record<string, unknown>);
  }

  async register(a: {
    pairingCode: string;
    username: string;
    password: string;
    deviceLabel: string;
    devicePublicKey: string;
    nonce: string;
    signature: string;
    deviceId?: string;
  }): Promise<PairResponse> {
    const { deviceId, ...rest } = a;
    const d = await this.call('POST', '/register', { json: { ...rest, ...(deviceId ? { deviceId } : {}) } });
    return parsePairResponse(d as Record<string, unknown>);
  }

  async pair(a: {
    pairingCode: string;
    deviceLabel: string;
    devicePublicKey: string;
    nonce: string;
    signature: string;
    deviceId?: string;
  }): Promise<PairResponse> {
    const { deviceId, ...rest } = a;
    const d = await this.call('POST', '/pair', { json: { ...rest, ...(deviceId ? { deviceId } : {}) } });
    return parsePairResponse(d as Record<string, unknown>);
  }

  async drives(): Promise<Drive[]> {
    const d = (await this.call('GET', '/system/drives')) as Record<string, unknown>[];
    return d.map(parseDrive);
  }

  async list(path: string, o: { cursor?: string; limit?: number } = {}): Promise<Listing> {
    const d = await this.call('GET', '/fs', { query: { path, cursor: o.cursor, limit: o.limit ?? 200 } });
    return parseListing(d as Record<string, unknown>);
  }

  // ---------------------------------------------------------------------------
  // Filesystem — read
  // ---------------------------------------------------------------------------

  async meta(path: string): Promise<Entry> {
    return parseEntry((await this.call('GET', '/fs/meta', { query: { path } })) as Record<string, unknown>);
  }

  async checksum(path: string, algo = 'sha256'): Promise<string> {
    const d = (await this.call('GET', '/fs/checksum', { query: { path, algo } })) as Record<string, unknown>;
    return d.checksum as string;
  }

  async archiveList(path: string, limit?: number): Promise<ArchiveEntry[]> {
    const d = (await this.call('GET', '/fs/archive', { query: { path, limit } })) as Record<string, unknown>;
    return (Array.isArray(d.entries) ? (d.entries as Record<string, unknown>[]) : []).map(parseArchiveEntry);
  }

  /** Path -> hex hash; files the agent could not hash are omitted. */
  async batchChecksums(paths: string[], algo = 'sha256'): Promise<Record<string, string>> {
    const d = (await this.call('POST', '/fs/checksums', { json: { paths, algo } })) as Record<string, unknown>;
    const out: Record<string, string> = {};
    for (const it of Array.isArray(d.checksums) ? (d.checksums as Record<string, unknown>[]) : []) {
      if (typeof it.hash === 'string' && it.hash.length > 0 && typeof it.path === 'string') out[it.path] = it.hash;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Filesystem — write
  // ---------------------------------------------------------------------------

  /**
   * Overwrites a file with UTF-8 [text] (agent cap 5 MiB). [baseModified] (the Entry.modified last read)
   * makes the write optimistic: the agent answers 409 STALE_WRITE if the file changed since. Other
   * typed failures arrive as AgentApiError codes READ_ONLY and PAYLOAD_TOO_LARGE.
   */
  async putContent(path: string, text: string, baseModified?: string): Promise<Entry> {
    return parseEntry((await this.call('PUT', '/content', { query: { path, baseModified }, text })) as Record<string, unknown>);
  }

  private async entry(method: string, path: string, json: unknown): Promise<Entry> {
    return parseEntry((await this.call(method, path, { json })) as Record<string, unknown>);
  }

  createFolder(path: string) {
    return this.entry('POST', '/fs/folder', { path });
  }

  createFile(path: string) {
    return this.entry('POST', '/fs/file', { path });
  }

  rename(src: string, dst: string) {
    return this.entry('PATCH', '/fs/rename', { src, dst });
  }

  chmod(path: string, mode: string) {
    return this.entry('POST', '/fs/chmod', { path, mode });
  }

  /** Collision precedence is server-side: `duplicate` (keep both) wins over `overwrite`; otherwise a CONFLICT per item. */
  async copy(sources: string[], destDir: string, o: { duplicate?: boolean; overwrite?: boolean } = {}): Promise<BatchResult> {
    const d = await this.call('POST', '/fs/copy', { json: { sources, destDir, duplicate: o.duplicate ?? false, overwrite: o.overwrite ?? false } });
    return parseBatchResult(d as Record<string, unknown>);
  }

  async move(sources: string[], destDir: string, o: { duplicate?: boolean; overwrite?: boolean } = {}): Promise<BatchResult> {
    const d = await this.call('POST', '/fs/move', { json: { sources, destDir, duplicate: o.duplicate ?? false, overwrite: o.overwrite ?? false } });
    return parseBatchResult(d as Record<string, unknown>);
  }

  /** Reversible (agent trash) unless `permanent`. */
  async delete(paths: string[], o: { permanent?: boolean } = {}): Promise<BatchResult> {
    const d = await this.call('DELETE', '/fs', { query: o.permanent ? { permanent: 'true' } : undefined, json: { paths } });
    return parseBatchResult(d as Record<string, unknown>);
  }

  async listTrash(): Promise<TrashEntry[]> {
    const d = (await this.call('GET', '/trash')) as Record<string, unknown>;
    return (Array.isArray(d.items) ? (d.items as Record<string, unknown>[]) : []).map(parseTrashEntry);
  }

  async restoreTrash(ids: string[]): Promise<BatchResult> {
    return parseBatchResult((await this.call('POST', '/trash/restore', { json: { ids } })) as Record<string, unknown>);
  }

  async emptyTrash(ids?: string[]): Promise<void> {
    await this.call('DELETE', '/trash', { json: ids ? { ids } : undefined });
  }

  /** The agent auto-renames if `dest` exists; the returned entry has the real path. */
  compress(sources: string[], dest: string) {
    return this.entry('POST', '/fs/compress', { sources, dest });
  }

  extract(archive: string, destDir: string) {
    return this.entry('POST', '/fs/extract', { archive, destDir });
  }

  // ---------------------------------------------------------------------------
  // Search and recents
  // ---------------------------------------------------------------------------

  /** Filters are ANDed server-side; `*` or `?` in [q] makes it a glob. Truncation state is on the result, not an error. */
  async search(o: {
    q: string;
    root?: string;
    limit?: number;
    types?: string[];
    ext?: string[];
    minSize?: number;
    maxSize?: number;
    modifiedAfter?: Date;
    modifiedBefore?: Date;
  }): Promise<SearchResult> {
    const { body, headers } = await this.callFull('GET', '/search', {
      query: {
        q: o.q,
        root: o.root,
        limit: o.limit ?? 100,
        types: o.types?.length ? o.types.join(',') : undefined,
        ext: o.ext?.length ? o.ext.join(',') : undefined,
        minSize: o.minSize,
        maxSize: o.maxSize,
        modifiedAfter: o.modifiedAfter?.toISOString(),
        modifiedBefore: o.modifiedBefore?.toISOString(),
      },
    });
    return parseSearchResult(body, headers);
  }

  /** Most recently modified files (never folders), newest first. */
  async recent(o: { root?: string; limit?: number } = {}): Promise<SearchResult> {
    const { body, headers } = await this.callFull('GET', '/fs/recent', { query: { root: o.root, limit: o.limit ?? 100 } });
    return parseSearchResult(body, headers);
  }

  // ---------------------------------------------------------------------------
  // Share links
  // ---------------------------------------------------------------------------

  /** One-time unauthenticated download link. 403 when the agent has sharing disabled, 413 above 500 MiB. */
  async mintShareLink(path: string, expiresInSeconds = 900): Promise<ShareLink> {
    return parseShareLink((await this.call('POST', '/share/mint', { json: { path, expiresInSeconds } })) as Record<string, unknown>);
  }

  /** [tokenHash] is the hash from the mint response, not the raw token. */
  async revokeShareLink(tokenHash: string): Promise<void> {
    await this.call('DELETE', `/share/${encodeURIComponent(tokenHash)}`);
  }

  async listShareLinks(): Promise<ShareLink[]> {
    const d = await this.call('GET', '/share');
    return (Array.isArray(d) ? (d as Record<string, unknown>[]) : []).map(parseShareLink);
  }
}
