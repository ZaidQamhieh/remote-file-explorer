import type { ShareIntentFile } from 'expo-share-intent';

import type { Picked } from '../transfers/uploadPlan';

/** Files another app shared with us as upload candidates; entries without a usable path are dropped. */
export function sharedFiles(files: readonly Pick<ShareIntentFile, 'path' | 'fileName' | 'size'>[] | null | undefined): Picked[] {
  const out: Picked[] = [];
  for (const f of files ?? []) {
    if (!f.path) continue;
    const uri = f.path.startsWith('/') ? `file://${f.path}` : f.path;
    if (!uri.startsWith('file://')) continue;
    const name = f.fileName || decodeURIComponent(uri.split('/').pop() ?? '') || 'file';
    out.push({ name, uri, size: f.size ?? undefined });
  }
  return out;
}

/** Expiry choices for a new share link; the agent refuses anything above 24 h, so 24 h is the last. */
export const SHARE_EXPIRY_PRESETS = [
  { seconds: 15 * 60, label: '15 minutes' },
  { seconds: 60 * 60, label: '1 hour' },
  { seconds: 24 * 60 * 60, label: '24 hours' },
] as const;
