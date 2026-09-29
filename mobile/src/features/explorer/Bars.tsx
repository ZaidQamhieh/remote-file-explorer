import { Archive, ArrowLeft, Bookmark, CheckSquare, Copy, Download, FilePen, MoreVertical, Pin, Scissors, Search, Square, Star, Terminal, Trash2, X, History, PieChart, Replace, FileUp, SlidersHorizontal } from 'lucide-react-native';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { ExplorerState } from './explorerStore';
import { atRoot, currentPath } from './explorerStore';
import { AppBarIconButton, Menu, Pressable, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { BreadcrumbBar } from './Breadcrumb';
import { folderLabel } from './paths';

export type OverflowAction = 'commandPalette' | 'viewOptions' | 'favorites' | 'transfers' | 'trash' | 'recent' | 'storageByType' | 'dupFinder' | 'pinOffline';

/** Browse app bar: back, folder title, breadcrumb row, search / bookmarks / favorite star and the overflow menu. */
export function BrowseAppBar({
  state, isFav, isCurrentFolderPinned, onBack, onNavigateTo, onJumpTo, onSearch, onToggleFavorite, onOpenBookmarks, onOverflow,
}: {
  state: ExplorerState; isFav: boolean; isCurrentFolderPinned: boolean; onBack: () => void; onNavigateTo: (i: number) => void; onJumpTo: (p: string) => void;
  onSearch: () => void; onToggleFavorite: () => void; onOpenBookmarks: () => void; onOverflow: (a: OverflowAction) => void;
}) {
  const c = useScheme();
  const insets = useSafeAreaInsets();
  const item = (label: string, icon: React.ReactNode, action: OverflowAction) => ({ label, icon, onPress: () => onOverflow(action) });
  const ic = (I: typeof Search) => <I size={16} color={c.onSurface} />;
  return (
    <View style={{ paddingTop: insets.top, backgroundColor: c.surface }}>
      <View style={{ height: 56, flexDirection: 'row', alignItems: 'center', paddingLeft: atRoot(state) ? 16 : 4, paddingRight: 4 }}>
        {!atRoot(state) && (
          <AppBarIconButton label="Back" onPress={onBack}>
            <ArrowLeft size={22} color={c.onSurface} />
          </AppBarIconButton>
        )}
        <Text variant="screenTitle" numberOfLines={1} style={{ flex: 1 }} accessibilityRole="header">{folderLabel(currentPath(state))}</Text>
        <AppBarIconButton label={t('searchTooltip')} onPress={onSearch}><Search size={19} color={c.onSurfaceVariant} /></AppBarIconButton>
        <AppBarIconButton label="Bookmarks" onPress={onOpenBookmarks}><Bookmark size={19} color={c.onSurfaceVariant} /></AppBarIconButton>
        <AppBarIconButton label={isFav ? t('removeFavoriteTooltip') : t('favoriteFolderTooltip')} onPress={onToggleFavorite}><Star size={19} color={isFav ? Brand.amber : c.onSurfaceVariant} /></AppBarIconButton>
        <Menu
          accessibilityLabel={t('moreTooltip')}
          trigger={<MoreVertical size={20} color={c.onSurfaceVariant} />}
          items={[
            item('Command Palette', ic(Terminal), 'commandPalette'),
            item(t('viewOptionsTitle'), ic(SlidersHorizontal), 'viewOptions'),
            item(t('favoritesTitle'), ic(Bookmark), 'favorites'),
            item(t('transfersMenuItem'), ic(FileUp), 'transfers'),
            item(t('trashTitle'), ic(Trash2), 'trash'),
            item(t('recentTitle'), ic(History), 'recent'),
            item(t('storageByTypeTitle'), ic(PieChart), 'storageByType'),
            item('Find Duplicates', ic(Replace), 'dupFinder'),
            item(isCurrentFolderPinned ? 'Unpin offline' : 'Pin offline', ic(Pin), 'pinOffline'),
          ]}
        />
      </View>
      <View style={{ paddingLeft: Spacing.md, paddingBottom: Spacing.xs, height: 44 }}>
        <BreadcrumbBar pathStack={state.pathStack} onNavigateTo={onNavigateTo} onJumpTo={onJumpTo} />
      </View>
    </View>
  );
}

/** Contextual app bar while items are selected. */
export function SelectionAppBar({
  state, onClose, onBatchRename, onSelectAll, onClearSelection, onInvertSelection, onBookmark,
}: { state: ExplorerState; onClose: () => void; onBatchRename: () => void; onSelectAll: () => void; onClearSelection: () => void; onInvertSelection: () => void; onBookmark: () => void }) {
  const c = useScheme();
  const insets = useSafeAreaInsets();
  const all = state.entries.length > 0 && state.selected.size === state.entries.length;
  return (
    <View style={{ paddingTop: insets.top, backgroundColor: c.surface }}>
      <View style={{ height: 56, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 4 }}>
        <AppBarIconButton label={t('clearSelectionTooltip')} onPress={onClose}><X size={19} color={c.onSurfaceVariant} /></AppBarIconButton>
        <Text variant="screenTitle" style={{ flex: 1 }} accessibilityRole="header">{t('nSelected', { count: state.selected.size })}</Text>
        {state.selected.size === 1 && (
          <AppBarIconButton label="Bookmark" onPress={onBookmark}><Bookmark size={19} color={c.onSurfaceVariant} /></AppBarIconButton>
        )}
        <AppBarIconButton label={t('batchRenameTooltip')} onPress={onBatchRename}><FilePen size={19} color={c.onSurfaceVariant} /></AppBarIconButton>
        <AppBarIconButton label={all ? t('deselectAllTooltip') : t('selectAllTooltip')} onPress={all ? onClearSelection : onSelectAll}>
          {all ? <Square size={19} color={c.onSurfaceVariant} /> : <CheckSquare size={19} color={c.onSurfaceVariant} />}
        </AppBarIconButton>
        <AppBarIconButton label={t('invertSelectionTooltip')} onPress={onInvertSelection}><Replace size={19} color={c.onSurfaceVariant} /></AppBarIconButton>
      </View>
      <View style={{ height: 44 }} />
    </View>
  );
}

function BarAction({ label, onPress, children }: { label: string; onPress: () => void; children: React.ReactNode }) {
  return (
    <Pressable onPress={onPress} pressedScale={0.92} accessibilityLabel={label} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
      {children}
    </Pressable>
  );
}

/** Bottom action bar for the current selection: cut, copy, compress, download, delete. */
export function SelectionBar({ count, onCut, onCopy, onCompress, onDownload, onDelete }: { count: number; onCut: () => void; onCopy: () => void; onCompress: () => void; onDownload: () => void; onDelete: () => void }) {
  const c = useScheme();
  // Sits above the tab bar, which already owns the bottom inset.
  return (
    <View style={{ backgroundColor: c.surfaceContainerHigh, borderTopWidth: 1, borderColor: c.outlineVariant }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 14, paddingVertical: 10 }}>
        <Text style={{ fontSize: 12.5 }} muted>{t('nSelected', { count })}</Text>
        <View style={{ flexDirection: 'row' }}>
          <BarAction label={t('cutButton')} onPress={onCut}><Scissors size={22} color={c.onSurfaceVariant} /></BarAction>
          <BarAction label={t('copyButton')} onPress={onCopy}><Copy size={22} color={c.onSurfaceVariant} /></BarAction>
          <BarAction label={t('compressButton')} onPress={onCompress}><Archive size={22} color={c.onSurfaceVariant} /></BarAction>
          <BarAction label={t('downloadButton')} onPress={onDownload}><Download size={22} color={c.onSurfaceVariant} /></BarAction>
          <BarAction label={t('deleteButton')} onPress={onDelete}><Trash2 size={22} color={c.error} /></BarAction>
        </View>
      </View>
    </View>
  );
}
