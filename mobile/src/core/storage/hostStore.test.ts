import { HostStore, MemoryKeyValueStore, HOSTS_KEY } from './hostStore';
import { MemorySecureStore, SecureKeys } from '../security/secureStore';

const PIN = 'cd'.repeat(32);
const host = { id: 'h1', label: 'PC', address: '10.0.0.2:8765' };

function make() {
  const kv = new MemoryKeyValueStore();
  const secure = new MemorySecureStore();
  return { kv, secure, store: new HostStore(kv, secure) };
}

describe('HostStore.commitPairing', () => {
  it('stores pin and token in secure storage and only the mirror in metadata', async () => {
    const { store, secure } = make();
    await store.commitPairing(host, { token: 'tok', fingerprint: PIN.toUpperCase() });
    expect(await store.getPin('h1')).toBe(PIN);
    expect(await store.getToken('h1')).toBe('tok');
    expect(secure.data.get(SecureKeys.fingerprint('h1'))).toBe(PIN);
    expect((await store.listHosts())[0].certFingerprint).toBe(PIN);
  });

  it('refuses a missing or malformed pin and writes nothing', async () => {
    const { store, secure, kv } = make();
    await expect(store.commitPairing(host, { token: 't', fingerprint: 'nope' })).rejects.toThrow();
    expect(secure.data.size).toBe(0);
    expect(kv.data.size).toBe(0);
  });

  it('rolls back secrets if the host record cannot be written', async () => {
    const { store, secure, kv } = make();
    kv.set = async () => {
      throw new Error('disk full');
    };
    await expect(store.commitPairing(host, { token: 't', fingerprint: PIN })).rejects.toThrow('disk full');
    expect(secure.data.size).toBe(0);
  });

  it('rolls back when the token write fails, leaving no orphan pin', async () => {
    const { store, secure } = make();
    const write = secure.write.bind(secure);
    secure.write = async (k, v) => {
      if (k.startsWith('rfe_token_')) throw new Error('keystore');
      return write(k, v);
    };
    await expect(store.commitPairing(host, { token: 't', fingerprint: PIN })).rejects.toThrow('keystore');
    expect(secure.data.size).toBe(0);
    expect(await store.listHosts()).toEqual([]);
  });
});

describe('HostStore list handling', () => {
  it('skips corrupt records, accepts Flutter string-encoded entries, and moves touched host first', async () => {
    const { store, kv } = make();
    await kv.set(HOSTS_KEY, JSON.stringify([JSON.stringify(host), 'not json', { id: 'x' }, { id: 'h2', label: 'B', address: 'b:1' }]));
    expect((await store.listHosts()).map((h) => h.id)).toEqual(['h1', 'h2']);
    await store.touchHost('h2');
    expect((await store.listHosts()).map((h) => h.id)).toEqual(['h2', 'h1']);
  });

  it('removeHost clears its secrets', async () => {
    const { store, secure } = make();
    await store.commitPairing(host, { token: 't', fingerprint: PIN });
    await store.removeHost('h1');
    expect(secure.data.size).toBe(0);
    expect(await store.listHosts()).toEqual([]);
  });
});
