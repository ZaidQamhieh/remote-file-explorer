import type { Entry } from '../../core/api/models';
import { isSafeName, needsSync } from './syncLogic';

const remote = (o: Partial<Entry>): Entry => ({ name: 'a.txt', path: '/a.txt', isDir: false, isSymlink: false, size: 10, modified: '2026-09-30T10:00:00Z', ...o });
const t0 = Date.parse('2026-09-30T10:00:00Z');

test('a file is downloaded when missing, resized, or changed after the local copy', () => {
  expect(needsSync(remote({}), undefined)).toBe(true);
  expect(needsSync(remote({}), { size: 9, modified: t0 + 1000 })).toBe(true);
  expect(needsSync(remote({}), { size: 10, modified: t0 - 1000 })).toBe(true);
});

test('an up-to-date file is left alone, including when a time is missing', () => {
  expect(needsSync(remote({}), { size: 10, modified: t0 + 1000 })).toBe(false);
  expect(needsSync(remote({ modified: undefined }), { size: 10, modified: t0 })).toBe(false);
  expect(needsSync(remote({}), { size: 10, modified: null })).toBe(false);
  expect(needsSync(remote({ size: undefined }), { size: 0, modified: t0 + 1 })).toBe(false);
});

test('only plain names are accepted', () => {
  expect(isSafeName('a b.txt')).toBe(true);
  for (const bad of ['', '.', '..', 'a/b', 'a\\b', '../x']) expect(isSafeName(bad)).toBe(false);
});
