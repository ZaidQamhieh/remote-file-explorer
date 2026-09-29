import { useRouter } from 'expo-router';
import { ArrowLeft, Monitor, Search } from 'lucide-react-native';
import { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, ScrollView, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useStore } from 'zustand';

import { formatSize } from '../../core/format';
import type { Host } from '../../core/models/host';
import { EmptyState, Pressable, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, FontFamily, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { clientForHost } from '../../services';
import { revealInExplorer } from '../explorer/reveal';
import { createCrossHostSearch, groupByHost, MIN_CROSS_QUERY } from './crossHostSearch';
import { ResultIconTile } from './SearchParts';

const DEBOUNCE_MS = 400;

/** Searches every paired computer at once; hits stream in per host and unreachable hosts are listed at the bottom. */
export function CrossHostSearchScreen({ hosts }: { hosts: Host[] }) {
  const c = useScheme();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const search = useMemo(() => createCrossHostSearch({ hosts, getClient: (h) => clientForHost(h) }), [hosts]);
  const state = useStore(search);
  const [text, setText] = useState('');
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );
  const onChange = (v: string) => {
    setText(v);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => void search.run(v), DEBOUNCE_MS);
  };

  const groups = groupByHost(state.results);
  const failedHosts = hosts.filter((h) => state.failed.includes(h.id));
  const short = text.trim().length < MIN_CROSS_QUERY;

  let body: React.ReactNode;
  if (state.searching && state.results.length === 0) {
    body = (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 }}>
        <ActivityIndicator />
        <Text>{t('crossHostSearching', { count: hosts.length })}</Text>
      </View>
    );
  } else if (short) body = <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><Text>{t('crossHostTypeToSearch')}</Text></View>;
  else if (state.results.length === 0) {
    body = (
      <View style={{ flex: 1 }}>
        <EmptyState kind="noMatches" message={t('crossHostNoResults')} />
        {failedHosts.length > 0 && <Text style={{ textAlign: 'center', fontSize: 12.5, paddingBottom: Spacing.lg }} color={c.error}>{t('crossHostUnreachableCount', { count: failedHosts.length })}</Text>}
      </View>
    );
  } else {
    body = (
      <ScrollView contentContainerStyle={{ paddingTop: 10, paddingBottom: 24 }}>
        <View style={{ paddingHorizontal: 18, flexDirection: 'row' }}>
          <View style={{ paddingHorizontal: 8, paddingVertical: 3, borderRadius: Radii.stadium, backgroundColor: `${Brand.seed}24` }}>
            <Text style={{ fontSize: 10.5, fontFamily: FontFamily.semibold }} color={Brand.seed}>{t('crossHostSearchingCount', { count: groups.length })}</Text>
          </View>
        </View>
        {groups.map((g) => (
          <View key={g.host.id}>
            <Text style={{ paddingHorizontal: 18, paddingTop: 14, paddingBottom: 4, fontSize: 10.5, fontFamily: FontFamily.semibold, letterSpacing: 0.9, textTransform: 'uppercase' }}>{g.host.label}</Text>
            {g.entries.map((entry) => (
              <Pressable key={entry.path} onPress={() => revealInExplorer(router, g.host, entry.path)} accessibilityLabel={`${entry.name} on ${g.host.label}`}>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingVertical: 11, paddingHorizontal: 18 }}>
                  <ResultIconTile entry={entry} />
                  <View style={{ flex: 1, gap: 2 }}>
                    <Text numberOfLines={1} style={{ fontSize: 14, fontFamily: FontFamily.medium }}>{entry.name}</Text>
                    <Text numberOfLines={1} muted style={{ fontSize: 11.5, fontFamily: FontFamily.mono }}>{entry.path}</Text>
                  </View>
                  {entry.size != null && <Text muted style={{ fontSize: 11.5 }}>{formatSize(entry.size)}</Text>}
                </View>
              </Pressable>
            ))}
          </View>
        ))}
        {failedHosts.map((h) => (
          <View key={h.id} style={{ marginHorizontal: 18, marginTop: 10, flexDirection: 'row', alignItems: 'center', gap: 10, padding: 14, borderRadius: Radii.lg, borderWidth: 1, borderColor: c.outlineVariant, backgroundColor: c.surface, opacity: 0.6 }}>
            <Monitor size={15} color={c.onSurfaceVariant} />
            <Text style={{ flex: 1, fontSize: 11.5 }} muted>{t('crossHostOffline', { host: h.label })}</Text>
          </View>
        ))}
      </ScrollView>
    );
  }

  return (
    <View style={{ flex: 1, backgroundColor: c.surface, paddingTop: insets.top }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 16, paddingTop: 14 }}>
        <Pressable onPress={() => router.back()} accessibilityLabel="Back" style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
          <ArrowLeft size={20} color={c.onSurfaceVariant} />
        </Pressable>
        <Text style={{ fontSize: 19, fontFamily: FontFamily.semibold }} accessibilityRole="header">{t('crossHostSearchTitle')}</Text>
      </View>
      <View style={{ paddingHorizontal: 16, paddingTop: 10 }}>
        <View style={{ minHeight: 44, flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 14, paddingVertical: 9, borderWidth: 1, borderColor: c.outlineVariant, borderRadius: Radii.stadium }}>
          <Search size={16} color={c.onSurfaceVariant} />
          <TextInput
            accessibilityLabel={t('crossHostSearchHint')}
            autoFocus
            value={text}
            onChangeText={onChange}
            placeholder={t('crossHostSearchHint')}
            placeholderTextColor={c.onSurfaceVariant}
            returnKeyType="search"
            autoCapitalize="none"
            autoCorrect={false}
            style={{ flex: 1, padding: 0, fontSize: 13.5, fontFamily: FontFamily.regular, color: c.onSurface }}
          />
        </View>
      </View>
      <View style={{ flex: 1 }}>{body}</View>
    </View>
  );
}
