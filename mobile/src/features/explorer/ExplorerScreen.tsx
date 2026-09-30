import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, BackHandler, FlatList, RefreshControl, View } from 'react-native';

import { can, type Entry } from '../../core/api/models';
import type { Host } from '../../core/models/host';
import { ActionFooter, EmptyState, type FooterButton, ErrorRetry, ListingSkeleton, OfflineBanner, Pressable, Text, useDialogs, useToast } from '../../design/components';
import { ClipboardPaste, Plus, Upload, Eye, EyeOff, Bookmark, FileUp, History, LayoutGrid, PieChart, RefreshCw, Replace, Route, Search, SlidersHorizontal, Trash2 } from 'lucide-react-native';
import { useScheme } from '../../design/theme';
import { Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { isPinned, useCollections } from '../../state/collections';
import { useSettings } from '../../state/settings';
import { offlineDeps } from '../offline/offlineDeps';
import { MAX_OFFLINE_FILE_BYTES, precachePinnedFolder } from '../offline/offlineBodies';
import { markPinSynced, pinSyncPending, refreshPinnedFolders } from '../offline/pinSync';
import { humanizeError } from '../pairing/pairingService';
import { fetchPreviewFile } from '../preview/previewFile';
import { isPreviewable, previewableSiblings } from '../preview/previewKind';
import { usePreviewSession } from '../preview/session';
import { enqueueDownloads } from '../transfers/enqueueDownloads';
import { BrowseAppBar, SelectionAppBar, SelectionBar, type OverflowAction } from './Bars';
import { BatchRenameSheet } from './BatchRenameSheet';
import { CommandPalette, type PaletteAction } from './CommandPalette';
import { CreateMenu } from './CreateMenu';
import { FOOTER_LIST_PADDING, footerActions } from './footerLogic';
import { EntryGridCell } from './EntryGridCell';
import { EntryTile } from './EntryTile';
import { MetaSheet } from './MetaSheet';
import { PeekSheet } from './PeekSheet';
import { FavoritesPinRow, FavoritesSheet, ViewOptionsSheet } from './Sheets';
import { useFileClipboard } from './clipboard';
import { normalizeTypedPath } from './paletteLogic';
import { transfers } from '../../core/native';
import { clientForHost, listingCache } from '../../services';
import { atRoot, currentPath } from './explorerStore';
import { basenameOf, folderLabel, parentDirOf } from './paths';
import { useExplorer } from './useExplorer';
import { useFileActions } from './useFileActions';
import { useFileCapabilities } from './useFileCapabilities';

const GRID_COLUMNS_MIN_WIDTH = 144;

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
  const caps = useFileCapabilities(host);
  const [viewOpen, setViewOpen] = useState(false);
  const [favOpen, setFavOpen] = useState(false);
  const [renameOpen, setRenameOpen] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [metaEntry, setMetaEntry] = useState<Entry | null>(null);
  const [peekEntry, setPeekEntry] = useState<Entry | null>(null);
  // A tag filter applies only to the folder it was picked in.
  const [tagFilter, setTagFilter] = useState<{ path: string; tag: string } | null>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    if (initialPath && initialPath !== rootPath) ex.jumpTo(initialPath);
  }, [ex, initialPath, rootPath]);

  // Once per launch, while the host is reachable, bring its pinned folders up to date in the background.
  const online = !state.loading && !state.error;
  useEffect(() => {
    if (!online || !pinSyncPending(host.id)) return;
    const paths = useCollections.getState().pins.filter((p) => p.hostId === host.id).map((p) => p.remotePath);
    if (paths.length === 0) return markPinSynced(host.id);
    void (async () => {
      const client = await clientForHost(host);
      const result = await refreshPinnedFolders(paths, {
        listAll: async (path) => {
          const all: Entry[] = [];
          let cursor: string | undefined;
          do {
            const page = await client.list(path, { cursor });
            all.push(...page.entries);
            cursor = page.nextCursor;
          } while (cursor);
          return all;
        },
        storeListing: (path, entries) => listingCache.put(host.id, path, entries),
        precache: (entries) => precachePinnedFolder(offlineDeps, host, entries, (h, e) => fetchPreviewFile(h, e, MAX_OFFLINE_FILE_BYTES)),
      });
      if (result.folders > 0) markPinSynced(host.id);
    })().catch(() => {});
  }, [online, host]);

  // A finished upload into the folder on screen shows up without a manual refresh.
  useEffect(
    () =>
      transfers.subscribe((r) => {
        if (r.direction === 'UPLOAD' && r.state === 'DONE' && r.hostId === host.id && parentDirOf(r.remotePath) === currentPath(ex.getState())) void ex.refresh();
      }),
    [ex, host.id],
  );

  // Hardware back: clear selection, then go up a folder, then leave the tab.
  // Only while this screen is focused, so a pushed screen (preview, meta) gets Back first.
  useFocusEffect(
    useCallback(() => {
      const sub = BackHandler.addEventListener('hardwareBackPress', () => {
        const s = ex.getState();
        if (s.selected.size > 0) {
          ex.clearSelection();
          return true;
        }
        return ex.popDirectory();
      });
      return () => sub.remove();
    }, [ex]),
  );

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

  const openPreview = usePreviewSession((x) => x.open);
  const startPreview = useCallback(
    (e: Entry) => {
      // Swipe order follows what is on screen (sorted, visibility- and tag-filtered).
      const sib = previewableSiblings(entries, e);
      const onChanged = () => void ex.refresh();
      openPreview(sib.index >= 0 ? { host, entries: sib.entries, index: sib.index, onChanged } : { host, entries: [e], index: 0, onChanged });
      router.push('/preview');
    },
    [ex, host, router, openPreview, entries],
  );
  const openEntry = useCallback(
    async (e: Entry) => {
      const s = ex.getState();
      if (s.selected.size > 0) return ex.toggleSelect(e.path);
      if (e.isDir) return ex.navigate(e.path);
      // Files without a previewer still have actions (download, extract, share link, details).
      if (!isPreviewable(e)) return setMetaEntry(e);
      startPreview(e);
    },
    [ex, startPreview],
  );

  async function toggleFavorite() {
    await collections.toggleFavorite({ hostId: host.id, path, label: folderLabel(path) });
    if (isFav) toast.info(t('removedFavorite', { name: folderLabel(path) }));
    else toast.success(t('addedFavorite', { name: folderLabel(path) }));
  }

  async function togglePin() {
    if (pinnedHere) return void (await collections.unpin(host.id, path));
    await collections.pin(host.id, path);
    // Fetch the folder's files in the background so they open offline (each fetch stores its encrypted copy).
    void precachePinnedFolder(offlineDeps, host, ex.getState().entries, (h, e) => fetchPreviewFile(h, e, MAX_OFFLINE_FILE_BYTES));
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

  function bookmarkSelected() {
    const [only] = ex.getState().selected;
    const entry = state.entries.find((e) => e.path === only);
    if (!entry) return;
    ex.clearSelection();
    void bookmark(entry);
  }

  function detailsOfSelected() {
    const [only] = ex.getState().selected;
    const entry = state.entries.find((e) => e.path === only);
    if (!entry) return;
    ex.clearSelection();
    setMetaEntry(entry);
  }

  async function downloadSelected() {
    const paths = [...ex.getState().selected];
    try {
      await enqueueDownloads(host, paths);
      ex.clearSelection();
      toast.success(t('queuedNDownloads', { count: paths.length }));
    } catch (e) {
      toast.error(humanizeError(e));
    }
  }


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
      case 'trash':
        return router.push('/trash');
      case 'recent':
        return router.push('/recent');
      case 'dupFinder':
        return router.push({ pathname: '/dups', params: { path } });
      case 'storageByType':
        return router.push({ pathname: '/host/[id]/types', params: { id: host.id, path } });
      case 'commandPalette':
        return setPaletteOpen(true);
      default:
        toast.info(`${a}: available in a later phase`);
    }
  };

  const goToPath = async () => {
    const typed = await dialogs.prompt({ title: t('goToPathTitle'), placeholder: '/path/to/folder', confirmLabel: t('goButton'), mono: true });
    const target = typed === null ? null : normalizeTypedPath(typed);
    if (target) ex.jumpTo(target);
  };
  const paletteActions: PaletteAction[] = [
    { id: 'search', label: 'Search', icon: Search, run: () => router.push({ pathname: '/host/[id]/search', params: { id: host.id, path } }) },
    { id: 'refresh', label: 'Refresh', icon: RefreshCw, run: () => ex.refresh() },
    { id: 'grid', label: 'Toggle Grid/List', icon: LayoutGrid, run: () => void useSettings.getState().setApp('gridView', !view.gridView) },
    { id: 'view', label: t('viewOptionsTitle'), icon: SlidersHorizontal, run: () => setViewOpen(true) },
    { id: 'favorites', label: t('favoritesTitle'), icon: Bookmark, run: () => setFavOpen(true) },
    { id: 'transfers', label: t('transfersMenuItem'), icon: FileUp, run: () => router.navigate('/transfers') },
    { id: 'trash', label: t('trashTitle'), icon: Trash2, run: () => router.push('/trash') },
    { id: 'recent', label: t('recentTitle'), icon: History, run: () => router.push('/recent') },
    { id: 'types', label: t('storageByTypeTitle'), icon: PieChart, run: () => router.push({ pathname: '/host/[id]/types', params: { id: host.id, path } }) },
    { id: 'dups', label: 'Find Duplicates', icon: Replace, run: () => router.push({ pathname: '/dups', params: { path } }) },
    { id: 'goto', label: 'Navigate to Path', icon: Route, run: () => void goToPath() },
  ];

  const columns = Math.max(2, Math.floor((width - Spacing.md) / (GRID_COLUMNS_MIN_WIDTH + Spacing.md)));
  const showMore = state.nextCursor !== null && !activeTag;
  const showHidden = hiddenCount > 0 && !activeTag;
  const favRow = atRoot(state) ? collections.favorites.filter((f) => f.hostId === host.id) : [];
  const multi = state.selected.size > 0;
  const selectedPaths = useMemo(() => [...state.selected], [state.selected]);
  const showPaste = clip !== null && clip.paths.length > 0 && clip.hostId === host.id && can(caps, 'modify');
  const footerButtons: FooterButton[] = footerActions({ caps, showPaste }).map((a) => ({
    key: a.key,
    primary: a.primary,
    label: a.key === 'paste' ? t('pasteNItems', { count: clip?.paths.length ?? 0 }) : a.key === 'upload' ? t('uploadFileTooltip') : t('newButton'),
    onPress: a.key === 'paste' ? () => void actions.paste() : a.key === 'upload' ? () => void actions.upload() : () => setCreateOpen(true),
    renderIcon: (k: string) => (a.key === 'paste' ? <ClipboardPaste size={18} color={k} /> : a.key === 'upload' ? <Upload size={18} color={k} /> : <Plus size={18} color={k} />),
  }));
  const listBottom = !multi && footerButtons.length > 0 ? FOOTER_LIST_PADDING : 0;

  const header = multi ? (
    <SelectionAppBar state={state} canModify={can(caps, 'modify')} onClose={ex.clearSelection} onBatchRename={() => setRenameOpen(true)} onSelectAll={() => ex.selectAll(display)} onClearSelection={ex.clearSelection} onInvertSelection={() => ex.invertSelection(display)} onBookmark={bookmarkSelected} onDetails={detailsOfSelected} />
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
        contentContainerStyle={{ padding: Spacing.md, paddingBottom: Spacing.md + listBottom, gap: Spacing.md }}
        columnWrapperStyle={{ gap: Spacing.md }}
        renderItem={({ item }) => (
          <View style={{ flex: 1, opacity: hidden.has(item.path) ? 0.55 : 1 }}>
            <EntryGridCell entry={item} hostId={host.id} selected={state.selected.has(item.path)} multiSelect={multi} isFavorite={favPaths.has(item.path)} isPinned={pinPaths.has(item.path)} onPress={() => openEntry(item)} onLongPress={() => ex.toggleSelect(item.path)} onPeek={isPreviewable(item) ? () => setPeekEntry(item) : undefined} />
          </View>
        )}
      />
    ) : (
      <FlatList
        key="list"
        {...common}
        contentContainerStyle={{ paddingHorizontal: Spacing.md, paddingBottom: listBottom }}
        ItemSeparatorComponent={() => <View style={{ height: 1, backgroundColor: c.outlineVariant }} />}
        renderItem={({ item }) => (
          <View style={{ opacity: hidden.has(item.path) ? 0.55 : 1 }}>
            <EntryTile entry={item} hostId={host.id} selected={state.selected.has(item.path)} multiSelect={multi} density={density} isFavorite={favPaths.has(item.path)} isPinned={pinPaths.has(item.path)} onPress={() => openEntry(item)} onLongPress={() => ex.toggleSelect(item.path)} onPeek={isPreviewable(item) ? () => setPeekEntry(item) : undefined} onSelect={() => ex.toggleSelect(item.path)} onShowMeta={item.isDir ? () => setMetaEntry(item) : undefined} />
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
        <SelectionBar count={state.selected.size} onCut={actions.cutSelection} onCopy={actions.copySelection} onCompress={actions.compressSelected} onDownload={downloadSelected} onDelete={actions.confirmDelete} caps={caps} />
      ) : (
        <ActionFooter buttons={footerButtons} />
      )}
      <CreateMenu
        visible={createOpen}
        onClose={() => setCreateOpen(false)}
        onNewFolder={() => void actions.createNamed(true)}
        onNewFile={() => void actions.createNamed(false)}
        onUpload={can(caps, 'upload') ? () => void actions.upload() : undefined}
        onPaste={showPaste ? () => void actions.paste() : undefined}
        pasteLabel={showPaste ? t('pasteNItems', { count: clip!.paths.length }) : undefined}
        canModify={can(caps, 'modify')}
      />
      <ViewOptionsSheet visible={viewOpen} onClose={() => setViewOpen(false)} gridView={view.gridView} density={view.density} sort={view.sort} showHidden={state.showHidden} hiddenCount={hiddenCount} onToggleShowHidden={ex.toggleShowHidden} />
      <CommandPalette visible={paletteOpen} actions={paletteActions} onClose={() => setPaletteOpen(false)} />
      <BatchRenameSheet
        visible={renameOpen}
        names={selectedPaths.map(basenameOf)}
        onClose={() => setRenameOpen(false)}
        onApply={(newNames) => {
          setRenameOpen(false);
          void actions.applyBatchRename(selectedPaths, newNames);
        }}
      />
      {peekEntry && <PeekSheet host={host} entry={peekEntry} onClose={() => setPeekEntry(null)} />}
      {metaEntry && <MetaSheet visible host={host} entry={metaEntry} onClose={() => setMetaEntry(null)} onChanged={() => void ex.refresh()} onPreview={startPreview} />}
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
