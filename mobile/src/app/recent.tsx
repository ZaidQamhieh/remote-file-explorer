import { Stack, useRouter } from 'expo-router';
import { History } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, RefreshControl, ScrollView, View } from 'react-native';

import type { Entry, SearchResult } from '../core/api/models';
import { formatRelative } from '../core/format';
import { ErrorRetry, Pressable, SectionLabel, Text } from '../design/components';
import { useScheme } from '../design/theme';
import { FontFamily, Radii, Spacing } from '../design/tokens';
import { EntryLeading, useIconChipBg } from '../features/explorer/EntryIcon';
import { revealInExplorer } from '../features/explorer/reveal';
import { humanizeError } from '../features/pairing/pairingService';
import { groupRecent } from '../features/recent/recentBuckets';
import { TruncationBanner } from '../features/search/SearchParts';
import { t } from '../i18n';
import { clientForHost } from '../services';
import { useActiveHost } from '../state/activeHost';

/** The most recently modified files on the host, grouped Today / Yesterday / Earlier. Tapping one shows its folder in Files. */
export default function Recent() {
  const c = useScheme();
  const router = useRouter();
  const active = useActiveHost((s) => s.active);
  const [result, setResult] = useState<SearchResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const host = active?.host;

  const fetchRecent = useCallback(async (): Promise<{ result: SearchResult } | { error: string }> => {
    if (!host) return { result: { entries: [], truncated: false, timeBudgetHit: false } };
    try {
      return { result: await (await clientForHost(host)).recent() };
    } catch (e) {
      return { error: humanizeError(e) };
    }
  }, [host]);
  const apply = useCallback((r: { result: SearchResult } | { error: string }) => {
    if ('result' in r) {
      setResult(r.result);
      setError(null);
    } else setError(r.error);
    setLoading(false);
  }, []);
  const reload = useCallback(async () => {
    setLoading(true);
    apply(await fetchRecent());
  }, [apply, fetchRecent]);
  useEffect(() => {
    let live = true;
    void fetchRecent().then((r) => live && apply(r));
    return () => {
      live = false;
    };
  }, [apply, fetchRecent]);

  if (!active) return null;
  let body: React.ReactNode;
  if (loading && result === null) body = <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator /></View>;
  else if (error && result === null) body = <ErrorRetry message={error} onRetry={reload} />;
  else if (!result || result.entries.length === 0) {
    body = (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, padding: Spacing.lg }}>
        <History size={64} color={c.outline} />
        <Text variant="titleMedium">{t('recentIsEmpty')}</Text>
        <Text variant="bodySmall" muted>{t('recentEmptySubtitle')}</Text>
      </View>
    );
  } else {
    const groups = groupRecent(result.entries, new Date());
    body = (
      <View style={{ flex: 1 }}>
        {result.timeBudgetHit && <TruncationBanner message={t('recentTimedOut')} />}
        <ScrollView refreshControl={<RefreshControl refreshing={loading} onRefresh={reload} />} contentContainerStyle={{ paddingVertical: Spacing.md }}>
          {groups.map((g) => (
            <View key={g.label}>
              <View style={{ paddingHorizontal: Spacing.md }}>
                <SectionLabel title={g.label} />
              </View>
              {g.entries.map((entry, i) => (
                <RecentRow key={entry.path} entry={entry} hostLabel={active.host.label} divider={i > 0} onPress={() => revealInExplorer(router, active.host, entry.path, active.rootPath)} />
              ))}
            </View>
          ))}
        </ScrollView>
      </View>
    );
  }

  return (
    <View style={{ flex: 1 }}>
      <Stack.Screen options={{ title: t('recentTitle') }} />
      {body}
    </View>
  );
}

function RecentRow({ entry, hostLabel, divider, onPress }: { entry: Entry; hostLabel: string; divider: boolean; onPress: () => void }) {
  const c = useScheme();
  const chip = useIconChipBg(entry);
  const sub = entry.modified ? `${hostLabel}  ·  modified ${formatRelative(new Date(entry.modified))}` : hostLabel;
  return (
    <Pressable onPress={onPress} accessibilityLabel={entry.name}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm, borderTopWidth: divider ? 1 : 0, borderColor: c.outlineVariant, marginLeft: divider ? Spacing.md : 0 }}>
        <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: chip, alignItems: 'center', justifyContent: 'center' }}>
          <EntryLeading entry={entry} size={18} />
        </View>
        <View style={{ flex: 1 }}>
          <Text numberOfLines={1} style={{ fontSize: 14, fontFamily: FontFamily.medium }}>{entry.name}</Text>
          <Text numberOfLines={1} muted style={{ fontSize: 11.5 }}>{sub}</Text>
        </View>
      </View>
    </Pressable>
  );
}
