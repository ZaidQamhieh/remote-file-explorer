import { Stack } from 'expo-router';
import { ArchiveRestore, File as FileIcon, Folder, Info, Trash2 } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, RefreshControl, View } from 'react-native';

import type { TrashEntry } from '../core/api/models';
import { formatRelative, formatSize } from '../core/format';
import { AppBarIconButton, EmptyState, ErrorRetry, GhostBlockButton, Pressable, Text, useDialogs, useToast } from '../design/components';
import { useScheme } from '../design/theme';
import { FontFamily, Radii, Spacing } from '../design/tokens';
import { explorerFor } from '../features/explorer/useExplorer';
import { humanizeError } from '../features/pairing/pairingService';
import { t } from '../i18n';
import { clientForHost } from '../services';
import { useActiveHost } from '../state/activeHost';

/** The agent's trash: restore to the original location, delete one item for good, or empty everything. A restore refreshes the open folder. */
export default function Trash() {
  const c = useScheme();
  const toast = useToast();
  const dialogs = useDialogs();
  const active = useActiveHost((s) => s.active);
  const [items, setItems] = useState<TrashEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const activeHost = active?.host;
  const fetchItems = useCallback(async (): Promise<{ items: TrashEntry[] } | { error: string }> => {
    if (!activeHost) return { items: [] };
    try {
      return { items: await (await clientForHost(activeHost)).listTrash() };
    } catch (e) {
      return { error: humanizeError(e) };
    }
  }, [activeHost]);
  const apply = useCallback((r: { items: TrashEntry[] } | { error: string }) => {
    if ('items' in r) {
      setItems(r.items);
      setError(null);
    } else setError(r.error);
    setLoading(false);
  }, []);
  const load = useCallback(async () => {
    setLoading(true);
    apply(await fetchItems());
  }, [apply, fetchItems]);

  useEffect(() => {
    let live = true;
    void fetchItems().then((r) => live && apply(r));
    return () => {
      live = false;
    };
  }, [apply, fetchItems]);

  if (!active) return null;
  const { host, rootPath } = active;
  const refreshFolder = () => {
    if (rootPath) void explorerFor(host, rootPath, () => clientForHost(host)).refresh();
  };

  async function restore(item: TrashEntry) {
    try {
      await (await clientForHost(host)).restoreTrash([item.id]);
      refreshFolder();
      toast.success(t('restoredItem', { name: item.name }));
      await load();
    } catch (e) {
      toast.error(t('restoreFailed', { error: humanizeError(e) }));
    }
  }

  async function deleteForever(item: TrashEntry) {
    const ok = await dialogs.confirm({ title: t('deleteForeverTitle'), description: t('deleteForeverConfirm', { name: item.name }), confirmLabel: t('deleteForeverButton'), cancelLabel: t('cancelButton'), destructive: true });
    if (!ok) return;
    try {
      await (await clientForHost(host)).emptyTrash([item.id]);
      toast.success(t('deletedForever', { name: item.name }));
      await load();
    } catch (e) {
      toast.error(t('deleteFailed', { error: humanizeError(e) }));
    }
  }

  async function emptyAll() {
    const ok = await dialogs.confirm({ title: t('emptyTrashTitle'), description: t('emptyTrashBody', { count: items?.length ?? 0 }), confirmLabel: t('emptyTrashTooltip'), cancelLabel: t('cancelButton'), destructive: true });
    if (!ok) return;
    try {
      await (await clientForHost(host)).emptyTrash();
      toast.success(t('trashEmptied'));
      await load();
    } catch (e) {
      toast.error(t('emptyFailed', { error: humanizeError(e) }));
    }
  }

  const hasItems = items !== null && items.length > 0;
  let body: React.ReactNode;
  if (loading && items === null) body = <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator /></View>;
  else if (error && items === null) body = <ErrorRetry message={error} onRetry={load} />;
  else if (!hasItems) body = <EmptyState message={`${t('trashIsEmpty')}\n${t('trashEmptySubtitle')}`} />;
  else {
    body = (
      <FlatList
        data={items}
        keyExtractor={(i) => i.id}
        refreshControl={<RefreshControl refreshing={loading} onRefresh={load} />}
        contentContainerStyle={{ paddingVertical: Spacing.md }}
        ListHeaderComponent={
          <View style={{ marginHorizontal: Spacing.md, marginBottom: Spacing.sm, flexDirection: 'row', gap: Spacing.sm, padding: 14, borderRadius: Radii.card, borderWidth: 1, borderColor: c.outlineVariant, backgroundColor: c.surfaceContainerHigh }}>
            <Info size={16} color={c.onSurfaceVariant} style={{ marginTop: 2 }} />
            <Text variant="bodySmall" muted style={{ flex: 1 }}>{"Items stay here until you delete them yourself — RFE doesn't auto-purge trash."}</Text>
          </View>
        }
        ItemSeparatorComponent={() => <View style={{ height: 1, marginLeft: Spacing.md, backgroundColor: c.outlineVariant }} />}
        ListFooterComponent={
          <View style={{ padding: Spacing.md }}>
            <GhostBlockButton label={t('emptyTrashTooltip')} onPress={emptyAll} />
          </View>
        }
        renderItem={({ item }) => <TrashRow item={item} onRestore={() => restore(item)} onDelete={() => deleteForever(item)} />}
      />
    );
  }

  return (
    <View style={{ flex: 1 }}>
      <Stack.Screen
        options={{
          title: t('trashTitle'),
          headerRight: () => (hasItems ? <AppBarIconButton label={t('emptyTrashTooltip')} onPress={emptyAll}><Trash2 size={19} color={c.error} /></AppBarIconButton> : null),
        }}
      />
      {body}
    </View>
  );
}

function TrashRow({ item, onRestore, onDelete }: { item: TrashEntry; onRestore: () => void; onDelete: () => void }) {
  const c = useScheme();
  const Icon = item.isDir ? Folder : FileIcon;
  const subtitle = [item.originalPath, item.deletedAt ? t('deletedRelative', { relative: formatRelative(new Date(item.deletedAt)) }) : null, !item.isDir && item.size != null ? formatSize(item.size) : null].filter(Boolean).join(' · ');
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm, opacity: 0.85 }}>
      <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: c.surfaceContainerHighest, alignItems: 'center', justifyContent: 'center' }}>
        <Icon size={18} color={c.onSurfaceVariant} />
      </View>
      <View style={{ flex: 1 }}>
        <Text numberOfLines={1} style={{ fontSize: 14, fontFamily: FontFamily.medium }}>{item.name}</Text>
        <Text numberOfLines={2} muted style={{ fontSize: 11.5 }}>{subtitle}</Text>
      </View>
      <Pressable onPress={onRestore} pressedScale={0.92} accessibilityLabel={`${t('restoreButton')} ${item.name}`} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
        <ArchiveRestore size={18} color={c.onSurfaceVariant} />
      </Pressable>
      <Pressable onPress={onDelete} pressedScale={0.92} accessibilityLabel={`${t('deleteForeverButton')} ${item.name}`} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
        <Trash2 size={18} color={c.error} />
      </Pressable>
    </View>
  );
}
