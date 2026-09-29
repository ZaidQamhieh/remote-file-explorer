// Adapters from the local Expo module (modules/rfe-transport) to core interfaces.
import Rfe from '../../modules/rfe-transport/src/RfeTransportModule';
import type { Transport } from './api/agentClient';
import type { SecureStore } from './security/secureStore';

export const nativeTransport: Transport = {
  async request({ url, method, headers, bodyText, pin, timeoutMs }) {
    const r = await Rfe.request(url, method, headers, bodyText, pin, timeoutMs);
    return { status: r.status, headers: r.headers, bodyText: r.bodyText };
  },
};

export const nativeSecureStore: SecureStore = {
  read: (key) => Rfe.secureRead(key),
  write: (key, value) => Rfe.secureWrite(key, value),
  delete: (key) => Rfe.secureDelete(key),
};

export const readLegacyPrefs = () => Rfe.legacyPrefsReadAll();
export const probeFingerprint = (url: string, timeoutMs?: number) => Rfe.probeFingerprint(url, timeoutMs);
export const downloadToFile = Rfe.downloadToFile.bind(Rfe);

/** Cryptographically secure random bytes; refuses to fall back to Math.random. */
export function secureRandomBytes(n: number): Uint8Array {
  const c = (globalThis as { crypto?: { getRandomValues?: (a: Uint8Array) => Uint8Array } }).crypto;
  if (!c?.getRandomValues) throw new Error('secure random source unavailable');
  return c.getRandomValues(new Uint8Array(n));
}
