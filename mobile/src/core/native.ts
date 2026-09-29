// Adapters from the local Expo module (modules/rfe-transport) to core interfaces.
import { getRandomBytes } from 'expo-crypto';
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

/** Cryptographically secure random bytes from the OS CSPRNG (expo-crypto); never Math.random. */
export function secureRandomBytes(n: number): Uint8Array {
  return getRandomBytes(n);
}
