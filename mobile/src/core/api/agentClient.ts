import { routeAddresses, routeForAddress, type Host, type HostRoute } from '../models/host';
import {
  parseDrive,
  parseHealth,
  parseListing,
  parseStatus,
  type AgentStatus,
  parsePairResponse,
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
    if (this.pin !== null && this.opts.deviceToken) headers.Authorization = `Bearer ${this.opts.deviceToken}`;
    return this.opts.transport.request({
      url,
      method,
      headers,
      bodyText: json === undefined ? null : JSON.stringify(json),
      pin: this.pin,
    });
  }

  private async call(
    method: string,
    path: string,
    o: { query?: Record<string, string | number | undefined>; json?: unknown } = {},
  ): Promise<unknown> {
    let res;
    try {
      res = await this.send(this.addrIndex, method, path, o.query, o.json);
    } catch (e) {
      const code = errCode(e);
      if (code === ERR_CERT_PIN_MISMATCH) throw new CertPinMismatch();
      if (code === ERR_PIN_POLICY) throw new MissingCertPin();
      if (code !== ERR_CONNECTION || !isSafeToRetryOnFallback(method) || this.addresses.length < 2) {
        throw this.toApiError(e);
      }
      res = await this.fallback(method, path, o, e);
    }
    return this.parse(res);
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
}
