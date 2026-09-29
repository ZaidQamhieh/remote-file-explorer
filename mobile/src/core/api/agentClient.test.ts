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
});
