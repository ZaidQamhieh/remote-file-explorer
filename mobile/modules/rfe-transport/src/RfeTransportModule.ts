import { NativeModule, requireNativeModule } from 'expo';

import type { RfeResponse } from './RfeTransport.types';

type Events = { onTransferUpdate: (e: { record: string }) => void };

declare class RfeTransportModule extends NativeModule<Events> {
  /** Durable native downloads; each returns/emits JSON-encoded TransferRecord. */
  transferEnqueue(id: string, hostId: string, address: string, remotePath: string, destPath: string): Promise<string>;
  transferResume(id: string): Promise<void>;
  transferPause(id: string): Promise<void>;
  transferCancel(id: string): Promise<void>;
  transfersList(): Promise<string[]>;
  /** Cancellable pinned GET to a file; a non-2xx status is a normal result (404 no thumbnail, 429 busy + Retry-After). Rejects ERR_TOO_LARGE past maxBytes. */
  fetchToFile(id: string, url: string, headers: Record<string, string>, pin: string | null, destPath: string, timeoutMs?: number, maxBytes?: number): Promise<{ status: number; retryAfter: number | null; bytes: number }>;
  fetchCancel(id: string): Promise<void>;
  /** Broadcasts a WoL magic packet; false on a malformed MAC or send failure. */
  sendWakeOnLan(mac: string): Promise<boolean>;
  deviceId(): Promise<string | null>;
  /** mDNS search for `_rfe._tcp` agents (8 s); results are untrusted hints. */
  discoveryScan(): Promise<{ name: string; address: string; port: number }[]>;
  discoveryStop(): Promise<void>;
  /** Flutter shared_preferences (`flutter.` stripped); each value is JSON-encoded. */
  legacyPrefsReadAll(): Promise<Record<string, string>>;
  secureRead(key: string): Promise<string | null>;
  secureWrite(key: string, value: string): Promise<void>;
  secureDelete(key: string): Promise<void>;
  secureContains(key: string): Promise<boolean>;
  probeFingerprint(url: string, timeoutMs?: number): Promise<string>;
  request(
    url: string,
    method: string,
    headers: Record<string, string>,
    bodyText: string | null,
    pin: string | null,
    timeoutMs?: number,
  ): Promise<RfeResponse>;
  downloadToFile(
    url: string,
    headers: Record<string, string>,
    pin: string | null,
    destPath: string,
    offset?: number,
    timeoutMs?: number,
  ): Promise<number>;
}

export default requireNativeModule<RfeTransportModule>('RfeTransport');
