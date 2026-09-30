import { ChevronRight, File as FileIcon, FileArchive, FileText, Folder, Globe, Image as ImageIcon, Info, Music, Regex, Video, type LucideIcon } from 'lucide-react-native';
import { ScrollView, Text as RNText, View } from 'react-native';

import type { Entry } from '../../core/api/models';
import { roleOf } from '../../core/entryCategory';
import { formatDate, formatSize } from '../../core/format';
import { Pressable, Text } from '../../design/components';
import { roleTint, useRoles, useScheme } from '../../design/theme';
import { Brand, FontFamily, Radii, Spacing, type Roles } from '../../design/tokens';
import { t } from '../../i18n';
import { folderLabel } from '../explorer/paths';
import { CATEGORY_LABEL, highlightRange, SEARCH_CATEGORIES, type SearchCategory } from './searchLogic';

const CATEGORY_ICON: Record<SearchCategory, LucideIcon> = { folder: Folder, image: ImageIcon, video: Video, audio: Music, document: FileText, archive: FileArchive, other: FileIcon };
const CATEGORY_ROLE: Record<SearchCategory, keyof Roles | null> = { folder: 'folder', image: 'photo', video: 'photo', audio: 'route', document: 'doc', archive: 'warn', other: null };

/** Icon and tint of a result row by MIME type; the same accents as the category chips. */
export function resultIcon(e: Pick<Entry, 'isDir' | 'mimeType'>): { icon: LucideIcon; color: string | null } {
  if (e.isDir) return { icon: Folder, color: Brand.amber };
  const mime = e.mimeType ?? '';
  if (mime.startsWith('image/')) return { icon: ImageIcon, color: Brand.seed };
  if (mime.startsWith('video/')) return { icon: Video, color: Brand.accent };
  if (mime.startsWith('audio/')) return { icon: Music, color: Brand.online };
  if (mime.includes('pdf')) return { icon: FileText, color: Brand.red };
  if (mime.includes('zip') || mime.includes('archive')) return { icon: FileArchive, color: Brand.amber };
  if (mime.startsWith('text/') || mime.includes('json')) return { icon: FileText, color: '#009688' };
  return { icon: FileIcon, color: null };
}

/** Tinted 38dp square holding a result's icon. */
export function ResultIconTile({ entry }: { entry: Pick<Entry, 'isDir' | 'mimeType'> }) {
  const c = useScheme();
  const roles = useRoles();
  const { icon: Icon } = resultIcon(entry);
  const role = roleOf(entry);
  const tint = role ? roles[role] : c.onSurfaceVariant;
  return (
    <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: role ? roleTint(tint, c) : c.surfaceContainerHighest, alignItems: 'center', justifyContent: 'center' }}>
      <Icon size={19} color={tint} />
    </View>
  );
}

function HighlightedName({ name, query, highlight }: { name: string; query: string; highlight: boolean }) {
  const c = useScheme();
  const base = { fontSize: 14, fontFamily: FontFamily.medium, color: c.onSurface } as const;
  const r = highlight ? highlightRange(name, query) : null;
  if (!r) return <Text numberOfLines={1} style={base}>{name}</Text>;
  return (
    <RNText numberOfLines={1} style={base}>
      {name.slice(0, r.start)}
      <RNText style={{ fontFamily: FontFamily.semibold, backgroundColor: c.primaryContainer, color: c.onPrimaryContainer }}>{name.slice(r.start, r.end)}</RNText>
      {name.slice(r.end)}
    </RNText>
  );
}

/** One search hit: name with the matched part highlighted, and path, size and date on the monospace second line. */
export function SearchResultTile({ entry, query, highlight, onPress }: { entry: Entry; query: string; highlight: boolean; onPress: () => void }) {
  const c = useScheme();
  const sub = [entry.path, !entry.isDir ? formatSize(entry.size) : '', entry.modified ? formatDate(new Date(entry.modified)) : ''].filter(Boolean).join('  ·  ');
  return (
    <Pressable onPress={onPress} accessibilityLabel={entry.name}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingVertical: 11, paddingHorizontal: Spacing.xs }}>
        <ResultIconTile entry={entry} />
        <View style={{ flex: 1, gap: 2 }}>
          <HighlightedName name={entry.name} query={query} highlight={highlight} />
          <Text numberOfLines={2} muted style={{ fontSize: 12, fontFamily: FontFamily.mono }}>{sub}</Text>
        </View>
        {entry.isDir && <ChevronRight size={18} color={c.onSurfaceVariant} />}
      </View>
    </Pressable>
  );
}

/** Horizontally scrolling category filter chips; a selected chip fills with its own tint. */
export function CategoryChips({ selected, onToggle }: { selected: SearchCategory[]; onToggle: (c: SearchCategory) => void }) {
  const c = useScheme();
  const roles = useRoles();
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0 }} contentContainerStyle={{ paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs, gap: Spacing.xs, alignItems: 'center' }}>
      {SEARCH_CATEGORIES.map((cat) => {
        const on = selected.includes(cat);
        const role = CATEGORY_ROLE[cat];
        const tint = role ? roles[role] : c.primary;
        const Icon = CATEGORY_ICON[cat];
        return (
          <Pressable key={cat} onPress={() => onToggle(cat)} accessibilityLabel={t(CATEGORY_LABEL[cat])} accessibilityState={{ selected: on }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 12, paddingVertical: 6, borderRadius: Radii.stadium, backgroundColor: on ? roleTint(tint, c) : 'transparent', borderWidth: 1, borderColor: on ? tint : c.outlineVariant }}>
              <Icon size={13} color={on ? tint : (role ? tint : c.onSurfaceVariant)} />
              <Text style={{ fontSize: 12 }} color={on ? tint : c.onSurfaceVariant}>{t(CATEGORY_LABEL[cat])}</Text>
            </View>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

/** Static chip shown when the query is treated as a glob or regex. */
export function GlobIndicator() {
  const c = useScheme();
  return (
    <View style={{ paddingHorizontal: Spacing.md, paddingBottom: Spacing.xs, flexDirection: 'row' }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 12, paddingVertical: 6, borderRadius: Radii.stadium, backgroundColor: c.primary }}>
        <Regex size={13} color={c.onPrimary} />
        <Text style={{ fontSize: 12 }} color={c.onPrimary}>{t('globPattern')}</Text>
      </View>
    </View>
  );
}

/** Amber notice above a result list: the agent stopped early (result cap or time budget). */
export function TruncationBanner({ message }: { message: string }) {
  const c = useScheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.sm, paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm, backgroundColor: `${Brand.amber}24` }}>
      <Info size={16} color={Brand.amber} />
      <Text style={{ flex: 1, fontSize: 13 }} color={c.onSurface}>{message}</Text>
    </View>
  );
}

/** Gradient pill showing where the search runs (this folder or everywhere); tapping opens the filters. */
export function ScopePill({ fromHere, currentPath, onPress }: { fromHere: boolean; currentPath: string; onPress: () => void }) {
  const c = useScheme();
  const Icon = fromHere ? Folder : Globe;
  return (
    <Pressable onPress={onPress} accessibilityLabel={fromHere ? folderLabel(currentPath) : t('searchingEverywhere')} style={{ marginLeft: Spacing.md }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.xs, paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm, borderRadius: 18, backgroundColor: c.primary }}>
        <Icon size={15} color={c.onPrimary} />
        <Text numberOfLines={1} style={{ fontSize: 12.5, fontFamily: FontFamily.semibold, maxWidth: 140 }} color={c.onPrimary}>{fromHere ? folderLabel(currentPath) : t('searchingEverywhere')}</Text>
      </View>
    </Pressable>
  );
}
