import { useLocalSearchParams, useRouter } from 'expo-router';
import { useState } from 'react';
import { ScrollView, View } from 'react-native';

import { Button, Segmented } from '../../design/components';
import { Spacing } from '../../design/tokens';
import { LanPanel } from '../../features/pairing/LanPanel';
import { ManualPanel } from '../../features/pairing/ManualPanel';
import { QrPanel } from '../../features/pairing/QrPanel';
import { t } from '../../i18n';

export default function Pair() {
  const router = useRouter();
  const params = useLocalSearchParams<{ address?: string; mode?: string }>();
  const [mode, setMode] = useState(params.mode === 'code' ? 2 : 0);
  const requestPair = (address: string) => router.push({ pathname: '/pair/request', params: { address } });

  return (
    <ScrollView contentContainerStyle={{ padding: Spacing.lg, gap: Spacing.md }} keyboardShouldPersistTaps="handled">
      <Segmented options={[t('scanQrTab'), t('lanDiscoveryTab'), t('enterCodeTab')]} selectedIndex={mode} onChange={setMode} />
      {mode === 0 && <QrPanel onOpenCamera={() => router.push('/pair/scan')} />}
      {mode === 1 && <LanPanel onSelect={requestPair} />}
      {mode === 2 && <ManualPanel prefillAddress={params.address} onRequest={requestPair} />}
      <View style={{ flexDirection: 'row', justifyContent: 'center', gap: Spacing.md }}>
        <Button kind="text" label={t('loginTab')} onPress={() => router.push({ pathname: '/pair/login', params: { address: params.address } })} />
        <Button kind="text" label={t('registerTab')} onPress={() => router.push({ pathname: '/pair/register', params: { address: params.address } })} />
      </View>
    </ScrollView>
  );
}
