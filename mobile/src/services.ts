import { openDatabaseSync } from 'expo-sqlite';

import { AgentClient } from './core/api/agentClient';
import { DeviceIdentity } from './core/security/deviceIdentity';
import { HostStore, type KeyValueStore } from './core/storage/hostStore';
import { importLegacyState, type ImportReport } from './core/storage/legacyImport';
import { nativeSecureStore, nativeTransport, readLegacyPrefs, secureRandomBytes } from './core/native';
import type { Host } from './core/models/host';

// Non-secret key/value storage in SQLite. Secrets never touch it.
const db = openDatabaseSync('rfe.db');
db.execSync('CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY NOT NULL, v TEXT NOT NULL)');

const kv: KeyValueStore = {
  async get(key) {
    return db.getFirstSync<{ v: string }>('SELECT v FROM kv WHERE k = ?', key)?.v ?? null;
  },
  async set(key, value) {
    db.runSync('INSERT OR REPLACE INTO kv (k, v) VALUES (?, ?)', key, value);
  },
  async remove(key) {
    db.runSync('DELETE FROM kv WHERE k = ?', key);
  },
};

export const hostStore = new HostStore(kv, nativeSecureStore);
export const identity = new DeviceIdentity(nativeSecureStore, secureRandomBytes);

let imported: Promise<ImportReport> | undefined;
/** Runs the one-time Flutter state import (idempotent). */
export function ensureLegacyImport(): Promise<ImportReport> {
  imported ??= readLegacyPrefs().then((prefs) => importLegacyState(prefs, kv, nativeSecureStore));
  return imported;
}

/** Builds a client for a paired host using only its secure-store pin and token. */
export async function clientForHost(host: Host, probeLanFirst = false, timeoutMs?: number): Promise<AgentClient> {
  const [pin, token] = await Promise.all([hostStore.getPin(host.id), hostStore.getToken(host.id)]);
  return new AgentClient(host, {
    transport: nativeTransport,
    deviceToken: token ?? undefined,
    pinnedFingerprint: pin,
    probeLanFirst,
    timeoutMs,
  });
}

export function unpinnedClient(host: Host): AgentClient {
  return new AgentClient(host, { transport: nativeTransport });
}

import { nativeTransport as _transport } from './core/native';
import { deviceIdNative } from './core/native';
import type { PairingDeps } from './features/pairing/pairingService';

export const pairingDeps: PairingDeps = {
  transport: _transport,
  identity,
  store: hostStore,
  deviceId: deviceIdNative,
};
