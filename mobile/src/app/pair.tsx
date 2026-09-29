import { useLocalSearchParams, useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, Text, TextInput } from 'react-native';

import { AgentApiError } from '../core/api/agentClient';
import { CertPinMismatch, MissingCertPin, normalizeFingerprint } from '../core/api/pin';
import { hostStore, identity, unpinnedClient } from '../services';
import { AgentClient } from '../core/api/agentClient';
import { nativeTransport } from '../core/native';

function describe(e: unknown): string {
  if (e instanceof CertPinMismatch) return 'The host certificate does not match the fingerprint you entered. Nothing was sent.';
  if (e instanceof MissingCertPin) return 'Enter the host certificate fingerprint shown by `rfe-agent pair`.';
  if (e instanceof AgentApiError) return `${e.code}: ${e.message}`;
  return (e as Error).message;
}

export default function Pair() {
  const router = useRouter();
  const p = useLocalSearchParams<{ address?: string; label?: string }>();
  const [address, setAddress] = useState(p.address ?? '');
  const [fingerprint, setFingerprint] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    const pin = normalizeFingerprint(fingerprint);
    if (pin === null) return setError('Fingerprint must be 64 hex characters (SHA-256).');
    setBusy(true);
    try {
      const host = { id: `h-${Date.now().toString(36)}`, label: p.label ?? address, address: address.trim() };
      // The pin comes from an independent channel (the pairing screen), and is
      // enforced before the pairing code or any secret leaves the phone.
      const nonce = await unpinnedClient(host).challenge();
      const client = new AgentClient(host, { transport: nativeTransport, pinnedFingerprint: pin });
      const res = await client.pair({
        pairingCode: code.trim(),
        deviceLabel: 'Android (RN)',
        devicePublicKey: await identity.publicKeyBase64(),
        nonce,
        signature: await identity.signBase64(nonce),
      });
      await hostStore.commitPairing(
        { ...host, label: res.agentName || host.label, address: host.address, tailscaleAddress: res.tailscaleAddress },
        { token: res.deviceToken, fingerprint: pin },
      );
      router.replace('/');
    } catch (e) {
      setError(describe(e));
    } finally {
      setBusy(false);
    }
  }

  const field = { borderWidth: 1, borderColor: '#999', borderRadius: 8, padding: 12, fontSize: 16 } as const;
  return (
    <ScrollView contentContainerStyle={{ padding: 16, gap: 12 }} keyboardShouldPersistTaps="handled">
      <Text>Host address</Text>
      <TextInput style={field} value={address} onChangeText={setAddress} placeholder="192.168.1.20:8765" autoCapitalize="none" autoCorrect={false} />
      <Text>Certificate fingerprint (SHA-256)</Text>
      <TextInput style={field} value={fingerprint} onChangeText={setFingerprint} placeholder="97f2…" autoCapitalize="none" autoCorrect={false} />
      <Text>Pairing code</Text>
      <TextInput style={field} value={code} onChangeText={setCode} placeholder="ABCD1234" autoCapitalize="characters" autoCorrect={false} />
      {error && <Text accessibilityRole="alert" style={{ color: '#b00020' }}>{error}</Text>}
      <Pressable
        accessibilityRole="button"
        disabled={busy || !address || !fingerprint || !code}
        onPress={submit}
        style={{ backgroundColor: busy ? '#888' : '#1a56db', padding: 14, borderRadius: 10, alignItems: 'center' }}
      >
        <Text style={{ color: 'white', fontSize: 16 }}>{busy ? 'Pairing…' : 'Pair'}</Text>
      </Pressable>
    </ScrollView>
  );
}
