import { AgentApiError, AgentClient, type Transport } from '../../core/api/agentClient';
import type { PairResponse } from '../../core/api/models';
import { CertPinMismatch, MissingCertPin, normalizeFingerprint } from '../../core/api/pin';
import type { Host } from '../../core/models/host';
import type { DeviceIdentity } from '../../core/security/deviceIdentity';
import type { HostStore } from '../../core/storage/hostStore';
import { matchCode } from './matchCode';

export type PairingDeps = {
  transport: Transport;
  identity: DeviceIdentity;
  store: HostStore;
  /** Android ID; lets a re-pair of the same phone reuse its device row. */
  deviceId: () => Promise<string | null>;
  deviceLabel?: string;
  /** TLS handshake only: the leaf SHA-256 the host at `https://<address>` presents. Never sends a request. */
  probe: (url: string) => Promise<string>;
  randomBytes: (n: number) => Uint8Array;
};

export type PairingTarget = { address: string; fingerprint: string };

/** Fields of the pairing QR: `{"address","certFingerprint","pairingCode"}`. */
export type PairingQr = { address: string; certFingerprint: string; pairingCode: string };

export type QrParseError = 'invalidQrFormat' | 'qrMissingFields' | 'qrInvalidFingerprint';

export function parsePairingQr(raw: string): { ok: true; qr: PairingQr } | { ok: false; error: QrParseError } {
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return { ok: false, error: 'invalidQrFormat' };
  }
  if (typeof json !== 'object' || json === null || Array.isArray(json)) return { ok: false, error: 'invalidQrFormat' };
  const j = json as Record<string, unknown>;
  if (typeof j.address !== 'string' || typeof j.certFingerprint !== 'string' || typeof j.pairingCode !== 'string') {
    return { ok: false, error: 'qrMissingFields' };
  }
  const fp = normalizeFingerprint(j.certFingerprint);
  if (fp === null) return { ok: false, error: 'qrInvalidFingerprint' };
  return { ok: true, qr: { address: j.address, certFingerprint: fp, pairingCode: j.pairingCode } };
}

/** Message shown for a failed call (port of humanizeError). */
export function humanizeError(e: unknown): string {
  if (e instanceof CertPinMismatch) return 'This computer’s identity has changed, so RFE refused to connect. If you reinstalled its agent, remove this computer and pair it again. If not, do not trust this network.';
  if (e instanceof MissingCertPin) return e.message;
  if (e instanceof AgentApiError) {
    // A streamed download only knows the status; the agent's own message (when there is one) already says what is missing.
    if (e.code === 'CAPABILITY_DENIED' || (e.statusCode === 403 && /^HTTP \d+$/.test(e.message))) {
      return 'This computer has not allowed this phone to do that. Allow it on the computer, in the device’s access settings.';
    }
    return e.message;
  }
  const message = e instanceof Error ? e.message : String(e);
  // A native module rejection wraps the real reason: "Call to function 'X.y' has been rejected.\n→ Caused by: <reason>".
  return message.replace(/^Call to function '[^']*' has been rejected\.\s*→ Caused by:\s*/, '');
}

async function proof(client: AgentClient, identity: DeviceIdentity) {
  // The challenge goes through the pinned client too: a wrong host is rejected
  // before anything (even a nonce request) is exchanged.
  const nonce = await client.challenge();
  return {
    devicePublicKey: await identity.publicKeyBase64(),
    nonce,
    signature: await identity.signBase64(nonce),
  };
}

async function commit(deps: PairingDeps, target: PairingTarget, resp: PairResponse): Promise<Host> {
  const pin = normalizeFingerprint(target.fingerprint);
  if (pin === null) throw new MissingCertPin();
  if (!resp.deviceToken || !resp.deviceId) throw new AgentApiError(0, 'BAD_RESPONSE', 'The host returned an incomplete pairing response.');
  const host: Host = {
    id: resp.deviceId,
    label: resp.agentName || target.address,
    address: target.address.trim(),
    certFingerprint: pin,
    tailscaleAddress: resp.tailscaleAddress,
  };
  await deps.store.commitPairing(host, { token: resp.deviceToken, fingerprint: pin });
  return host;
}

function pinnedClient(deps: PairingDeps, target: PairingTarget): AgentClient {
  const pin = normalizeFingerprint(target.fingerprint);
  if (pin === null) throw new MissingCertPin();
  return new AgentClient(
    { id: 'pairing_probe', label: 'probe', address: target.address.trim(), certFingerprint: pin },
    { transport: deps.transport, pinnedFingerprint: pin },
  );
}

export async function pairWithCode(deps: PairingDeps, target: PairingTarget, pairingCode: string): Promise<Host> {
  const client = pinnedClient(deps, target);
  const p = await proof(client, deps.identity);
  const resp = await client.pair({
    pairingCode: pairingCode.trim(),
    deviceLabel: deps.deviceLabel ?? 'Mobile App',
    ...p,
    deviceId: (await deps.deviceId()) ?? undefined,
  });
  return commit(deps, target, resp);
}

export async function loginWithAccount(
  deps: PairingDeps,
  target: PairingTarget,
  creds: { username: string; password: string },
): Promise<Host> {
  const client = pinnedClient(deps, target);
  const p = await proof(client, deps.identity);
  const resp = await client.login({
    username: creds.username.trim(),
    password: creds.password,
    deviceLabel: deps.deviceLabel ?? 'Mobile App',
    ...p,
    deviceId: (await deps.deviceId()) ?? undefined,
  });
  return commit(deps, target, resp);
}

export async function registerAccount(
  deps: PairingDeps,
  target: PairingTarget,
  a: { pairingCode: string; username: string; password: string },
): Promise<Host> {
  const client = pinnedClient(deps, target);
  const p = await proof(client, deps.identity);
  const resp = await client.register({
    pairingCode: a.pairingCode.trim(),
    username: a.username.trim(),
    password: a.password,
    deviceLabel: deps.deviceLabel ?? 'Mobile App',
    ...p,
    deviceId: (await deps.deviceId()) ?? undefined,
  });
  return commit(deps, target, resp);
}

/** The owner rejected the request on the computer. */
export class PairRejected extends Error {
  constructor() {
    super('The computer declined this pairing request.');
    this.name = 'PairRejected';
  }
}

/** Nobody answered on the computer in time. */
export class PairExpired extends Error {
  constructor() {
    super('The pairing request timed out. Ask again and approve it on the computer.');
    this.name = 'PairExpired';
  }
}

export type PairRequestHandle = { target: PairingTarget; requestId: string; clientNonce: string; matchCode: string; expiresInSeconds: number };

/**
 * Learns the certificate the host at [address] presents (first contact, trust on first use) so the user never has to
 * see or type a fingerprint; every later request is pinned to it.
 */
export async function probeTarget(deps: PairingDeps, address: string): Promise<PairingTarget> {
  const authority = address.trim().replace(/^https?:\/\//, '').replace(/\/+$/, '');
  const fp = normalizeFingerprint(await deps.probe(`https://${authority}`));
  if (fp === null) throw new MissingCertPin();
  return { address: authority, fingerprint: fp };
}

const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');

/**
 * Asks the computer at [address] to approve this phone; nothing is typed. The certificate the host presents is
 * pinned on first contact (the user never sees or enters it); the match code the computer shows is derived from that
 * pin, so a machine relaying the connection produces a code that differs from the one on the computer's screen.
 */
export async function requestPairing(deps: PairingDeps, address: string): Promise<PairRequestHandle> {
  const target = await probeTarget(deps, address);
  const fp = target.fingerprint;
  const client = pinnedClient(deps, target);
  const p = await proof(client, deps.identity);
  const clientNonce = hex(deps.randomBytes(16));
  const r = await client.requestPair({
    deviceLabel: deps.deviceLabel ?? 'Mobile App',
    clientNonce,
    ...p,
    deviceId: (await deps.deviceId()) ?? undefined,
  });
  if (!r.requestId) throw new AgentApiError(0, 'BAD_RESPONSE', 'The host returned an incomplete pairing response.');
  return { target, requestId: r.requestId, clientNonce, matchCode: matchCode(fp, clientNonce, r.requestId), expiresInSeconds: r.expiresInSeconds };
}

/** Polls until the owner answers; resolves with the paired host. Aborting stops polling (the request lapses on the computer). */
export async function awaitPairing(
  deps: PairingDeps,
  h: PairRequestHandle,
  o: { signal?: AbortSignal; intervalMs?: number; sleep?: (ms: number) => Promise<void>; now?: () => number } = {},
): Promise<Host> {
  const client = pinnedClient(deps, h.target);
  const sleep = o.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const now = o.now ?? Date.now;
  const deadline = now() + (h.expiresInSeconds + 5) * 1000;
  let transient = 0;
  while (!o.signal?.aborted) {
    if (now() > deadline) throw new PairExpired();
    try {
      const s = await client.pairRequestStatus(h.requestId, h.clientNonce);
      transient = 0;
      if (s.status === 'approved') return commit(deps, h.target, s.response);
      if (s.status === 'rejected') throw new PairRejected();
    } catch (e) {
      if (e instanceof PairRejected || e instanceof CertPinMismatch || e instanceof MissingCertPin) throw e;
      if (e instanceof AgentApiError && e.code === 'NOT_FOUND') throw new PairExpired();
      // A dropped connection or a busy agent is retried; a few in a row is a real failure.
      if (++transient >= 5) throw e;
    }
    await sleep(o.intervalMs ?? 2000);
  }
  throw new DOMException('aborted', 'AbortError');
}
