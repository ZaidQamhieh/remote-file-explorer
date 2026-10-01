import { isTrustedApkUrl, isUpdateAvailable, parseRelease, percent, shouldSurfaceUpdate } from './updateLogic';

const good = { versionName: '2.1.0', versionCode: 82, size: 1000, url: 'https://github.com/ZaidQamhieh/remote-file-explorer/releases/download/v2.1.0/app.apk', sha256: 'A'.repeat(64) };

test('reads the manifest the release workflow publishes', () => {
  expect(parseRelease(good)).toEqual({ ...good, sha256: 'a'.repeat(64) });
});

test('a manifest without a usable SHA-256 is refused, so a download is never installed unchecked', () => {
  expect(parseRelease({ ...good, sha256: undefined })).toBeNull();
  expect(parseRelease({ ...good, sha256: 'short' })).toBeNull();
  expect(parseRelease({ ...good, sha256: 'g'.repeat(64) })).toBeNull();
  expect(parseRelease({ ...good, sha256: 5 })).toBeNull();
});

test('a manifest without a version code or with an APK address off GitHub is refused', () => {
  expect(parseRelease(null)).toBeNull();
  expect(parseRelease({ ...good, versionCode: 0 })).toBeNull();
  expect(parseRelease({ ...good, versionCode: '82' })).toBeNull();
  expect(parseRelease({ ...good, url: 'https://evil.example/app.apk' })).toBeNull();
  expect(parseRelease({ ...good, url: 'http://github.com/x.apk' })).toBeNull();
  expect(parseRelease({ ...good, url: undefined })).toBeNull();
});

test('trusted hosts are GitHub and its release storage, exactly', () => {
  expect(isTrustedApkUrl('https://objects.githubusercontent.com/x')).toBe(true);
  expect(isTrustedApkUrl('https://github.com/a/b')).toBe(true);
  expect(isTrustedApkUrl('https://notgithub.com/a')).toBe(false);
  expect(isTrustedApkUrl('https://github.com.evil.example/a')).toBe(false);
  expect(isTrustedApkUrl('nonsense')).toBe(false);
});

test('newer than installed, and the banner respects a dismissal', () => {
  const r = parseRelease(good)!;
  expect(isUpdateAvailable(81, r)).toBe(true);
  expect(isUpdateAvailable(82, r)).toBe(false);
  expect(isUpdateAvailable(81, null)).toBe(false);
  expect(shouldSurfaceUpdate(r, 81)).toBe(true);
  expect(shouldSurfaceUpdate(r, 82)).toBe(false);
  expect(shouldSurfaceUpdate(null, 0)).toBe(false);
});

test('percent clamps and tolerates an unknown total', () => {
  expect(percent(50, 200)).toBe(25);
  expect(percent(300, 200)).toBe(100);
  expect(percent(5, 0)).toBe(0);
});
