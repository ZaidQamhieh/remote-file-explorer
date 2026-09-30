import type { Entry } from '../../core/api/models';

import { defaultSort, type EntryDensity, type SortField, type SortOrder } from '../../core/models/sort';

// The sort model lives in core so persisted settings can name it without depending on a feature.
export { defaultSort, type EntryDensity, type SortField, type SortOrder };

const ms = (s?: string) => (s ? Date.parse(s) || 0 : 0);

/** Directories first, then files; each group sorted by [sort]. Stable, and independent of which other entries exist. */
export function sortEntries(entries: readonly Entry[], sort: SortOrder): Entry[] {
  const cmp = (a: Entry, b: Entry): number => {
    let r: number;
    switch (sort.field) {
      case 'name': {
        const x = a.name.toLowerCase();
        const y = b.name.toLowerCase();
        r = x < y ? -1 : x > y ? 1 : 0;
        break;
      }
      case 'size':
        r = (a.size ?? 0) - (b.size ?? 0);
        break;
      case 'date':
        r = ms(a.modified) - ms(b.modified);
        break;
      case 'type': {
        const x = a.mimeType ?? '';
        const y = b.mimeType ?? '';
        r = x < y ? -1 : x > y ? 1 : 0;
        break;
      }
    }
    return sort.ascending ? r : -r;
  };
  const dirs = entries.filter((e) => e.isDir).sort(cmp);
  const files = entries.filter((e) => !e.isDir).sort(cmp);
  return [...dirs, ...files];
}
