import { UpdateBanner } from '../../features/update/UpdateBanner';
import { useFocusEffect, useRouter } from 'expo-router';
import { Plus, QrCode, Search, Monitor, X } from 'lucide-react-native';
import { useCallback, useState } from 'react';
import { RefreshControl, ScrollView, View } from 'react-native';

import type { Host } from '../../core/models/host';
import { AppBar, AppBarIconButton, Button, ErrorRetry, Loading, Pressable, SearchBar, SectionLabel, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Radii, Spacing } from '../../design/tokens';
import { HostCard } from '../../features/hosts/HostCard';
import { humanizeError } from '../../features/pairing/pairingService';
import { t } from '../../i18n';
import { ensureLegacyImport, hostStore } from '../../services';

export default function Devices() {
  const router = useRouter();
  const c = useScheme();
  const [hosts, setHosts] = useState<Host[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showSearch, setShowSearch] = useState(false);
  const [query, setQuery] = useState('');
  const [online, setOnline] = useState<Record<string, boolean>>({});
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      await ensureLegacyImport();
      setHosts(await hostStore.listHosts());
      setError(null);
    } catch (e) {
      setError(humanizeError(e));
    }
  }, []);
  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  const reportOnline = useCallback((id: string, o: boolean) => setOnline((cur) => (cur[id] === o ? cur : { ...cur, [id]: o })), []);
  const onlineCount = (hosts ?? []).filter((h) => online[h.id]).length;
  const q = query.trim().toLowerCase();
  const shown = (hosts ?? []).filter((h) => !q || h.label.toLowerCase().includes(q) || h.address.toLowerCase().includes(q));

  const header = (
    <>
    <AppBar
      title="Devices"
      subtitle={hosts && hosts.length > 0 ? `${hosts.length} paired · ${onlineCount} online now` : undefined}
      actions={
        <>
          <AppBarIconButton label={t('searchButton')} onPress={() => setShowSearch((s) => !s)}>
            {showSearch ? <X size={19} color={c.onSurfaceVariant} /> : <Search size={19} color={c.onSurfaceVariant} />}
          </AppBarIconButton>
          <AppBarIconButton label={t('receiveFileTooltip')} onPress={() => router.push('/receive')}>
            <QrCode size={19} color={c.onSurfaceVariant} />
          </AppBarIconButton>
        </>
      }
    />
    <UpdateBanner />
    </>
  );

  if (error) return (<View style={{ flex: 1 }}>{header}<ErrorRetry message={t('errorLabel', { error })} onRetry={load} /></View>);
  if (hosts === null) return (<View style={{ flex: 1 }}>{header}<Loading /></View>);

  if (hosts.length === 0) {
    return (
      <View style={{ flex: 1 }}>
        {header}
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: Spacing.xl, gap: Spacing.md }}>
          <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={{ width: 112, height: 112, borderRadius: 56, backgroundColor: c.primaryContainer, alignItems: 'center', justifyContent: 'center' }}>
            <Monitor size={48} color={c.onPrimaryContainer} />
          </View>
          <Text variant="headlineSmall" style={{ textAlign: 'center', fontFamily: 'Lato_700Bold' }}>{t('emptyStatePairTitle')}</Text>
          <Text muted style={{ textAlign: 'center' }}>{t('emptyStatePairBody')}</Text>
          <Button kind="filled" label={t('scanQrCodeButton')} renderIcon={(k) => <QrCode size={18} color={k} />} onPress={() => router.push('/pair')} />
        </View>
      </View>
    );
  }

  return (
    <View style={{ flex: 1 }}>
      {header}
      {showSearch && (
        <View style={{ paddingHorizontal: Spacing.md, paddingBottom: Spacing.sm }}>
          <SearchBar value={query} onChange={setQuery} placeholder="Search devices…" autoFocus />
        </View>
      )}
      {shown.length === 0 ? (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Text muted>{`No devices match "${query}"`}</Text>
        </View>
      ) : (
        <ScrollView
          contentContainerStyle={{ paddingHorizontal: Spacing.md, paddingTop: Spacing.sm, paddingBottom: Spacing.xl * 2, gap: 10 }}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}
        >
          {shown.map((h, i) => (
            <View key={h.id} style={{ gap: 10 }}>
              {!q && i === 1 && <SectionLabel title={`Also paired · ${shown.length - 1}`} />}
              <HostCard host={h} isHero={!q && i === 0} onOnlineChanged={(o) => reportOnline(h.id, o)} onChanged={load} />
            </View>
          ))}
          <View style={{ marginTop: Spacing.md }}>
            <SectionLabel title="Add another computer" />
            <GhostAdd onPress={() => router.push('/pair')} label={t('addComputerButton')} />
          </View>
        </ScrollView>
      )}
    </View>
  );
}

/** Tonal, borderless 'Add computer' action. */
function GhostAdd({ onPress, label }: { onPress: () => void; label: string }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} accessibilityLabel={label}>
      <View style={{ height: 52, flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 8, paddingHorizontal: 18, backgroundColor: c.surfaceContainerHigh, borderRadius: Radii.sm }}>
        <Plus size={18} color={c.onSurface} />
        <Text style={{ fontSize: 14, fontFamily: 'Lato_700Bold' }}>{label}</Text>
      </View>
    </Pressable>
  );
}
