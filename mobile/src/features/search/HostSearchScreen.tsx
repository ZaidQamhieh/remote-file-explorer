import { useRouter } from 'expo-router';
import { ArrowLeft, Bookmark, BookmarkPlus, History, Search, SearchX, SlidersHorizontal, X } from 'lucide-react-native';
import { useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, ScrollView, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useStore } from 'zustand';

import type { Host } from '../../core/models/host';
import { ErrorRetry, GhostBlockButton, Pressable, Text, useDialogs } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, FontFamily, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { clientForHost } from '../../services';
import { useCollections } from '../../state/collections';
import { useResolvedVisibility } from '../../state/settings';
import { useActiveHost } from '../../state/activeHost';
import { revealInExplorer } from '../explorer/reveal';
import { humanizeError } from '../pairing/pairingService';
import { SearchFilterSheet } from './SearchFilterSheet';
import { CategoryChips, GlobIndicator, ScopePill, SearchResultTile, TruncationBanner } from './SearchParts';
import { createSearchController } from './searchController';
import { activeFilterCount, defaultFilters, filterSearchResults, isGlobQuery, type SearchCategory, type SearchFilters } from './searchLogic';

const DEBOUNCE_MS = 450;

/** Search one host: debounced query, category chips, filter sheet, recent and saved searches. Tapping a hit shows its folder in Files. */
export function HostSearchScreen({ host, currentPath, onlyEverywhere }: { host: Host; currentPath: string; onlyEverywhere?: boolean }) {
  const c = useScheme();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const dialogs = useDialogs();
  const vis = useResolvedVisibility(host.id);
  const recordSearch = useCollections((s) => s.recordSearch);
  const controller = useMemo(
    () => createSearchController({ getClient: () => clientForHost(host), humanize: humanizeError, onSearched: (q) => void recordSearch(q) }),
    [host, recordSearch],
  );
  const state = useStore(controller);
  const [text, setText] = useState('');
  const [filters, setFilters] = useState<SearchFilters>(() => ({ ...defaultFilters(), fromHere: !onlyEverywhere }));
  const [filterOpen, setFilterOpen] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  const run = (value: string, f: SearchFilters = filters) => {
    if (timer.current) clearTimeout(timer.current);
    void controller.run(value, f, currentPath);
  };
  const onChange = (value: string) => {
    setText(value);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => void controller.run(value, filters, currentPath), DEBOUNCE_MS);
  };
  const apply = (f: SearchFilters) => {
    setFilters(f);
    setFilterOpen(false);
    if (text.trim()) run(text, f);
  };
  const toggleCategory = (cat: SearchCategory) => {
    const categories = filters.categories.includes(cat) ? filters.categories.filter((x) => x !== cat) : [...filters.categories, cat];
    const next = { ...filters, categories };
    setFilters(next);
    if (text.trim()) run(text, next);
  };
  const pick = (q: string) => {
    setText(q);
    run(q);
  };

  async function saveCurrent() {
    const q = text.trim();
    if (!q) return;
    const name = await dialogs.prompt({ title: t('saveSearch'), placeholder: t('savedSearchName'), initialValue: q, confirmLabel: t('saveButton') });
    if (name) await useCollections.getState().addSavedSearch({ name, query: q });
  }

  const results = useMemo(() => filterSearchResults(state.raw, vis, filters.includeHidden), [state.raw, vis, filters.includeHidden]);
  const glob = filters.mode !== 'substring' || isGlobQuery(state.query);
  const active = useActiveHost((s) => s.active);
  const rootPath = active?.host.id === host.id ? active.rootPath : undefined;
  const banner = state.truncated ? t('showingFirstNResults', { limit: results.length }) : state.timeBudgetHit ? t('searchTimedOut') : null;

  let body: React.ReactNode;
  if (state.query === '') body = <RecentAndSaved onPick={pick} onAllHosts={() => router.replace('/search')} />;
  else if (state.loading) body = <ResultSkeleton />;
  else if (state.error) body = <ErrorRetry message={t('searchFailed', { error: state.error })} onRetry={() => run(text)} />;
  else if (results.length === 0) body = <Centered message={t('noResultsFor', { query: state.query })} />;
  else {
    body = (
      <FlatList
        data={results}
        keyExtractor={(e) => e.path}
        contentContainerStyle={{ padding: Spacing.md }}
        ItemSeparatorComponent={() => <View style={{ height: 1, marginHorizontal: Spacing.md, backgroundColor: c.outlineVariant }} />}
        renderItem={({ item }) => <SearchResultTile entry={item} query={state.query} highlight={!glob} onPress={() => revealInExplorer(router, host, item.path, rootPath)} />}
      />
    );
  }

  const count = activeFilterCount(filters);
  return (
    <View style={{ flex: 1, backgroundColor: c.surface, paddingTop: insets.top }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 16, paddingTop: 14, paddingBottom: 12 }}>
        <Pressable onPress={() => router.back()} accessibilityLabel="Back" style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
          <ArrowLeft size={20} color={c.onSurfaceVariant} />
        </Pressable>
        <View style={{ flex: 1, minHeight: 44, flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 14, paddingVertical: 9, backgroundColor: c.surface, borderWidth: 1, borderColor: c.outlineVariant, borderRadius: Radii.stadium }}>
          <Search size={16} color={c.onSurfaceVariant} />
          <TextInput
            accessibilityLabel={t('searchHint')}
            autoFocus
            value={text}
            onChangeText={onChange}
            onSubmitEditing={() => run(text)}
            placeholder={t('searchHint')}
            placeholderTextColor={c.onSurfaceVariant}
            returnKeyType="search"
            autoCapitalize="none"
            autoCorrect={false}
            style={{ flex: 1, padding: 0, fontSize: 13.5, fontFamily: FontFamily.regular, color: c.onSurface }}
          />
          {text !== '' && (
            <>
              <Pressable onPress={saveCurrent} accessibilityLabel={t('saveSearch')}>
                <BookmarkPlus size={16} color={c.onSurfaceVariant} />
              </Pressable>
              <Pressable
                onPress={() => {
                  onChange('');
                  run('');
                }}
                accessibilityLabel="Clear"
              >
                <X size={16} color={c.onSurfaceVariant} />
              </Pressable>
            </>
          )}
        </View>
        <Pressable onPress={() => setFilterOpen(true)} accessibilityLabel={t('searchFiltersTooltip')} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
          <SlidersHorizontal size={19} color={c.onSurfaceVariant} />
          {count > 0 && (
            <View style={{ position: 'absolute', top: 4, right: 4, minWidth: 14, paddingHorizontal: 4, borderRadius: Radii.stadium, backgroundColor: Brand.seed, alignItems: 'center' }}>
              <Text style={{ fontSize: 9, lineHeight: 12 }} color="#fff">{String(count)}</Text>
            </View>
          )}
        </Pressable>
      </View>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <ScopePill fromHere={filters.fromHere} currentPath={currentPath} onPress={() => setFilterOpen(true)} />
        <View style={{ flex: 1 }}>
          <CategoryChips selected={filters.categories} onToggle={toggleCategory} />
        </View>
      </View>
      {glob && state.query !== '' && <GlobIndicator />}
      {banner && <TruncationBanner message={banner} />}
      <View style={{ height: 1, backgroundColor: c.outlineVariant }} />
      <View style={{ flex: 1 }}>{body}</View>
      <SearchFilterSheet visible={filterOpen} filters={filters} currentPath={currentPath} onApply={apply} onClose={() => setFilterOpen(false)} />
    </View>
  );
}

function Centered({ message }: { message: string }) {
  const c = useScheme();
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: Spacing.xl, gap: Spacing.md }}>
      <SearchX size={56} color={c.outline} />
      <Text style={{ textAlign: 'center' }}>{message}</Text>
    </View>
  );
}

function ResultSkeleton() {
  const c = useScheme();
  return (
    <View accessibilityRole="progressbar" accessibilityLabel="Searching">
      {Array.from({ length: 8 }, (_, i) => (
        <View key={i} style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm }}>
          <View style={{ width: 40, height: 40, borderRadius: 6, backgroundColor: c.surfaceContainerHighest }} />
          <View style={{ gap: Spacing.xs }}>
            <View style={{ height: 12, width: i % 2 ? 130 : 180, borderRadius: 6, backgroundColor: c.surfaceContainerHighest }} />
            <View style={{ height: 10, width: 90, borderRadius: 6, backgroundColor: c.surfaceContainerHighest }} />
          </View>
        </View>
      ))}
    </View>
  );
}

/** Empty-query body: saved searches, then recent ones (each removable), or a hint when there are none. */
function RecentAndSaved({ onPick, onAllHosts }: { onPick: (q: string) => void; onAllHosts: () => void }) {
  const c = useScheme();
  const saved = useCollections((s) => s.savedSearches);
  const recent = useCollections((s) => s.recentSearches);
  const removeSaved = useCollections((s) => s.removeSavedSearch);
  const removeRecent = useCollections((s) => s.removeRecentSearch);
  const clearRecent = useCollections((s) => s.clearRecentSearches);
  const allHosts = (
    <View style={{ padding: Spacing.md }}>
      <GhostBlockButton label={t('searchEveryHostButton')} onPress={onAllHosts} />
    </View>
  );
  if (saved.length === 0 && recent.length === 0) {
    return (
      <View style={{ flex: 1 }}>
        <Centered message={t('typeToSearch')} />
        {allHosts}
      </View>
    );
  }
  const label = (text: string, trailing?: React.ReactNode) => (
    <View style={{ flexDirection: 'row', alignItems: 'center', paddingLeft: Spacing.md, paddingRight: Spacing.sm, paddingTop: Spacing.md, paddingBottom: Spacing.xs }}>
      <Text style={{ flex: 1, fontSize: 10.5, fontFamily: FontFamily.semibold, letterSpacing: 0.9, textTransform: 'uppercase' }}>{text}</Text>
      {trailing}
    </View>
  );
  return (
    <ScrollView keyboardShouldPersistTaps="handled">
      {saved.length > 0 && label(t('savedSearches'))}
      {saved.map((s) => (
        <Row key={s.name} icon={<Bookmark size={19} color={Brand.seed} />} tint={Brand.seed} title={s.name} subtitle={s.query} onPress={() => onPick(s.query)} onRemove={() => void removeSaved(s.name)} />
      ))}
      {recent.length > 0 &&
        label(
          t('recentSearches'),
          <Pressable onPress={() => void clearRecent()} accessibilityLabel={t('clearAllButton')}>
            <Text style={{ fontSize: 12.5, paddingHorizontal: Spacing.sm, paddingVertical: Spacing.xs }} color={c.primary}>{t('clearAllButton')}</Text>
          </Pressable>,
        )}
      {recent.map((q) => (
        <Row key={q} icon={<History size={19} color={c.onSurfaceVariant} />} title={q} onPress={() => onPick(q)} onRemove={() => void removeRecent(q)} />
      ))}
      {allHosts}
    </ScrollView>
  );
}

function Row({ icon, tint, title, subtitle, onPress, onRemove }: { icon: React.ReactNode; tint?: string; title: string; subtitle?: string; onPress: () => void; onRemove: () => void }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} accessibilityLabel={title}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingVertical: 11, paddingHorizontal: Spacing.md }}>
        <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: tint ? `${tint}24` : c.surfaceContainerHigh, alignItems: 'center', justifyContent: 'center' }}>{icon}</View>
        <View style={{ flex: 1 }}>
          <Text numberOfLines={1} style={{ fontSize: 14, fontFamily: FontFamily.medium }}>{title}</Text>
          {subtitle ? <Text numberOfLines={1} muted style={{ fontSize: 11.5 }}>{subtitle}</Text> : null}
        </View>
        <Pressable onPress={onRemove} accessibilityLabel={`Remove ${title}`} style={{ padding: Spacing.xs }}>
          <X size={18} color={c.onSurfaceVariant} />
        </Pressable>
      </View>
    </Pressable>
  );
}
