import { Stack, useRouter } from 'expo-router';
import { Bookmark as BookmarkIcon } from 'lucide-react-native';
import { useEffect, useState } from 'react';
import { ScrollView, View } from 'react-native';

import type { Host } from '../core/models/host';
import type { Bookmark } from '../core/storage/collections';
import { Pressable, SectionLabel, Text, useDialogs } from '../design/components';
import { useScheme } from '../design/theme';
import { FontFamily, Radii, Spacing } from '../design/tokens';
import { t } from '../i18n';
import { hostStore } from '../services';
import { useActiveHost } from '../state/activeHost';
import { useCollections } from '../state/collections';

/** All bookmarks grouped by host. Tap opens the Files tab at that path; long-press removes (with confirmation). */
export default function Bookmarks() {
  const c = useScheme();
  const router = useRouter();
  const dialogs = useDialogs();
  const bookmarks = useCollections((s) => s.bookmarks);
  const remove = useCollections((s) => s.removeBookmark);
  const setActive = useActiveHost((s) => s.setActive);
  const [hosts, setHosts] = useState<Record<string, Host>>({});

  useEffect(() => {
    hostStore.listHosts().then((l) => setHosts(Object.fromEntries(l.map((h) => [h.id, h]))));
  }, []);

  if (bookmarks.length === 0) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: Spacing.xl, gap: Spacing.md }}>
        <Stack.Screen options={{ title: 'Bookmarks' }} />
        <View style={{ width: 120, height: 120, borderRadius: 60, backgroundColor: `${c.primary}24`, alignItems: 'center', justifyContent: 'center' }}>
          <BookmarkIcon size={48} color={c.primary} />
        </View>
        <Text muted style={{ textAlign: 'center' }}>No bookmarks yet. Long-press any file to bookmark it.</Text>
      </View>
    );
  }

  const groups = new Map<string, Bookmark[]>();
  for (const b of bookmarks) groups.set(b.hostId, [...(groups.get(b.hostId) ?? []), b]);

  async function confirmRemove(b: Bookmark, name: string) {
    const ok = await dialogs.confirm({ title: t('removeBookmarkTitle'), description: t('removeBookmarkConfirm', { name }), confirmLabel: t('removeButton'), cancelLabel: t('cancelButton'), destructive: true });
    if (ok) await remove(b.hostId, b.remotePath);
  }

  return (
    <ScrollView contentContainerStyle={{ paddingVertical: Spacing.md }}>
      <Stack.Screen options={{ title: 'Bookmarks' }} />
      {[...groups.entries()].map(([hostId, items]) => (
        <View key={hostId} style={{ marginBottom: Spacing.md }}>
          <View style={{ paddingHorizontal: Spacing.md }}>
            <SectionLabel title={hosts[hostId]?.label ?? hostId} />
          </View>
          {items.map((b, i) => {
            const name = b.remotePath.split('/').filter(Boolean).pop() ?? b.remotePath;
            return (
              <Pressable
                key={b.remotePath}
                accessibilityLabel={name}
                onPress={() => {
                  const host = hosts[b.hostId];
                  if (!host) return;
                  setActive({ host, health: null, initialPath: b.remotePath });
                  router.dismissTo('/files');
                }}
                onLongPress={() => confirmRemove(b, name)}
              >
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm, borderTopWidth: i ? 1 : 0, borderColor: c.outlineVariant, marginLeft: i ? Spacing.md : 0 }}>
                  <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: `${c.primary}24`, alignItems: 'center', justifyContent: 'center' }}>
                    <BookmarkIcon size={18} color={c.primary} />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text numberOfLines={1} style={{ fontSize: 14, fontFamily: FontFamily.medium }}>{name}</Text>
                    <Text numberOfLines={1} muted style={{ fontSize: 11.5, fontFamily: FontFamily.mono }}>{b.remotePath}</Text>
                  </View>
                  {b.tag ? (
                    <View style={{ paddingHorizontal: 7, paddingVertical: 2, borderRadius: Radii.stadium, backgroundColor: c.surfaceContainerHighest }}>
                      <Text style={{ fontSize: 10.5, fontFamily: FontFamily.semibold }} muted>{b.tag}</Text>
                    </View>
                  ) : null}
                </View>
              </Pressable>
            );
          })}
        </View>
      ))}
    </ScrollView>
  );
}
