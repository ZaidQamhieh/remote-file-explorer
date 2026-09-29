import { Monitor, Radar, X } from 'lucide-react-native';
import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Platform, View } from 'react-native';

import type { DiscoveredAgent } from '../../core/discovery';
import { scanLan, stopLanScan } from '../../core/native';
import { Button, GroupedCard, HintCard, Pressable, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Spacing } from '../../design/tokens';
import { t } from '../../i18n';

export function LanPanel({ onSelect }: { onSelect: (authority: string) => void }) {
  const c = useScheme();
  const [agents, setAgents] = useState<DiscoveredAgent[]>([]);
  const [scanning, setScanning] = useState(false);
  const [searched, setSearched] = useState(false);
  const [failed, setFailed] = useState(false);
  const live = useRef(true);
  const scanningRef = useRef(false);

  useEffect(() => {
    live.current = true;
    return () => {
      live.current = false;
      if (scanningRef.current) stopLanScan().catch(() => {});
    };
  }, []);

  if (Platform.OS !== 'android') return <Text style={{ textAlign: 'center', padding: Spacing.lg }}>{t('lanDiscoveryUnavailable')}</Text>;

  async function scan() {
    if (scanning) {
      await stopLanScan().catch(() => {});
      return;
    }
    scanningRef.current = true;
    setScanning(true);
    setSearched(true);
    setFailed(false);
    setAgents([]);
    try {
      const found = await scanLan();
      if (live.current) setAgents(found);
    } catch {
      if (live.current) setFailed(true);
    } finally {
      scanningRef.current = false;
      if (live.current) setScanning(false);
    }
  }

  return (
    <View style={{ gap: Spacing.md }}>
      <Text muted style={{ lineHeight: 20 }}>{t('lanDiscoveryIntro')}</Text>
      <Button label={scanning ? t('stopLocalSearch') : t('scanLocalNetwork')} kind="filled" onPress={scan} icon={scanning ? <X size={18} color={c.onPrimary} /> : <Radar size={18} color={c.onPrimary} />} />
      {scanning && (
        <View style={{ alignItems: 'center', gap: 8 }}>
          <ActivityIndicator />
          <Text variant="bodySmall">{t('searchingLocalNetwork')}</Text>
        </View>
      )}
      {failed ? (
        <Text color={c.error}>{t('lanDiscoveryFailed')}</Text>
      ) : !scanning && searched && agents.length === 0 ? (
        <Text muted style={{ textAlign: 'center' }}>{t('noLocalAgentsFound')}</Text>
      ) : null}
      {agents.map((a) => (
        <GroupedCard key={a.authority}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
            <Monitor size={22} color={c.primary} />
            <View style={{ flex: 1 }}>
              <Text variant="titleMedium">{a.name}</Text>
              <Text muted>{a.authority}</Text>
            </View>
            <Pressable onPress={() => onSelect(a.authority)} accessibilityLabel={t('useAddress')}>
              <Text variant="labelLarge" color={c.primary} style={{ padding: 8 }}>{t('useAddress')}</Text>
            </Pressable>
          </View>
        </GroupedCard>
      ))}
      <HintCard kind="warning" text={t('discoveryTrustWarning')} />
    </View>
  );
}
