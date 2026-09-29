import { useRouter } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, BackHandler, FlatList, RefreshControl, View } from 'react-native';

import type { Entry } from '../../core/api/models';
import { transfers } from '../../core/native';
import type { Host } from '../../core/models/host';
import { Directory, File, Paths } from 'expo-file-system';
import { EmptyState, ErrorRetry, ListingSkeleton, OfflineBanner, Pressable, Text, useDialogs, useToast } from '../../design/components';
import { Plus , Eye, EyeOff } from 'lucide-react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useScheme } from '../../design/theme';
import { Brand, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { isPinned, useCollections } from '../../state/collections';
import { useSettings } from '../../state/settings';
import { humanizeError } from '../pairing/pairingService';
import { BrowseAppBar, SelectionAppBar, SelectionBar, type OverflowAction } from './Bars';
import { CreateMenu } from './CreateMenu';
import { EntryGridCell } from './EntryGridCell';
import { EntryTile } from './EntryTile';
import { FavoritesPinRow, FavoritesSheet, ViewOptionsSheet } from './Sheets';
import { useFileClipboard } from './clipboard';
import { atRoot, currentPath } from './explorerStore';
import { folderLabel } from './paths';
import { useExplorer } from './useExplorer';
import { useFileActions } from './useFileActions';

const GRID_COLUMNS_MIN_WIDTH = 144;

/** Local, non-secret id for a queued transfer journal entry. */
const newTransferId = () => `d${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/** Files tab body for one host root: list/grid browsing, selection, clipboard operations, favorites, bookmarks and pinning. */
export function ExplorerScreen({ host, rootPath, initialPath }: { host: Host; rootPath: string; initialPath?: string }) {
  const c = useScheme();
  const router = useRouter();
  const toast = useToast();
  const dialogs = useDialogs();
  const { ex, state, view, display, hidden, hiddenCount } = useExplorer(host, rootPath);
  const actions = useFileActions(host, ex);
  const collections = useCollections();
  const clip = useFileClipboard((s) => s.clip);
  const density = useSettings((s) => s.state.overrides[host.id]?.density ?? s.state.app.density);
  const [createOpen, setCreateOpen] = useState(false);
  const [viewOpen, setViewOpen] = useState(false);
  const [favOpen, setFavOpen] = useState(false);
  // A tag filter applies only to the folder it was picked in.
  const [tagFilter, setTagFilter] = useState<{ path: string; tag: string } | null>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    if (initialPath && initialPath !== rootPath) ex.jumpTo(initialPath);
  }, [ex, initialPath, rootPath]);

  // Hardware back: clear selection, then go up a folder, then leave the tab.
  useEffect(() => {
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      const s = ex.getState();
      if (s.selected.size > 0) {
        ex.clearSelection();
        return true;
      }
      return ex.popDirectory();
    });
    return () => sub.remove();
  }, [ex]);

  const path = currentPath(state);
  const activeTag = tagFilter?.path === path ? tagFilter.tag : null;
  const setActiveTag = (tag: string | null) => setTagFilter(tag ? { path, tag } : null);
  const isFav = collections.favorites.some((f) => f.hostId === host.id && f.path === path);
  const pinnedHere = isPinned(collections.pins, host.id, path);
  const favPaths = useMemo(() => new Set(collections.favorites.filter((f) => f.hostId === host.id).map((f) => f.path)), [collections.favorites, host.id]);
  const pinPaths = useMemo(() => new Set(collections.pins.filter((p) => p.hostId === host.id).map((p) => p.remotePath)), [collections.pins, host.id]);
  const taggedPaths = useMemo(() => new Set(collections.bookmarks.filter((b) => b.hostId === host.id && activeTag && b.tag === activeTag).map((b) => b.remotePath)), [collections.bookmarks, host.id, activeTag]);
  const tags = useMemo(() => {
    const visible = new Set(display.map((e) => e.path));
    return [...new Set(collections.bookmarks.filter((b) => b.hostId === host.id && b.tag && visible.has(b.remotePath)).map((b) => b.tag!))];
  }, [collections.bookmarks, display, host.id]);
  const entries = activeTag ? display.filter((e) => taggedPaths.has(e.path)) : display;

  const openEntry = useCallback(
    async (e: Entry) => {
      const s = ex.getState();
      if (s.selected.size > 0) return ex.toggleSelect(e.path);
      if (e.isDir) return ex.navigate(e.path);
      router.push({ pathname: '/preview', params: { hostId: host.id, path: e.path, root: rootPath } });
    },
    [ex, host.id, rootPath, router],
  );

  async function toggleFavorite() {
    await collections.toggleFavorite({ hostId: host.id, path, label: folderLabel(path) });
    if (isFav) toast.info(t('removedFavorite', { name: folderLabel(path) }));
    else toast.success(t('addedFavorite', { name: folderLabel(path) }));
  }

  async function togglePin() {
    if (pinnedHere) await collections.unpin(host.id, path);
    else await collections.pin(host.id, path);
  }

  async function bookmark(e: Entry) {
    const already = collections.bookmarks.some((b) => b.hostId === host.id && b.remotePath === e.path);
    if (already) {
      const ok = await dialogs.confirm({ title: 'Remove Bookmark', description: `Remove bookmark for "${e.name}"?`, confirmLabel: 'Remove', cancelLabel: t('cancelButton') });
      if (ok) await collections.removeBookmark(host.id, e.path);
      return;
    }
    const tag = await dialogs.prompt({ title: `Bookmark "${e.name}"`, placeholder: 'Tag (optional)', confirmLabel: 'Save', allowEmpty: true });
    if (tag === null) return;
    await collections.addBookmark({ hostId: host.id, remotePath: e.path, ...(tag ? { tag } : {}) });
  }

  async function downloadSelected() {
    const paths = [...ex.getState().selected];
    try {
      const dir = new Directory(Paths.document, 'downloads');
      dir.create({ idempotent: true, intermediates: true });
      for (const p of paths) {
        const name = p.split(/[/\\]/).pop() ?? 'file';
        const dest = decodeURIComponent(new File(dir, name).uri.replace('file://', ''));
        await transfers.enqueue(newTransferId(), host.id, (await activeAddress()) ?? host.address, p, dest);
      }
      ex.clearSelection();
      toast.success(t('queuedNDownloads', { count: paths.length }));
    } catch (e) {
      toast.error(humanizeError(e));
    }
  }

  const activeAddress = async () => (await import('../../services').then((m) => m.clientForHost(host))).activeAddress;

  const onOverflow = (a: OverflowAction) => {
    switch (a) {
      case 'viewOptions':
        return setViewOpen(true);
      case 'favorites':
        return setFavOpen(true);
      case 'pinOffline':
        return void togglePin();
      case 'transfers':
        return router.navigate('/transfers');
      default:
        toast.info(`${a}: available in a later phase`);
    }
  };

  const columns = Math.max(2, Math.floor((width - Spacing.md) / (GRID_COLUMNS_MIN_WIDTH + Spacing.md)));
  const showMore = state.nextCursor !== null && !activeTag;
  const showHidden = hiddenCount > 0 && !activeTag;
  const favRow = atRoot(state) ? collections.favorites.filter((f) => f.hostId === host.id) : [];
  const multi = state.selected.size > 0;
  const showPaste = clip !== null && clip.paths.length > 0 && clip.hostId === host.id;

  const header = multi ? (
    <SelectionAppBar state={state} onClose={ex.clearSelection} onBatchRename={() => toast.info('Batch rename: available in a later phase')} onSelectAll={() => ex.selectAll(display)} onClearSelection={ex.clearSelection} onInvertSelection={() => ex.invertSelection(display)} />
  ) : (
    <BrowseAppBar
      state={state}
      isFav={isFav}
      isCurrentFolderPinned={pinnedHere}
      onBack={() => ex.popDirectory()}
      onNavigateTo={ex.navigateTo}
      onJumpTo={ex.jumpTo}
      onSearch={() => router.push({ pathname: '/host/[id]/search', params: { id: host.id, path } })}
      onToggleFavorite={toggleFavorite}
      onOpenBookmarks={() => router.push('/bookmarks')}
      onOverflow={onOverflow}
    />
  );

  let body: React.ReactNode;
  if (state.loading && state.entries.length === 0) body = <ListingSkeleton />;
  else if (state.error && state.entries.length === 0) body = <ErrorRetry message={state.error} onRetry={() => ex.refresh()} />;
  else if (entries.length === 0) body = <EmptyState kind={state.entries.length > 0 ? 'noMatches' : 'emptyFolder'} message={state.entries.length > 0 ? t('noMatchesMessage') : t('emptyFolderMessage')} />;
  else {
    const footer = (
      <>
        {showMore && <View style={{ paddingVertical: Spacing.lg, alignItems: 'center' }}>{state.loadingMore ? <ActivityIndicator /> : <View style={{ height: 24 }} />}</View>}
        {showHidden && (
          <Pressable onPress={ex.toggleShowHidden} accessibilityLabel={`${t('nHidden', { count: hiddenCount })} ${state.showHidden ? t('hideLabel') : t('showLabel')}`}>
            <View style={{ flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: Spacing.sm, padding: Spacing.md }}>
              {state.showHidden ? <EyeOff size={18} color={c.onSurfaceVariant} /> : <Eye size={18} color={c.onSurfaceVariant} />}
              <Text variant="bodySmall" muted>{`${t('nHidden', { count: hiddenCount })} · `}</Text>
              <Text variant="bodySmall" color={c.primary} style={{ fontFamily: 'Inter-SemiBold' }}>{state.showHidden ? t('hideLabel') : t('showLabel')}</Text>
            </View>
          </Pressable>
        )}
      </>
    );
    const common = {
      data: entries,
      keyExtractor: (e: Entry) => e.path,
      onEndReached: () => showMore && void ex.loadMore(),
      onEndReachedThreshold: 0.6,
      refreshControl: <RefreshControl refreshing={state.loading} onRefresh={() => ex.refresh()} />,
      ListFooterComponent: footer,
    };
    body = view.gridView ? (
      <FlatList
        key={`grid${columns}`}
        {...common}
        numColumns={columns}
        contentContainerStyle={{ padding: Spacing.md, gap: Spacing.md }}
        columnWrapperStyle={{ gap: Spacing.md }}
        renderItem={({ item }) => (
          <View style={{ flex: 1, opacity: hidden.has(item.path) ? 0.55 : 1 }}>
            <EntryGridCell entry={item} hostId={host.id} selected={state.selected.has(item.path)} multiSelect={multi} isFavorite={favPaths.has(item.path)} isPinned={pinPaths.has(item.path)} onPress={() => openEntry(item)} onLongPress={() => ex.toggleSelect(item.path)} onBookmark={() => bookmark(item)} />
          </View>
        )}
      />
    ) : (
      <FlatList
        key="list"
        {...common}
        contentContainerStyle={{ paddingHorizontal: Spacing.md }}
        ItemSeparatorComponent={() => <View style={{ height: 1, backgroundColor: c.outlineVariant }} />}
        renderItem={({ item }) => (
          <View style={{ opacity: hidden.has(item.path) ? 0.55 : 1 }}>
            <EntryTile entry={item} hostId={host.id} selected={state.selected.has(item.path)} multiSelect={multi} density={density} isFavorite={favPaths.has(item.path)} isPinned={pinPaths.has(item.path)} onPress={() => openEntry(item)} onLongPress={() => ex.toggleSelect(item.path)} onSelect={() => ex.toggleSelect(item.path)} onShowMeta={item.isDir ? () => router.push({ pathname: '/meta', params: { hostId: host.id, path: item.path } }) : undefined} onBookmark={() => bookmark(item)} />
          </View>
        )}
      />
    );
  }

  return (
    <View style={{ flex: 1 }} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
      {header}
      {favRow.length > 0 && <FavoritesPinRow favorites={favRow} onOpen={ex.jumpTo} onRemove={(f) => collections.removeFavorite(f.hostId, f.path)} />}
      {tags.length > 0 && <TagChips tags={tags} active={activeTag} onChange={setActiveTag} />}
      {state.offline && <OfflineBanner text={t('offlineBannerText')} />}
      <View style={{ flex: 1 }}>{body}</View>
      {multi ? (
        <SelectionBar count={state.selected.size} onCut={actions.cutSelection} onCopy={actions.copySelection} onCompress={actions.compressSelected} onDownload={downloadSelected} onDelete={actions.confirmDelete} />
      ) : (
        <View style={{ position: 'absolute', right: 16, bottom: 16 }}>
          <Pressable onPress={() => setCreateOpen(true)} pressedScale={0.92} accessibilityLabel="Create">
            <LinearGradient colors={[Brand.accent, Brand.accentDim]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={{ width: 52, height: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center', shadowColor: Brand.accent, shadowOpacity: 0.4, shadowRadius: 20, shadowOffset: { width: 0, height: 6 }, elevation: 8 }}>
              <Plus size={22} color="#fff" />
            </LinearGradient>
          </Pressable>
        </View>
      )}
      <CreateMenu
        visible={createOpen}
        onClose={() => setCreateOpen(false)}
        onNewFolder={() => void actions.createNamed(true)}
        onNewFile={() => void actions.createNamed(false)}
        onPaste={showPaste ? () => void actions.paste() : undefined}
        pasteLabel={showPaste ? t('pasteNItems', { count: clip!.paths.length }) : undefined}
      />
      <ViewOptionsSheet visible={viewOpen} onClose={() => setViewOpen(false)} gridView={view.gridView} density={view.density} sort={view.sort} showHidden={state.showHidden} hiddenCount={hiddenCount} onToggleShowHidden={ex.toggleShowHidden} />
      <FavoritesSheet visible={favOpen} onClose={() => setFavOpen(false)} host={host} state={state} onOpen={ex.jumpTo} />
    </View>
  );
}

function TagChips({ tags, active, onChange }: { tags: string[]; active: string | null; onChange: (t: string | null) => void }) {
  const c = useScheme();
  const chip = (label: string, on: boolean, onPress: () => void) => (
    <Pressable key={label} onPress={onPress} accessibilityLabel={label} accessibilityState={{ selected: on }}>
      <View style={{ paddingHorizontal: 12, paddingVertical: 6, borderRadius: 8, borderWidth: 1, borderColor: c.outlineVariant, backgroundColor: on ? `${c.primary}2E` : 'transparent' }}>
        <Text style={{ fontSize: 12 }} color={on ? c.primary : c.onSurfaceVariant}>{label}</Text>
      </View>
    </Pressable>
  );
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.xs, paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs }}>
      {active && chip('All', false, () => onChange(null))}
      {tags.map((tag) => chip(tag, active === tag, () => onChange(active === tag ? null : tag)))}
    </View>
  );
}
