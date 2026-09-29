import { useEffect, useState } from 'react';
import { ScrollView, Text } from 'react-native';

import { nativeSecureStore, readLegacyPrefs } from './src/core/native';
import { SecureKeys } from './src/core/security/secureStore';

// Spike 1B probe: reads what the Flutter app stored, in place. Replaced by the
// real Expo Router app in phase 2. Logs only lengths/booleans, never secrets.
export default function App() {
  const [out, setOut] = useState('probing…');
  useEffect(() => {
    (async () => {
      const lines: string[] = [];
      try {
        const priv = await nativeSecureStore.read(SecureKeys.devicePrivate);
        const token = await nativeSecureStore.read(SecureKeys.token('h1'));
        const fp = await nativeSecureStore.read(SecureKeys.fingerprint('h1'));
        lines.push(`identity: ${priv === 'SEED-PRIV-MIGRATION-TEST'}`);
        lines.push(`token: ${token === 'SEED-TOKEN'}`);
        lines.push(`fp: ${fp === 'a'.repeat(64)}`);
      } catch (e) {
        lines.push(`secure ERROR ${(e as Error).message}`);
      }
      try {
        const prefs = await readLegacyPrefs();
        lines.push(`prefs keys: ${Object.keys(prefs).join(',')}`);
        lines.push(`hosts: ${prefs.rfe_hosts_v1}`);
      } catch (e) {
        lines.push(`prefs ERROR ${(e as Error).message}`);
      }
      const text = lines.join('\n');
      console.log(`RFEPROBE\n${text}`);
      setOut(text);
    })();
  }, []);
  return (
    <ScrollView contentContainerStyle={{ padding: 32, paddingTop: 80 }}>
      <Text selectable>{out}</Text>
    </ScrollView>
  );
}
