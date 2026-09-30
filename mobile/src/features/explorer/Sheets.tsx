import { ArrowDown, ArrowUp, Folder, Plus, Star } from 'lucide-react-native';
import { ScrollView, View } from 'react-native';

import type { Host } from '../../core/models/host';
import { BottomSheet, GroupedCard, MockupSwitch, Pressable, Segmented, SectionLabel, SheetHead, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { useSettings } from '../../state/settings';
import { useCollections } from '../../state/collections';
import type { ExplorerState } from './explorerStore';
import { currentPath } from './explorerStore';
import { folderLabel } from './paths';
import type { EntryDensity, SortField, SortOrder } from './sort';

const SORT_FIELDS: SortField[] = ['name', 'size', 'date', 'type'];
const sortLabel = (f: SortField) => t(f === 'name' ? 'sortFieldName' : f === 'size' ? 'sortFieldSize' : f === 'date' ? 'sortFieldDate' : 'sortFieldType');

export function ViewOptionsSheet({ visible, onClose, gridView, density, sort, showHidden, hiddenCount, onToggleShowHidden }: { visible: boolean; onClose: () => void; gridView: boolean; density: EntryDensity; sort: SortOrder; showHidden: boolean; hiddenCount: number; onToggleShowHidden: () => void }) {
  const c = useScheme();
  const setApp = useSettings((s) => s.setApp);
  return (
    <BottomSheet visible={visible} onClose={onClose}>
      <SheetHead title={t('viewOptionsTitle')} />
      <ScrollView contentContainerStyle={{ paddingHorizontal: Spacing.md, paddingBottom: Spacing.lg, gap: Spacing.sm }}>
        <Text variant="labelLarge">{t('layoutLabel')}</Text>
        <Segmented options={[t('listLabel'), t('gridLabel')]} selectedIndex={gridView ? 1 : 0} onChange={(i) => setApp('gridView', i === 1)} />
        <View style={{ height: Spacing.sm }} />
        <Text variant="labelLarge">{t('densityLabel')}</Text>
        <Segmented options={[t('comfortableLabel'), t('compactLabel')]} selectedIndex={density === 'compact' ? 1 : 0} onChange={(i) => setApp('density', i === 1 ? 'compact' : 'comfortable')} />
        <View style={{ height: Spacing.sm }} />
        <SectionLabel title={t('sortByLabel')} />
        <View>
          {SORT_FIELDS.map((f, i) => (
            <Pressable
              key={f}
              onPress={() => setApp('sort', sort.field === f ? { ...sort, ascending: !sort.ascending } : { field: f, ascending: true })}
              accessibilityLabel={sortLabel(f)}
              accessibilityState={{ selected: sort.field === f }}
            >
              <View style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 11, paddingHorizontal: 4, borderBottomWidth: i === SORT_FIELDS.length - 1 ? 0 : 1, borderColor: c.outlineVariant }}>
                <Text style={{ flex: 1, fontSize: 14, fontFamily: 'Lato_400Regular' }}>{sortLabel(f)}</Text>
                {sort.field === f && (sort.ascending ? <ArrowUp size={17} color={c.primary} /> : <ArrowDown size={17} color={c.primary} />)}
              </View>
            </Pressable>
          ))}
        </View>
        <View style={{ height: Spacing.sm }} />
        <SectionLabel title={t('optionsLabel')} />
        <GroupedCard padded={false}>
          <ToggleRow title={t('foldersFirstLabel')} value divider />
          <ToggleRow title={t('showHiddenItems')} subtitle={hiddenCount > 0 ? t('nHiddenByVisibility', { count: hiddenCount }) : undefined} value={showHidden} onPress={onToggleShowHidden} />
        </GroupedCard>
      </ScrollView>
    </BottomSheet>
  );
}

function ToggleRow({ title, subtitle, value, onPress, divider }: { title: string; subtitle?: string; value: boolean; onPress?: () => void; divider?: boolean }) {
  const c = useScheme();
  const row = (
    <View style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 12, paddingHorizontal: 14, borderBottomWidth: divider ? 1 : 0, borderColor: c.outlineVariant }}>
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 14, fontFamily: 'Lato_400Regular' }}>{title}</Text>
        {subtitle ? <Text muted style={{ fontSize: 11.5, marginTop: 1 }}>{subtitle}</Text> : null}
      </View>
      <MockupSwitch value={value} />
    </View>
  );
  return onPress ? <Pressable onPress={onPress} accessibilityLabel={title}>{row}</Pressable> : row;
}

export function FavoritesSheet({ visible, onClose, host, state, onOpen }: { visible: boolean; onClose: () => void; host: Host; state: ExplorerState; onOpen: (path: string) => void }) {
  const c = useScheme();
  const favs = useCollections((s) => s.favorites).filter((f) => f.hostId === host.id);
  const toggle = useCollections((s) => s.toggleFavorite);
  const remove = useCollections((s) => s.removeFavorite);
  const path = currentPath(state);
  return (
    <BottomSheet visible={visible} onClose={onClose}>
      <SheetHead title={t('favoritesTitle')} subtitle={t('favoritesSubtitle')} />
      {favs.length === 0 ? (
        <Text muted style={{ fontSize: 13, textAlign: 'center', paddingHorizontal: 20, paddingBottom: 24 }}>{t('noFavoritesYet')}</Text>
      ) : (
        <ScrollView contentContainerStyle={{ paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs }}>
          {favs.map((f) => (
            <Pressable key={f.path} onPress={() => { onClose(); onOpen(f.path); }} accessibilityLabel={f.label}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingHorizontal: Spacing.xs, paddingVertical: Spacing.sm }}>
                <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: `${c.primary}24`, alignItems: 'center', justifyContent: 'center' }}>
                  <Folder size={18} color={c.primary} />
                </View>
                <View style={{ flex: 1 }}>
                  <Text numberOfLines={1} style={{ fontSize: 14, fontFamily: 'Lato_400Regular' }}>{f.label}</Text>
                  <Text numberOfLines={1} muted style={{ fontSize: 11.5 }}>{f.path}</Text>
                </View>
                <Pressable onPress={() => remove(f.hostId, f.path)} pressedScale={0.92} accessibilityLabel={t('removeFavoriteTooltip')} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
                  <Star size={16} color={Brand.amber} />
                </Pressable>
              </View>
            </Pressable>
          ))}
        </ScrollView>
      )}
      <View style={{ padding: Spacing.md }}>
        <Pressable onPress={() => toggle({ hostId: host.id, path, label: folderLabel(path) })} accessibilityLabel={t('addCurrentFolderLabel', { name: folderLabel(path) })} pressedScale={0.97}>
          <View style={{ flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 7, paddingHorizontal: 18, paddingVertical: 11, backgroundColor: c.surfaceContainerHigh, borderWidth: 1, borderColor: c.outlineVariant, borderRadius: Radii.sm }}>
            <Text style={{ fontSize: 13.5, fontFamily: 'Lato_700Bold' }}>{t('addCurrentFolderLabel', { name: folderLabel(path) })}</Text>
            <Plus size={16} color={c.onSurface} />
          </View>
        </Pressable>
      </View>
    </BottomSheet>
  );
}

/** Horizontal chips of favorites, shown at the root of a host (FavoritesPinRow). */
export function FavoritesPinRow({ favorites, onOpen, onRemove }: { favorites: { label: string; path: string; hostId: string }[]; onOpen: (path: string) => void; onRemove: (f: { hostId: string; path: string; label: string }) => void }) {
  const c = useScheme();
  if (favorites.length === 0) return null;
  return (
    <View style={{ height: 56 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm, gap: Spacing.sm }}>
        {favorites.map((f) => (
          <Pressable key={f.path} onPress={() => onOpen(f.path)} onLongPress={() => onRemove(f)} accessibilityLabel={f.label}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.xs, paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm, backgroundColor: c.secondaryContainer, borderRadius: Radii.card }}>
              <Folder size={18} color={c.onSecondaryContainer} />
              <Text variant="labelLarge" color={c.onSecondaryContainer} numberOfLines={1} style={{ maxWidth: 120 }}>{f.label}</Text>
            </View>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}
