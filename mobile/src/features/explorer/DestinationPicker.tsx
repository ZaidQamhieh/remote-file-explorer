import { ChevronRight, Folder, FolderPlus } from 'lucide-react-native';
import { useEffect, useMemo } from 'react';
import { ActivityIndicator, FlatList, View } from 'react-native';
import { useStore } from 'zustand';

import type { Host } from '../../core/models/host';
import { BottomSheet, Button, EmptyState, ErrorRetry, GhostBlockButton, ListingSkeleton, Pressable, SheetHead, Text, useDialogs, useToast } from '../../design/components';
import { useScheme } from '../../design/theme';
import { FontFamily, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { clientForHost } from '../../services';
import { useResolvedVisibility } from '../../state/settings';
import { humanizeError } from '../pairing/pairingService';
import { BreadcrumbBar } from './Breadcrumb';
import { createDestinationPicker, pickerPath } from './destinationPicker';

/**
 * Folder browser sheet for choosing where Move/Copy/Save goes. `onPick` gets the current directory; the
 * confirm button stays disabled while it is `originPath` (moving or copying into the same folder is a no-op).
 */
export function DestinationPicker({ visible, host, originPath, title, confirmLabel, onPick, onClose }: { visible: boolean; host: Host; originPath: string; title: string; confirmLabel: string; onPick: (dir: string) => void; onClose: () => void }) {
  const c = useScheme();
  const toast = useToast();
  const dialogs = useDialogs();
  const vis = useResolvedVisibility(host.id);
  const picker = useMemo(
    () => createDestinationPicker({ hostId: host.id, startPath: originPath, getClient: () => clientForHost(host), visibility: () => vis, humanize: humanizeError }),
    [host, originPath, vis],
  );
  const state = useStore(picker);

  useEffect(() => {
    if (visible) void picker.load();
  }, [visible, picker]);

  async function newFolder() {
    const name = await dialogs.prompt({ title: t('newFolderButton'), placeholder: t('nameHint'), confirmLabel: t('createButton') });
    if (!name) return;
    try {
      await picker.createFolder(name);
      toast.success(t('createdName', { name }));
    } catch (e) {
      toast.error(t('createFailed', { name, error: humanizeError(e) }));
    }
  }

  const here = pickerPath(state);
  let body: React.ReactNode;
  if (state.loading && state.folders.length === 0) body = <ListingSkeleton rows={5} />;
  else if (state.error && state.folders.length === 0) body = <ErrorRetry message={state.error} onRetry={() => void picker.load()} />;
  else if (state.folders.length === 0) body = <EmptyState message={t('emptyFolderMessage')} />;
  else {
    body = (
      <FlatList
        data={state.folders}
        keyExtractor={(f) => f.path}
        onEndReached={() => void picker.loadMore()}
        onEndReachedThreshold={0.6}
        ListFooterComponent={state.loadingMore ? <ActivityIndicator style={{ padding: Spacing.lg }} /> : null}
        renderItem={({ item }) => (
          <Pressable onPress={() => picker.navigate(item.path)} accessibilityLabel={item.name}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingHorizontal: Spacing.md, paddingVertical: 11, borderBottomWidth: 1, borderColor: c.outlineVariant }}>
              <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: `${c.primary}24`, alignItems: 'center', justifyContent: 'center' }}>
                <Folder size={18} color={c.primary} />
              </View>
              <Text numberOfLines={1} style={{ flex: 1, fontSize: 14, fontFamily: FontFamily.medium }}>{item.name}</Text>
              <ChevronRight size={16} color={c.onSurfaceVariant} />
            </View>
          </Pressable>
        )}
      />
    );
  }

  return (
    <BottomSheet visible={visible} onClose={onClose} maxHeight="90%">
      <View style={{ height: 560, maxHeight: '100%' }}>
        <SheetHead title={title} subtitle={originPath} />
        <View style={{ paddingHorizontal: Spacing.md, height: 44 }}>
          <BreadcrumbBar pathStack={state.pathStack} onNavigateTo={picker.navigateTo} />
        </View>
        <View style={{ height: 1, backgroundColor: c.outlineVariant }} />
        <View style={{ flex: 1 }}>{body}</View>
        <View style={{ padding: Spacing.md, gap: Spacing.sm }}>
          <GhostBlockButton label={t('newFolderButton')} icon={<FolderPlus size={16} color={c.onSurface} />} onPress={newFolder} />
          <Button label={confirmLabel} disabled={here === originPath} onPress={() => onPick(here)} />
        </View>
      </View>
    </BottomSheet>
  );
}
