import { useLocalSearchParams, useRouter } from 'expo-router';
import { useState } from 'react';
import { ScrollView, View } from 'react-native';

import { Button, Segmented, useToast } from '../../design/components';
import { Spacing } from '../../design/tokens';
import { LanPanel } from '../../features/pairing/LanPanel';
import { ManualPanel } from '../../features/pairing/ManualPanel';
import { QrPanel } from '../../features/pairing/QrPanel';
import { t } from '../../i18n';

export default function Pair() {
  const router = useRouter();
  const toast = useToast();
  const params = useLocalSearchParams<{ address?: string; mode?: string }>();
  const [mode, setMode] = useState(params.mode === 'code' ? 2 : 0);
  const [discovered, setDiscovered] = useState<string | undefined>(undefined);

  const paired = (label: string) => {
    toast.success(t('pairedWith', { name: label }));
    router.dismissTo('/');
  };

  return (
    <ScrollView contentContainerStyle={{ padding: Spacing.lg, gap: Spacing.md }} keyboardShouldPersistTaps="handled">
      <Segmented options={[t('scanQrTab'), t('lanDiscoveryTab'), t('enterCodeTab')]} selectedIndex={mode} onChange={setMode} />
      {mode === 0 && <QrPanel onOpenCamera={() => router.push('/pair/scan')} />}
      {mode === 1 && (
        <LanPanel
          onSelect={(a) => {
            setDiscovered(a);
            setMode(2);
          }}
        />
      )}
      {mode === 2 && <ManualPanel key={discovered} prefillAddress={discovered ?? params.address} onPaired={paired} />}
      <View style={{ flexDirection: 'row', justifyContent: 'center', gap: Spacing.md }}>
        <Button kind="text" label={t('loginTab')} onPress={() => router.push({ pathname: '/pair/login', params: { address: discovered ?? params.address } })} />
        <Button kind="text" label={t('registerTab')} onPress={() => router.push({ pathname: '/pair/register', params: { address: discovered ?? params.address } })} />
      </View>
    </ScrollView>
  );
}
