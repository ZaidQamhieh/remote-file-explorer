import type { AgentClient } from '../../core/api/agentClient';
import type { Entry } from '../../core/api/models';
import { ListingCache, MemoryListingBackend } from '../../core/storage/listingCache';
import { defaultVisibility } from '../../core/visibility';
import { createExplorer, currentPath, deriveDisplay } from './explorerStore';

const e = (name: string, dir = false): Entry => ({ name, path: `/r/${name}`, isDir: dir, isSymlink: false });
const tick = () => new Promise((r) => setTimeout(r, 0));

function setup(client: Partial<Record<keyof AgentClient, jest.Mock>>) {
  const cache = new ListingCache(new MemoryListingBackend(), 3);
  const ex = createExplorer({ hostId: 'h', rootPath: '/r', getClient: async () => client as unknown as AgentClient, cache, humanize: (x) => (x as Error).message });
  return { ex, cache };
}

describe('load / cache / offline', () => {
  it('loads, caches, and falls back to cache with offline=true when the host is down', async () => {
    const list = jest.fn().mockResolvedValueOnce({ path: '/r', entries: [e('a')], nextCursor: 'c' }).mockRejectedValueOnce(new Error('down'));
    const { ex } = setup({ list });
    await ex.load();
    expect(ex.getState()).toMatchObject({ loading: false, stale: false, offline: false, nextCursor: 'c' });
    expect(ex.getState().entries.map((x) => x.name)).toEqual(['a']);
    await ex.load();
    expect(ex.getState()).toMatchObject({ offline: true, stale: true, error: null });
    expect(ex.getState().entries).toHaveLength(1);
  });

  it('reports the error when there is no cache', async () => {
    const { ex } = setup({ list: jest.fn().mockRejectedValue(new Error('boom')) });
    await ex.load();
    expect(ex.getState()).toMatchObject({ error: 'boom', loading: false });
  });

  it('a stale overlapping load never clobbers the newer result (ABA)', async () => {
    let releaseFirst!: (v: unknown) => void;
    const list = jest
      .fn()
      .mockImplementationOnce(() => new Promise((r) => (releaseFirst = r)))
      .mockResolvedValueOnce({ path: '/r', entries: [e('fresh')] });
    const { ex } = setup({ list });
    const first = ex.load();
    await tick();
    const second = ex.load();
    await second;
    releaseFirst({ path: '/r', entries: [e('stale')] });
    await first;
    expect(ex.getState().entries.map((x) => x.name)).toEqual(['fresh']);
  });

  it('paginates and appends, caching the merged list', async () => {
    const list = jest
      .fn()
      .mockResolvedValueOnce({ path: '/r', entries: [e('a')], nextCursor: 'c1' })
      .mockResolvedValueOnce({ path: '/r', entries: [e('b')] });
    const { ex, cache } = setup({ list });
    await ex.load();
    await ex.loadMore();
    expect(list).toHaveBeenLastCalledWith('/r', { cursor: 'c1' });
    expect(ex.getState().entries.map((x) => x.name)).toEqual(['a', 'b']);
    expect(ex.getState().nextCursor).toBeNull();
    expect((await cache.get('h', '/r'))!.entries).toHaveLength(2);
    await ex.loadMore(); // no cursor: no-op
    expect(list).toHaveBeenCalledTimes(2);
  });
});

describe('navigation and selection', () => {
  it('navigates, pops, jumps within the root, and clears selection on every load', async () => {
    const list = jest.fn().mockResolvedValue({ path: '/r', entries: [e('a')] });
    const { ex } = setup({ list });
    await ex.load();
    ex.toggleSelect('/r/a');
    expect(ex.getState().selected.has('/r/a')).toBe(true);
    ex.navigate('/r/a');
    await tick();
    expect(currentPath(ex.getState())).toBe('/r/a');
    expect(ex.getState().selected.size).toBe(0);
    expect(ex.popDirectory()).toBe(true);
    expect(ex.popDirectory()).toBe(false);
    ex.jumpTo('/r/x/y');
    expect(ex.getState().pathStack).toEqual(['/r', '/r/x', '/r/x/y']);
    ex.jumpTo('/etc');
    expect(ex.getState().pathStack).toEqual(['/r']);
  });

  it('select all / invert operate on displayed (visible) entries only', async () => {
    const list = jest.fn().mockResolvedValue({ path: '/r', entries: [e('a'), e('.hidden'), e('b')] });
    const { ex } = setup({ list });
    await ex.load();
    const { display, hiddenCount } = deriveDisplay(ex.getState(), { field: 'name', ascending: true }, defaultVisibility());
    expect(hiddenCount).toBe(1);
    ex.selectAll(display);
    expect([...ex.getState().selected].sort()).toEqual(['/r/a', '/r/b']);
    ex.toggleSelect('/r/a');
    ex.invertSelection(display);
    expect([...ex.getState().selected]).toEqual(['/r/a']);
    ex.toggleShowHidden();
    expect(deriveDisplay(ex.getState(), { field: 'name', ascending: true }, defaultVisibility()).display).toHaveLength(3);
  });
});

describe('operations', () => {
  it('batchRename does two-phase renames and rejects duplicate targets before touching anything', async () => {
    const rename = jest.fn().mockResolvedValue({});
    const { ex } = setup({ list: jest.fn().mockResolvedValue({ path: '/r', entries: [] }), rename });
    const res = await ex.batchRename([
      { path: '/r/a', newName: 'b' },
      { path: '/r/b', newName: 'a' },
      { path: '/r/c', newName: 'dup' },
      { path: '/r/d', newName: 'dup' },
      { path: '/r/e', newName: 'e' },
    ]);
    expect(res.failed.map((f) => f.errorCode)).toEqual(['DUPLICATE_TARGET', 'DUPLICATE_TARGET']);
    const calls = rename.mock.calls.map((c) => c.join('>'));
    expect(calls).toEqual(['/r/a>/r/.rfe-rn-0-b', '/r/b>/r/.rfe-rn-1-a', '/r/.rfe-rn-0-b>/r/b', '/r/.rfe-rn-1-a>/r/a']);
    expect(res.results.find((r) => r.path === '/r/e')!.ok).toBe(true);
  });

  it('collidingBasenames pages the whole destination', async () => {
    const list = jest
      .fn()
      .mockResolvedValueOnce({ path: '/d', entries: [e('x')], nextCursor: 'n' })
      .mockResolvedValueOnce({ path: '/d', entries: [e('y')] });
    const { ex } = setup({ list });
    expect([...(await ex.collidingBasenames('/d', ['/s/y', '/s/z']))]).toEqual(['y']);
  });

  it('copy/move/delete pass the selection and options to the client and refresh', async () => {
    const res = { results: [], failed: [] };
    const client = { list: jest.fn().mockResolvedValue({ path: '/r', entries: [] }), copy: jest.fn().mockResolvedValue(res), move: jest.fn().mockResolvedValue(res), delete: jest.fn().mockResolvedValue(res), createFolder: jest.fn().mockResolvedValue({}) };
    const { ex } = setup(client);
    ex.toggleSelect('/r/a');
    await ex.copySelected('/d', { duplicate: true });
    await ex.moveSelected('/d', { sources: ['/r/z'], overwrite: true });
    ex.toggleSelect('/r/a');
    ex.toggleSelect('/r/b');
    await ex.deleteSelected({ permanent: true });
    await ex.createFolder('new');
    expect(client.copy).toHaveBeenCalledWith(['/r/a'], '/d', { duplicate: true });
    expect(client.move).toHaveBeenCalledWith(['/r/z'], '/d', { sources: ['/r/z'], overwrite: true });
    expect(client.delete).toHaveBeenCalledWith(['/r/a', '/r/b'], { permanent: true });
    expect(client.createFolder).toHaveBeenCalledWith('/r/new');
  });
});

describe('listing cache', () => {
  it('evicts the oldest non-pinned listing beyond capacity and serialises writes', async () => {
    let t = 0;
    const cache = new ListingCache(new MemoryListingBackend(), 2, () => ++t);
    cache.setPinned('h:/a', true);
    await Promise.all([cache.put('h', '/a', []), cache.put('h', '/b', []), cache.put('h', '/c', [])]);
    expect(await cache.get('h', '/a')).not.toBeNull();
    expect(await cache.get('h', '/b')).toBeNull();
    expect(await cache.get('h', '/c')).not.toBeNull();
    await cache.evictHost('h');
    expect(await cache.get('h', '/a')).toBeNull();
  });
});
