import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { ArrowRight } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { ScrollView, View } from 'react-native';

import type { Drive } from '../../../core/api/models';
import { formatSize } from '../../../core/format';
import { aggregateUsage } from '../../../core/storage/usage';
import { EmptyState, ErrorRetry, Loading, Pressable, Text } from '../../../design/components';
import { useScheme } from '../../../design/theme';
import { Brand, FontFamily, Radii, Spacing } from '../../../design/tokens';
import { t } from '../../../i18n';
import { humanizeError } from '../../../features/pairing/pairingService';
import { useHostById } from '../../../features/hosts/useHostById';
import { ringSegments } from '../../../features/storage/storageLogic';
import { UsageRing } from '../../../features/storage/UsageRing';
import { clientForHost } from '../../../services';

const PALETTE = [Brand.seed, Brand.accent, Brand.amber];

/** Aggregate disk usage for one computer: a ring over its drives, a per-drive list, and the way into the by-type map. */
export default function StorageInsights() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const host = useHostById(id);
  const c = useScheme();
  const router = useRouter();
  const [drives, setDrives] = useState<Drive[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!host) return null;
    try {
      return { ok: true as const, drives: await (await clientForHost(host)).drives() };
    } catch (e) {
      return { ok: false as const, error: humanizeError(e) };
    }
  }, [host]);
  const apply = useCallback((r: Awaited<ReturnType<typeof load>>) => {
    if (!r) return;
    if (r.ok) {
      setDrives(r.drives);
      setError(null);
    } else setError(r.error);
  }, []);
  useEffect(() => {
    let live = true;
    void load().then((r) => live && apply(r));
    return () => {
      live = false;
    };
  }, [load, apply]);

  const usage = drives ? aggregateUsage(drives) : null;
  const label = host ? host.label || host.address : '';
  const title = <Stack.Screen options={{ title: t('storageInsightsTitle') }} />;

  if (host === undefined) return <Loading />;
  if (host === null) return <EmptyState message={t('hostNoLongerPaired')} />;
  if (error && !drives) return <View style={{ flex: 1 }}>{title}<ErrorRetry message={t('couldNotLoadStorage', { error })} onRetry={() => void load().then(apply)} /></View>;
  if (!drives) return <View style={{ flex: 1 }}>{title}<Loading /></View>;
  if (!usage) return <View style={{ flex: 1 }}>{title}<EmptyState message={t('emptyFolderMessage')} /></View>;

  const segments = ringSegments(drives);
  const colors = segments.map((s, i) => (s.key === 'free' ? c.surfaceContainerHighest : PALETTE[i % PALETTE.length]));
  const used = usage.totalBytes - usage.freeBytes;
  return (
    <ScrollView contentContainerStyle={{ padding: Spacing.md, gap: Spacing.md, paddingBottom: Spacing.xl }}>
      {title}
      <Text muted style={{ textAlign: 'center' }}>{t('hostStorageSubtitle', { hostLabel: label, used: formatSize(used), total: formatSize(usage.totalBytes) })}</Text>
      <View style={{ alignItems: 'center', paddingVertical: Spacing.md }}>
        <UsageRing segments={segments.map((s, i) => ({ color: colors[i], fraction: s.fraction }))} percent={Math.round(usage.usedFraction * 100)} usedLabel={formatSize(used)} />
      </View>
      <View>
        {segments.map((s, i) => (
          <View key={s.key} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 11, paddingHorizontal: 4, borderBottomWidth: i < segments.length - 1 ? 1 : 0, borderBottomColor: c.outlineVariant }}>
            <View style={{ width: 12, height: 12, borderRadius: 3, backgroundColor: colors[i] }} />
            <Text numberOfLines={1} style={{ flex: 1, fontSize: 14, fontFamily: FontFamily.medium }}>{s.drive ? s.drive.label || s.drive.path : t('freeSpaceLabel')}</Text>
            <Text muted style={{ fontFamily: FontFamily.mono, fontSize: 11.5 }}>{formatSize(s.drive ? s.drive.totalBytes! - Math.min(s.drive.freeBytes!, s.drive.totalBytes!) : usage.freeBytes)}</Text>
          </View>
        ))}
      </View>
      <Pressable onPress={() => router.push({ pathname: '/host/[id]/types', params: { id: host.id } })} accessibilityRole="button" accessibilityLabel={t('openStorageTypeMapButton')}>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7, paddingHorizontal: 18, paddingVertical: 11, backgroundColor: c.surfaceContainerHigh, borderWidth: 1, borderColor: c.outlineVariant, borderRadius: Radii.sm }}>
          <Text style={{ fontSize: 13.5, fontFamily: FontFamily.semibold }}>{t('openStorageTypeMapButton')}</Text>
          <ArrowRight size={16} color={c.onSurface} />
        </View>
      </Pressable>
    </ScrollView>
  );
}
