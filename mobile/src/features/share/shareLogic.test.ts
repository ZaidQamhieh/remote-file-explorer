import { sharedFiles } from './shareLogic';

const f = (path: string, fileName = 'a.txt', size: number | null = 5) => ({ path, fileName, size });

test('keeps file URIs and adds the scheme to bare paths', () => {
  expect(sharedFiles([f('file:///c/a.txt'), f('/c/b.txt', 'b.txt', null)])).toEqual([
    { name: 'a.txt', uri: 'file:///c/a.txt', size: 5 },
    { name: 'b.txt', uri: 'file:///c/b.txt', size: undefined },
  ]);
});

test('drops content URIs and empty paths, tolerates null', () => {
  expect(sharedFiles([f('content://x/1'), f('')])).toEqual([]);
  expect(sharedFiles(null)).toEqual([]);
});

test('falls back to the decoded last path segment for a missing name', () => {
  expect(sharedFiles([f('file:///c/my%20doc.pdf', '')])[0].name).toBe('my doc.pdf');
});
