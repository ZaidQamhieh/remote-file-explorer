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
