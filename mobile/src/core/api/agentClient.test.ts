import { AgentClient, ERR_CERT_PIN_MISMATCH, ERR_CONNECTION, type Transport } from './agentClient';
import { CertPinMismatch, MissingCertPin } from './pin';
import type { Host } from '../models/host';

const PIN = 'ab'.repeat(32);
const host: Host = { id: 'h1', label: 'PC', address: '192.168.1.2:8765', tailscaleAddress: '100.1.2.3:8765' };

const ok = (body: unknown) => ({ status: 200, headers: {}, bodyText: JSON.stringify(body) });
const coded = (code: string) => Object.assign(new Error(code), { code });

function fake(handler: (url: string, method: string) => unknown) {
  const calls: { url: string; method: string; headers: Record<string, string>; pin: string | null }[] = [];
  const transport: Transport = {
    async request(a) {
      calls.push({ url: a.url, method: a.method, headers: a.headers, pin: a.pin });
      const r = handler(a.url, a.method);
      if (r instanceof Error) throw r;
      return r as never;
    },
  };
  return { transport, calls };
}

describe('AgentClient pin policy', () => {
  it('refuses a token without a pin at construction', () => {
    const { transport } = fake(() => ok({}));
    expect(() => new AgentClient(host, { transport, deviceToken: 't' })).toThrow(MissingCertPin);
  });

  it('refuses malformed pins', () => {
    const { transport } = fake(() => ok({}));
    expect(() => new AgentClient(host, { transport, pinnedFingerprint: 'zz' })).toThrow(MissingCertPin);
  });

  it('unpinned client may only call health and challenge, and never sends credentials', async () => {
    const { transport, calls } = fake(() => ok({ status: 'ok', nonce: 'n' }));
    const c = new AgentClient(host, { transport });
    await c.health();
    await c.challenge();
    await expect(c.drives()).rejects.toBeInstanceOf(MissingCertPin);
    expect(calls).toHaveLength(2);
    expect(calls.every((x) => x.headers.Authorization === undefined && x.pin === null)).toBe(true);
  });

  it('sends bearer only when pinned and passes the normalized pin to the transport', async () => {
    const { transport, calls } = fake(() => ok([]));
    const c = new AgentClient(host, { transport, deviceToken: 'tok', pinnedFingerprint: PIN.toUpperCase() });
    await c.drives();
    expect(calls[0].headers.Authorization).toBe('Bearer tok');
    expect(calls[0].pin).toBe(PIN);
    expect(calls[0].url).toBe('https://192.168.1.2:8765/v1/system/drives');
  });

  it('surfaces a pin mismatch and never tries another route', async () => {
    const { transport, calls } = fake(() => coded(ERR_CERT_PIN_MISMATCH));
    const c = new AgentClient(host, { transport, deviceToken: 't', pinnedFingerprint: PIN });
    await expect(c.list('/')).rejects.toBeInstanceOf(CertPinMismatch);
    expect(calls).toHaveLength(1);
  });
});

describe('AgentClient route fallback', () => {
  it('falls back to Tailscale for GET on connectivity failure and remembers it', async () => {
    const { transport, calls } = fake((url) => (url.includes('192.168') ? coded(ERR_CONNECTION) : ok([])));
    const c = new AgentClient(host, { transport, deviceToken: 't', pinnedFingerprint: PIN, probeLanFirst: true });
    await c.drives();
    expect(calls.map((x) => x.url.split('/')[2])).toEqual(['192.168.1.2:8765', '100.1.2.3:8765']);
    expect(c.activeRoute).toBe('tailscale');
    const later = new AgentClient(host, { transport, deviceToken: 't', pinnedFingerprint: PIN });
    expect(later.activeAddress).toBe('100.1.2.3:8765');
  });

  it('does not replay POST on another route', async () => {
    const { transport, calls } = fake(() => coded(ERR_CONNECTION));
    const c = new AgentClient(host, { transport, pinnedFingerprint: PIN, probeLanFirst: true });
    await expect(
      c.pair({ pairingCode: '1', deviceLabel: 'p', devicePublicKey: 'k', nonce: 'n', signature: 's' }),
    ).rejects.toMatchObject({ code: 'CONNECTION' });
    expect(calls).toHaveLength(1);
  });

  it('stops fallback when a pin mismatch appears on the second route', async () => {
    const { transport, calls } = fake((url) =>
      url.includes('192.168') ? coded(ERR_CONNECTION) : coded(ERR_CERT_PIN_MISMATCH),
    );
    const c = new AgentClient(host, { transport, deviceToken: 't', pinnedFingerprint: PIN, probeLanFirst: true });
    await expect(c.drives()).rejects.toBeInstanceOf(CertPinMismatch);
    expect(calls).toHaveLength(2);
  });
});

describe('AgentClient responses', () => {
  it('maps API errors and parses listings', async () => {
    const { transport } = fake((url) =>
      url.includes('/fs?')
        ? ok({ path: '/', entries: [{ name: 'a', path: '/a', isDir: true }], nextCursor: 'c' })
        : { status: 403, headers: {}, bodyText: JSON.stringify({ code: 'READ_ONLY', message: 'nope' }) },
    );
    const c = new AgentClient(host, { transport, deviceToken: 't', pinnedFingerprint: PIN });
    const l = await c.list('/');
    expect(l.entries[0]).toMatchObject({ name: 'a', isDir: true, isSymlink: false });
    expect(l.nextCursor).toBe('c');
    await expect(c.drives()).rejects.toMatchObject({ statusCode: 403, code: 'READ_ONLY' });
  });

  it('reads roots and access policy from /settings', async () => {
    const { transport, calls } = fake(() => ok({ roots: ['/srv/a', 7], accessDenied: true, effectiveScope: 'device', readOnly: true }));
    const c = new AgentClient(host, { transport, deviceToken: 't', pinnedFingerprint: PIN });
    expect(await c.status()).toMatchObject({ roots: ['/srv/a'], accessDenied: true, effectiveScope: 'device', readOnly: true });
    expect(calls[0].url).toMatch(/\/v1\/settings$/);
  });
});

describe('AgentClient putContent', () => {
  it('PUTs raw text with baseModified and maps STALE_WRITE to a coded error', async () => {
    const seen: { url: string; body: string | null; ct?: string }[] = [];
    let status = 200;
    const transport: Transport = {
      async request(a) {
        seen.push({ url: a.url, body: a.bodyText, ct: a.headers['Content-Type'] });
        return status === 200
          ? { status, headers: {}, bodyText: JSON.stringify({ name: 'a.txt', path: '/a.txt', isDir: false, modified: 'm2' }) }
          : { status, headers: {}, bodyText: JSON.stringify({ code: 'STALE_WRITE', message: 'changed' }) };
      },
    };
    const client = new AgentClient(host, { transport, deviceToken: 't', pinnedFingerprint: PIN });
    const e = await client.putContent('/a.txt', '{"k":1}\n', 'm1');
    expect(e.modified).toBe('m2');
    expect({ ...seen[0], url: seen[0].url.split('/v1')[1] }).toEqual({ url: '/content?path=%2Fa.txt&baseModified=m1', body: '{"k":1}\n', ct: 'application/octet-stream' });
    status = 409;
    await expect(client.putContent('/a.txt', 'x')).rejects.toMatchObject({ statusCode: 409, code: 'STALE_WRITE' });
    expect(seen[1].url.split('/v1')[1]).toBe('/content?path=%2Fa.txt');
  });
});

describe('AgentClient filesystem operations', () => {
  const pinned = (h: (url: string, method: string, body: unknown) => unknown) => {
    const calls: { url: string; method: string; body: unknown }[] = [];
    const transport: Transport = {
      async request(a) {
        const body = a.bodyText ? JSON.parse(a.bodyText) : null;
        calls.push({ url: a.url, method: a.method, body });
        return { status: 200, headers: {}, bodyText: JSON.stringify(h(a.url, a.method, body)) };
      },
    };
    return { client: new AgentClient(host, { transport, deviceToken: 't', pinnedFingerprint: PIN }), calls };
  };

  it('uses the exact verbs, paths and bodies of the Flutter client', async () => {
    const { client, calls } = pinned(() => ({ name: 'n', path: '/p', isDir: false, results: [], items: [] }));
    await client.createFolder('/a/b');
    await client.createFile('/a/f');
    await client.rename('/a/f', '/a/g');
    await client.chmod('/a/g', '0755');
    await client.copy(['/x'], '/d', { duplicate: true });
    await client.move(['/x'], '/d', { overwrite: true });
    await client.delete(['/x']);
    await client.delete(['/x'], { permanent: true });
    await client.restoreTrash(['1']);
    await client.emptyTrash();
    await client.emptyTrash(['1']);
    await client.compress(['/a'], '/a.zip');
    await client.extract('/a.zip', '/out');
    const shape = calls.map((c) => `${c.method} ${c.url.split('/v1')[1]} ${JSON.stringify(c.body)}`);
    expect(shape).toEqual([
      'POST /fs/folder {"path":"/a/b"}',
      'POST /fs/file {"path":"/a/f"}',
      'PATCH /fs/rename {"src":"/a/f","dst":"/a/g"}',
      'POST /fs/chmod {"path":"/a/g","mode":"0755"}',
      'POST /fs/copy {"sources":["/x"],"destDir":"/d","duplicate":true,"overwrite":false}',
      'POST /fs/move {"sources":["/x"],"destDir":"/d","duplicate":false,"overwrite":true}',
      'DELETE /fs {"paths":["/x"]}',
      'DELETE /fs?permanent=true {"paths":["/x"]}',
      'POST /trash/restore {"ids":["1"]}',
      'DELETE /trash null',
      'DELETE /trash {"ids":["1"]}',
      'POST /fs/compress {"sources":["/a"],"dest":"/a.zip"}',
      'POST /fs/extract {"archive":"/a.zip","destDir":"/out"}',
    ]);
  });

  it('parses batch results with per-item errors and lists trash/archives/checksums', async () => {
    const { client } = pinned((url) =>
      url.includes('/fs/copy')
        ? { results: [{ path: '/a', ok: true }, { path: '/b', ok: false, error: { code: 'CONFLICT', message: 'exists' } }] }
        : url.includes('/trash')
          ? { items: [{ id: '1', name: 'x', originalPath: '/x', isDir: true }] }
          : url.includes('/fs/archive')
            ? { entries: [{ path: 'a/b', size: 3, isDir: false }] }
            : { checksums: [{ path: '/a', hash: 'abc' }, { path: '/b', hash: '' }] },
    );
    const r = await client.copy(['/a', '/b'], '/d');
    expect(r.failed).toEqual([{ path: '/b', ok: false, errorCode: 'CONFLICT', errorMessage: 'exists' }]);
    expect((await client.listTrash())[0]).toMatchObject({ id: '1', isDir: true });
    expect((await client.archiveList('/a.zip'))[0]).toMatchObject({ path: 'a/b', size: 3 });
    expect(await client.batchChecksums(['/a', '/b'])).toEqual({ '/a': 'abc' });
  });
});
