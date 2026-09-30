import { MemoryKeyValueStore } from '../../core/storage/hostStore';
import { albumsToScan, isAlreadyOnHost, assetIdFromTransferId, assetKey, backupRemotePath, backupTransferId, isFileStable, pendingIds, PhotoBackupStore, safeExtension, sanitizeSegment } from './photoBackupLogic';

test('builds date folders, with and without a device segment or root destination', () => {
  const d = new Date(2026, 2, 9);
  expect(backupRemotePath('/srv/photos/', d, 'a.jpg')).toBe('/srv/photos/2026/2026-03/a.jpg');
  expect(backupRemotePath('/srv/photos', d, 'a.jpg', 'Zaid')).toBe('/srv/photos/Zaid/2026/2026-03/a.jpg');
  expect(backupRemotePath('/', d, 'a.jpg')).toBe('/2026/2026-03/a.jpg');
  expect(backupRemotePath('D:\\x', d, 'a.jpg')).toBe('D:\\x/2026/2026-03/a.jpg');
});

test('pending ids keep order; album selection drops missing albums and empty means all', () => {
  expect(pendingIds(['1', '2', '3'], new Set(['2']))).toEqual(['1', '3']);
  expect(albumsToScan(['a', 'b'], new Set())).toEqual(['a', 'b']);
  expect(albumsToScan(['a', 'b'], new Set(['b', 'gone']))).toEqual(['b']);
});

test('a file counts as stable only when two reads agree and are non-zero', async () => {
  const wait = async () => {};
  expect(await isFileStable(() => 0, wait)).toBe(false);
  const grow = [10, 20];
  expect(await isFileStable(() => grow.shift() ?? 20, wait)).toBe(false);
  expect(await isFileStable(() => 10, wait)).toBe(true);
});

test('nickname and extension are made safe for a remote path', () => {
  expect(sanitizeSegment('  ../Zaid/phone: 1. ')).toBe('_Zaid_phone_ 1');
  expect(sanitizeSegment('...')).toBe('device');
  expect(sanitizeSegment('x'.repeat(100))).toHaveLength(64);
  expect(safeExtension('IMG_1.HEIC')).toBe('.HEIC');
  expect(safeExtension('../evil')).toBe('.jpg');
  expect(safeExtension('a.toolongext')).toBe('.jpg');
});

test('transfer ids round-trip an asset id and reject foreign ids', () => {
  expect(backupTransferId('123')).toBe('pb-123');
  expect(assetIdFromTransferId('pb-123')).toBe('123');
  expect(assetKey('content://media/external/images/media/20')).toBe('20');
  expect(backupTransferId('content://media/external/images/media/20')).toBe('pb-20');
  expect(assetKey('ph:/A-B/1')).toBe('1');
  expect(assetKey('a/b')).toBe('a_b');
  expect(assetIdFromTransferId('u1abc')).toBeNull();
  expect(assetIdFromTransferId('pb-1/2')).toBeNull();
});

test('prefs and the done record round-trip and read the Flutter encoding', async () => {
  const kv = new MemoryKeyValueStore();
  const store = new PhotoBackupStore(kv);
  expect(await store.load()).toEqual({ enabled: false, hostId: null, deviceName: null, wifiOnly: true, chargingOnly: false, albumIds: [] });
  await kv.set('rfe_photo_backup_enabled', 'true');
  await kv.set('rfe_photo_backup_host', '"h1"');
  await kv.set('rfe_photo_backup_done', '["1","2"]');
  const p = await store.load();
  expect(p).toMatchObject({ enabled: true, hostId: 'h1' });
  await store.save({ ...p, deviceName: 'Phone', albumIds: ['9'] });
  expect(await store.load()).toMatchObject({ deviceName: 'Phone', albumIds: ['9'] });
  await store.markDone(['2', '3']);
  expect([...(await store.doneIds())].sort()).toEqual(['1', '2', '3']);
  await store.clearDone();
  expect((await store.doneIds()).size).toBe(0);
});

test('a conflict on the host counts as already backed up, other failures do not', () => {
  expect(isAlreadyOnHost({ state: 'FAILED', error: 'CONFLICT' })).toBe(true);
  expect(isAlreadyOnHost({ state: 'FAILED', error: 'ERR_CONNECTION: x' })).toBe(false);
  expect(isAlreadyOnHost({ state: 'DONE', error: null })).toBe(false);
});
