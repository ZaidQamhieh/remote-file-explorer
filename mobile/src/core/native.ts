// Adapters from the local Expo module (modules/rfe-transport) to core interfaces.
import { getRandomBytes } from 'expo-crypto';
import Rfe from '../../modules/rfe-transport/src/RfeTransportModule';
import type { Transport } from './api/agentClient';
import { normalizeDiscovered } from './discovery';
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
export type TransferState = 'QUEUED' | 'RUNNING' | 'PAUSED' | 'DONE' | 'FAILED' | 'CANCELLED';
export type TransferRecord = {
  id: string;
  hostId: string;
  address: string;
  remotePath: string;
  destPath: string;
  state: TransferState;
  received: number;
  total: number;
  error: string | null;
};

const parseRecord = (s: string) => JSON.parse(s) as TransferRecord;

/** Durable native downloads (foreground service, journal, Range resume). */
export const transfers = {
  enqueue: async (id: string, hostId: string, address: string, remotePath: string, destPath: string) =>
    parseRecord(await Rfe.transferEnqueue(id, hostId, address, remotePath, destPath)),
  resume: (id: string) => Rfe.transferResume(id),
  pause: (id: string) => Rfe.transferPause(id),
  cancel: (id: string) => Rfe.transferCancel(id),
  list: async () => (await Rfe.transfersList()).map(parseRecord),
  subscribe(cb: (r: TransferRecord) => void) {
    const sub = Rfe.addListener('onTransferUpdate', (e) => cb(parseRecord(e.record)));
    return () => sub.remove();
  },
};

export const downloadToFile = Rfe.downloadToFile.bind(Rfe);

/** Cryptographically secure random bytes from the OS CSPRNG (expo-crypto); never Math.random. */
export function secureRandomBytes(n: number): Uint8Array {
  return getRandomBytes(n);
}

export const deviceIdNative = async () => (await Rfe.deviceId()) ?? null;

export const scanLan = async () => normalizeDiscovered(await Rfe.discoveryScan());
export const stopLanScan = () => Rfe.discoveryStop();

export const sendWakeOnLan = (mac: string) => Rfe.sendWakeOnLan(mac);

export const fetchToFileNative = (id: string, url: string, headers: Record<string, string>, pin: string | null, destPath: string, timeoutMs?: number, maxBytes?: number) =>
  Rfe.fetchToFile(id, url, headers, pin, destPath, timeoutMs, maxBytes);
export const fetchCancelNative = (id: string) => Rfe.fetchCancel(id);
export const pdf = {
  pageCount: (path: string) => Rfe.pdfPageCount(path),
  renderPage: (path: string, index: number, widthPx: number, outPath: string) => Rfe.pdfRenderPage(path, index, widthPx, outPath),
  close: () => Rfe.pdfClose(),
};
