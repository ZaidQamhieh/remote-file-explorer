import { createStore, type StoreApi } from 'zustand/vanilla';

import type { AgentClient } from '../../core/api/agentClient';
import type { BatchItemResult, BatchResult, Entry } from '../../core/api/models';
import type { ListingCache } from '../../core/storage/listingCache';
import { isEntryHidden, type VisibilityPrefs } from '../../core/visibility';
import { basenameOf, buildPathStackWithinRoot, joinRemotePath, renameDestination } from './paths';
import { sortEntries, type SortOrder } from './sort';

export type ExplorerState = {
  pathStack: string[];
  entries: Entry[];
  loading: boolean;
  loadingMore: boolean;
  error: string | null;
  selected: Set<string>;
  /** Showing cached data; a refresh is in progress or failed. */
  stale: boolean;
  /** The last live fetch failed and the data is from cache only. */
  offline: boolean;
  nextCursor: string | null;
  /** Session-only "show hidden items" override; not persisted. */
  showHidden: boolean;
};

export type ExplorerDeps = {
  hostId: string;
  rootPath: string;
  getClient: () => Promise<AgentClient>;
  cache: ListingCache;
  humanize: (e: unknown) => string;
};

export const currentPath = (s: ExplorerState) => s.pathStack[s.pathStack.length - 1];
export const atRoot = (s: ExplorerState) => s.pathStack.length === 1;
export const multiSelect = (s: ExplorerState) => s.selected.size > 0;

/** Sorted entries and the hidden-path set; the visible list is derived at display time so revealed hidden items keep their sorted position. */
export function deriveDisplay(s: Pick<ExplorerState, 'entries' | 'showHidden'>, sort: SortOrder, vis: VisibilityPrefs) {
  const sorted = sortEntries(s.entries, sort);
  const hidden = new Set(sorted.filter((e) => isEntryHidden(e, vis)).map((e) => e.path));
  return { sorted, hidden, display: s.showHidden ? sorted : sorted.filter((e) => !hidden.has(e.path)), hiddenCount: hidden.size };
}

/**
 * Explorer state machine ported from ExplorerNotifier. Every load takes a generation number so a
 * stale result of an overlapping same-path load (A -> B -> A) can never clobber the fresh one (PR-34).
 */
export function createExplorer(deps: ExplorerDeps): StoreApi<ExplorerState> & Explorer {
  const store = createStore<ExplorerState>(() => ({
    pathStack: [deps.rootPath],
    entries: [],
    loading: false,
    loadingMore: false,
    error: null,
    selected: new Set(),
    stale: false,
    offline: false,
    nextCursor: null,
    showHidden: false,
  }));
  let generation = 0;
  const get = store.getState;
  const set = (p: Partial<ExplorerState>) => store.setState(p);

  const load = async () => {
    const path = currentPath(get());
    const gen = ++generation;
    const cached = await deps.cache.get(deps.hostId, path);
    if (gen !== generation) return;
    if (cached) set({ entries: cached.entries, loading: false, stale: true, offline: false, error: null, selected: new Set(), nextCursor: null });
    else set({ loading: true, error: null, selected: new Set(), nextCursor: null });
    try {
      const client = await deps.getClient();
      if (gen !== generation) return;
      const listing = await client.list(path);
      if (gen !== generation) return;
      await deps.cache.put(deps.hostId, path, listing.entries);
      if (gen !== generation) return;
      set({ loading: false, entries: listing.entries, stale: false, offline: false, error: null, nextCursor: listing.nextCursor ?? null });
    } catch (e) {
      if (gen !== generation) return;
      if (cached) set({ loading: false, stale: true, offline: true });
      else set({ loading: false, error: deps.humanize(e) });
    }
  };

  const api: Explorer = {
    load,
    refresh: load,
    async loadMore() {
      const s = get();
      if (s.loading || s.loadingMore || s.nextCursor === null) return;
      const path = currentPath(s);
      const gen = ++generation;
      set({ loadingMore: true });
      try {
        const client = await deps.getClient();
        if (gen !== generation) return;
        const listing = await client.list(path, { cursor: s.nextCursor });
        if (gen !== generation) return;
        const merged = [...get().entries, ...listing.entries];
        await deps.cache.put(deps.hostId, path, merged);
        if (gen !== generation) return;
        set({ entries: merged, loadingMore: false, nextCursor: listing.nextCursor ?? null });
      } catch {
        if (gen === generation) set({ loadingMore: false });
      }
    },
    navigate(path) {
      set({ pathStack: [...get().pathStack, path] });
      void load();
    },
    popDirectory() {
      const s = get();
      if (atRoot(s)) return false;
      set({ pathStack: s.pathStack.slice(0, -1) });
      void load();
      return true;
    },
    navigateTo(index) {
      const s = get();
      if (index >= s.pathStack.length) return;
      set({ pathStack: s.pathStack.slice(0, index + 1) });
      void load();
    },
    jumpTo(path) {
      set({ pathStack: buildPathStackWithinRoot(deps.rootPath, path) });
      void load();
    },
    toggleShowHidden: () => set({ showHidden: !get().showHidden }),
    toggleSelect(path) {
      const sel = new Set(get().selected);
      if (!sel.delete(path)) sel.add(path);
      set({ selected: sel });
    },
    clearSelection: () => set({ selected: new Set() }),
    selectAll: (displayed) => set({ selected: new Set(displayed.map((e) => e.path)) }),
    invertSelection(displayed) {
      const all = new Set(displayed.map((e) => e.path));
      const cur = get().selected;
      set({ selected: new Set([...all].filter((p) => !cur.has(p))) });
    },
    async createFolder(name) {
      await (await deps.getClient()).createFolder(joinRemotePath(currentPath(get()), name));
      await load();
    },
    async createFile(name) {
      await (await deps.getClient()).createFile(joinRemotePath(currentPath(get()), name));
      await load();
    },
    async rename(oldPath, newName) {
      await (await deps.getClient()).rename(oldPath, renameDestination(oldPath, newName));
      await load();
    },
    async deleteSelected(o = {}) {
      const res = await (await deps.getClient()).delete([...get().selected], { permanent: o.permanent });
      await load();
      return res;
    },
    async moveSelected(destDir, o = {}) {
      const res = await (await deps.getClient()).move(o.sources ?? [...get().selected], destDir, o);
      await load();
      return res;
    },
    async copySelected(destDir, o = {}) {
      const res = await (await deps.getClient()).copy(o.sources ?? [...get().selected], destDir, o);
      await load();
      return res;
    },
    async compressSelected(dest, sources) {
      const entry = await (await deps.getClient()).compress(sources ?? [...get().selected], dest);
      await load();
      return entry;
    },
    async extractArchive(archive, destDir) {
      const entry = await (await deps.getClient()).extract(archive, destDir ?? currentPath(get()));
      await load();
      return entry;
    },
    async batchRename(renames) {
      const client = await deps.getClient();
      const results: BatchItemResult[] = [];
      const pending = new Map<string, string>(); // finalPath -> tempPath
      const fail = (path: string, e: unknown): BatchItemResult => ({ path, ok: false, errorCode: 'RENAME_FAILED', errorMessage: deps.humanize(e) });
      // Two sources landing on the same final name would strand the first at its temp name (PR-35): reject
      // every duplicate target up front, before any file is touched.
      const counts = new Map<string, number>();
      for (const r of renames) {
        const dst = renameDestination(r.path, r.newName);
        counts.set(dst, (counts.get(dst) ?? 0) + 1);
      }
      for (let i = 0; i < renames.length; i++) {
        const r = renames[i];
        const dst = renameDestination(r.path, r.newName);
        if (dst === r.path) {
          results.push({ path: r.path, ok: true });
          continue;
        }
        if ((counts.get(dst) ?? 0) > 1) {
          results.push({ path: r.path, ok: false, errorCode: 'DUPLICATE_TARGET', errorMessage: `Another selected item is also being renamed to "${r.newName}"` });
          continue;
        }
        const tmp = renameDestination(r.path, `.rfe-rn-${i}-${r.newName}`);
        try {
          await client.rename(r.path, tmp);
          pending.set(dst, tmp);
        } catch (e) {
          results.push(fail(r.path, e));
        }
      }
      for (const [finalPath, tmp] of pending) {
        try {
          await client.rename(tmp, finalPath);
          results.push({ path: finalPath, ok: true });
        } catch (e) {
          results.push(fail(tmp, e));
        }
      }
      await load();
      return { results, failed: results.filter((r) => !r.ok) };
    },
    /** Basenames of [sourcePaths] that already exist in [destDir]; pages the whole destination so late collisions are not missed. */
    async collidingBasenames(destDir, sourcePaths) {
      const client = await deps.getClient();
      const names = new Set<string>();
      let cursor: string | undefined;
      do {
        const l = await client.list(destDir, { cursor });
        for (const e of l.entries) names.add(e.name);
        cursor = l.nextCursor;
      } while (cursor);
      return new Set([...sourcePaths].map(basenameOf).filter((n) => names.has(n)));
    },
  };
  return Object.assign(store, api);
}

type CollisionOpts = { sources?: string[]; duplicate?: boolean; overwrite?: boolean };

export interface Explorer {
  load(): Promise<void>;
  refresh(): Promise<void>;
  loadMore(): Promise<void>;
  navigate(path: string): void;
  popDirectory(): boolean;
  navigateTo(index: number): void;
  jumpTo(path: string): void;
  toggleShowHidden(): void;
  toggleSelect(path: string): void;
  clearSelection(): void;
  selectAll(displayed: Entry[]): void;
  invertSelection(displayed: Entry[]): void;
  createFolder(name: string): Promise<void>;
  createFile(name: string): Promise<void>;
  rename(oldPath: string, newName: string): Promise<void>;
  deleteSelected(o?: { permanent?: boolean }): Promise<BatchResult>;
  moveSelected(destDir: string, o?: CollisionOpts): Promise<BatchResult>;
  copySelected(destDir: string, o?: CollisionOpts): Promise<BatchResult>;
  compressSelected(dest: string, sources?: string[]): Promise<Entry>;
  extractArchive(archive: string, destDir?: string): Promise<Entry>;
  batchRename(renames: { path: string; newName: string }[]): Promise<BatchResult>;
  collidingBasenames(destDir: string, sourcePaths: Iterable<string>): Promise<Set<string>>;
}
