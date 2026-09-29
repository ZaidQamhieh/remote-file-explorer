import { Directory, File, Paths } from 'expo-file-system';
import { useRouter } from 'expo-router';
import { FileText, Folder, Server } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { BackHandler, FlatList, PermissionsAndroid, Platform, View } from 'react-native';

import type { AgentClient } from '../../core/api/agentClient';
import type { Entry } from '../../core/api/models';
import { formatSize } from '../../core/format';
import { transfers } from '../../core/native';
import { AppBar, Button, EmptyState, ErrorRetry, ListingSkeleton, Pressable, Text, useToast } from '../../design/components';
import { useScheme } from '../../design/theme';
import { humanizeError } from '../../features/pairing/pairingService';
import { clientForHost } from '../../services';
import { useActiveHost } from '../../state/activeHost';

/** Interim Files tab (phase-4 explorer port replaces this): roots, folder navigation, queued downloads. */
export default function Files() {
  const c = useScheme();
  const router = useRouter();
  const toast = useToast();
  const active = useActiveHost((s) => s.active);
  const [client, setClient] = useState<AgentClient | null>(null);
  const [stack, setStack] = useState<string[]>([]);
  const [entries, setEntries] = useState<Entry[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (cl: AgentClient, path: string | null) => {
    setEntries(null);
    setError(null);
    try {
      if (path === null) {
        const drives = await cl.drives();
        if (drives.length > 0) return setEntries(drives.map((d) => ({ name: d.label || d.path, path: d.path, isDir: true, isSymlink: false })));
        const st = await cl.status();
        if (st.accessDenied) return setError('This device has no access to any shared folder on this host.');
        if (st.roots.length === 0) return setError('The host has no shared folders configured.');
        return setEntries(st.roots.map((r) => ({ name: r, path: r, isDir: true, isSymlink: false })));
      }
      setEntries((await cl.list(path)).entries);
    } catch (e) {
      setError(humanizeError(e));
    }
  }, []);

  useEffect(() => {
    setStack([]);
    setClient(null);
    if (!active) return;
    let live = true;
    clientForHost(active.host)
      .then((cl) => {
        if (!live) return;
        setClient(cl);
        load(cl, null);
      })
      .catch((e) => live && setError(humanizeError(e)));
    return () => {
      live = false;
    };
  }, [active, load]);

  // Back inside a folder goes up a level before leaving the tab.
  useEffect(() => {
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if (stack.length === 0 || !client) return false;
      const next = stack.slice(0, -1);
      setStack(next);
      load(client, next.length ? next[next.length - 1] : null);
      return true;
    });
    return () => sub.remove();
  }, [stack, client, load]);

  if (!active) {
    return (
      <View style={{ flex: 1 }}>
        <AppBar title="Files" />
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 }}>
          <Server size={56} color={c.outline} />
          <Text>Select a server to browse its files</Text>
          <Button kind="filled" label="Go to Devices" renderIcon={(k) => <Server size={18} color={k} />} onPress={() => router.navigate('/')} />
        </View>
      </View>
    );
  }

  const open = (e: Entry) => {
    if (!client) return;
    if (e.isDir) {
      setStack((s) => [...s, e.path]);
      load(client, e.path);
      return;
    }
    download(e);
  };

  async function download(e: Entry) {
    if (!client || !active) return;
    try {
      if (Platform.OS === 'android' && Platform.Version >= 33) await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS);
      const dir = new Directory(Paths.document, 'downloads');
      dir.create({ idempotent: true, intermediates: true });
      const dest = decodeURIComponent(new File(dir, e.name).uri.replace('file://', ''));
      await transfers.enqueue(`d${Date.now().toString(36)}`, active.host.id, client.activeAddress, e.path, dest);
      toast.info(`Downloading ${e.name}`);
    } catch (err) {
      toast.error(`Could not start download: ${humanizeError(err)}`);
    }
  }

  const title = stack.length ? stack[stack.length - 1].split('/').filter(Boolean).pop() ?? '/' : active.host.label;
  return (
    <View style={{ flex: 1 }}>
      <AppBar title={title} subtitle={active.host.label} />
      {error ? (
        <ErrorRetry message={error} onRetry={() => client && load(client, stack.length ? stack[stack.length - 1] : null)} />
      ) : entries === null ? (
        <ListingSkeleton />
      ) : entries.length === 0 ? (
        <EmptyState />
      ) : (
        <FlatList
          data={entries}
          keyExtractor={(e) => e.path}
          renderItem={({ item }) => (
            <Pressable onPress={() => open(item)} accessibilityLabel={item.name}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16, paddingHorizontal: 16, paddingVertical: 8, minHeight: 56 }}>
                <View style={{ width: 40, height: 40, borderRadius: 12, backgroundColor: item.isDir ? `${c.primary}1F` : c.surfaceContainerHighest, alignItems: 'center', justifyContent: 'center' }}>
                  {item.isDir ? <Folder size={20} color={c.primary} /> : <FileText size={20} color={c.onSurfaceVariant} />}
                </View>
                <View style={{ flex: 1 }}>
                  <Text variant="titleMedium" numberOfLines={1}>{item.name}</Text>
                  {!item.isDir && item.size != null ? <Text variant="bodySmall" muted>{formatSize(item.size)}</Text> : null}
                </View>
              </View>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}
