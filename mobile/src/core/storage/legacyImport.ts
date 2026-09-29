import { hostFromJson, hostToJson, type Host } from '../models/host';
import { SecureKeys, type SecureStore } from '../security/secureStore';
import { normalizeFingerprint } from '../api/pin';
import { HOSTS_KEY, type KeyValueStore } from './hostStore';

export const IMPORT_DONE_KEY = 'rn_legacy_import_v1';

export type ImportReport = {
  status: 'imported' | 'already-done' | 'nothing-to-import';
  hosts: number;
  /** Hosts that lack a usable secure-store pin or token and therefore need re-pairing. */
  needRepair: string[];
  skippedRecords: number;
};

/**
 * One-time import of the Flutter app's non-secret state. Secrets are NOT
 * copied: the RN app reads the same secure-storage entries in place (same
 * package, vendored plugin code), so tokens, pins and the Ed25519 identity keep
 * their original protection. Hosts whose pin/token can't be read are reported
 * for explicit re-pairing instead of being trusted from the metadata mirror.
 * Idempotent, and never overwrites hosts already created by the RN app.
 */
export async function importLegacyState(
  legacyPrefs: Record<string, string>,
  kv: KeyValueStore,
  secure: SecureStore,
): Promise<ImportReport> {
  if ((await kv.get(IMPORT_DONE_KEY)) !== null) return { status: 'already-done', hosts: 0, needRepair: [], skippedRecords: 0 };

  const raw = legacyPrefs[HOSTS_KEY];
  if (raw === undefined) {
    await kv.set(IMPORT_DONE_KEY, '1');
    return { status: 'nothing-to-import', hosts: 0, needRepair: [], skippedRecords: 0 };
  }

  let entries: unknown[] = [];
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) entries = parsed;
  } catch {
    // unreadable list: treated as no records
  }

  const hosts: Host[] = [];
  let skipped = 0;
  for (const e of entries) {
    let obj: unknown = e;
    if (typeof e === 'string') {
      try {
        obj = JSON.parse(e);
      } catch {
        obj = null;
      }
    }
    const h = hostFromJson(obj);
    if (h) hosts.push(h);
    else skipped++;
  }

  const needRepair: string[] = [];
  for (const h of hosts) {
    const pin = normalizeFingerprint(await secure.read(SecureKeys.fingerprint(h.id)).catch(() => null));
    const token = await secure.read(SecureKeys.token(h.id)).catch(() => null);
    if (pin === null || !token) needRepair.push(h.id);
  }

  const existingRaw = await kv.get(HOSTS_KEY);
  const existing: unknown[] = existingRaw ? (JSON.parse(existingRaw) as unknown[]) : [];
  const existingIds = new Set(existing.map((x) => (x as { id?: string }).id));
  const merged = [...existing, ...hosts.filter((h) => !existingIds.has(h.id)).map(hostToJson)];
  await kv.set(HOSTS_KEY, JSON.stringify(merged));
  // Non-secret per-host "last seen" timestamps (ms since epoch, stored by Flutter as an int).
  for (const [k, v] of Object.entries(legacyPrefs)) {
    if (k.startsWith('rfe_last_seen_') && /^[0-9]+$/.test(v) && (await kv.get(k)) === null) await kv.set(k, v);
  }
  await kv.set(IMPORT_DONE_KEY, '1');
  return { status: 'imported', hosts: hosts.length, needRepair, skippedRecords: skipped };
}
