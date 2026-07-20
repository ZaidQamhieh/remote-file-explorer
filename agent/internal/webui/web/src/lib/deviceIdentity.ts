// Ed25519 device identity for this browser tab, matching the pairing/login/
// register proof-of-possession scheme documented in protocol/openapi.yaml
// (PairRequest/RegisterRequest/LoginRequest: devicePublicKey + nonce +
// signature). The keypair is generated once and its raw bytes persisted in
// localStorage so a returning browser reuses the same device identity
// instead of re-pairing every reload.
//
// ponytail: keys are extractable and stored as base64 in localStorage,
// same trust boundary as the bearer token already stored there (LAN-only
// tool, no hostile-JS threat model assumed). A hardened build would keep
// the private key as a non-extractable CryptoKey in IndexedDB instead.

const PRIV_KEY = 'rfe_device_privkey';
const PUB_KEY = 'rfe_device_pubkey';

function toBase64(buf: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buf)));
}
function fromBase64(b64: string): ArrayBuffer {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)).buffer;
}

async function generateAndStore(): Promise<CryptoKeyPair> {
  const pair = (await crypto.subtle.generateKey(
    { name: 'Ed25519' },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
  const priv = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  const pub = await crypto.subtle.exportKey('raw', pair.publicKey);
  localStorage.setItem(PRIV_KEY, toBase64(priv));
  localStorage.setItem(PUB_KEY, toBase64(pub));
  return pair;
}

let cached: CryptoKeyPair | null = null;

/** The device's persistent Ed25519 keypair, creating one on first use. */
export async function getDeviceKeyPair(): Promise<CryptoKeyPair> {
  if (cached) return cached;
  const privB64 = localStorage.getItem(PRIV_KEY);
  const pubB64 = localStorage.getItem(PUB_KEY);
  if (privB64 && pubB64) {
    const privateKey = await crypto.subtle.importKey(
      'pkcs8',
      fromBase64(privB64),
      { name: 'Ed25519' },
      true,
      ['sign'],
    );
    const publicKey = await crypto.subtle.importKey(
      'raw',
      fromBase64(pubB64),
      { name: 'Ed25519' },
      true,
      ['verify'],
    );
    cached = { privateKey, publicKey };
    return cached;
  }
  cached = await generateAndStore();
  return cached;
}

/** devicePublicKey field: standard base64 of the 32 raw public-key bytes. */
export async function getDevicePublicKeyB64(): Promise<string> {
  const { publicKey } = await getDeviceKeyPair();
  const raw = await crypto.subtle.exportKey('raw', publicKey);
  return toBase64(raw);
}

/** signature field: nonce signed with the device's private key, base64. */
export async function signNonce(nonce: string): Promise<string> {
  const { privateKey } = await getDeviceKeyPair();
  const sig = await crypto.subtle.sign(
    'Ed25519',
    privateKey,
    new TextEncoder().encode(nonce),
  );
  return toBase64(sig);
}
