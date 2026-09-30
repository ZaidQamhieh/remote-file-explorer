import type { Entry } from '../../core/api/models';

/**
 * Whether [remote] must be downloaded again to keep the local copy current: missing, a different size, or changed on
 * the computer after the local file was written (a same-size edit still re-syncs).
 */
export function needsSync(remote: Entry, local: { size: number; modified: number | null } | undefined): boolean {
  if (!local) return true;
  if (local.size !== (remote.size ?? 0)) return true;
  const remoteMs = remote.modified ? Date.parse(remote.modified) : NaN;
  if (!Number.isNaN(remoteMs) && local.modified !== null) return remoteMs > local.modified;
  return false;
}

/** A remote name that is safe to create locally: one plain path segment. */
export const isSafeName = (name: string) => name !== '' && name !== '.' && name !== '..' && !/[\\/\u0000]/.test(name);
