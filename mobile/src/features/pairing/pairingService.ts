import { AgentApiError, AgentClient, type Transport } from '../../core/api/agentClient';
import type { PairResponse } from '../../core/api/models';
import { CertPinMismatch, MissingCertPin, normalizeFingerprint } from '../../core/api/pin';
import type { Host } from '../../core/models/host';
import type { DeviceIdentity } from '../../core/security/deviceIdentity';
import type { HostStore } from '../../core/storage/hostStore';

export type PairingDeps = {
  transport: Transport;
  identity: DeviceIdentity;
  store: HostStore;
  /** Android ID; lets a re-pair of the same phone reuse its device row. */
  deviceId: () => Promise<string | null>;
  deviceLabel?: string;
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
  if (e instanceof CertPinMismatch || e instanceof MissingCertPin) return e.message;
  if (e instanceof AgentApiError) return e.message;
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
