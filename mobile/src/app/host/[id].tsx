import { Directory, File, Paths } from 'expo-file-system';
import { Stack, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, Text, View } from 'react-native';

import type { AgentClient } from '../../core/api/agentClient';
import type { Entry } from '../../core/api/models';
import { downloadToFile } from '../../core/native';
import { clientForHost, hostStore } from '../../services';

const fmt = (n?: number) => (n === undefined ? '' : n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1048576).toFixed(1)} MB`);

export default function Browse() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [client, setClient] = useState<AgentClient | null>(null);
  const [path, setPath] = useState<string | null>(null);
  const [entries, setEntries] = useState<Entry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const load = useCallback(async (c: AgentClient, p: string | null) => {
    setEntries(null);
    setError(null);
    try {
      let start = p;
      if (start === null) {
        const drives = await c.drives();
        if (drives.length > 0) {
          setEntries(drives.map((d) => ({ name: d.label || d.path, path: d.path, isDir: true, isSymlink: false, size: d.totalBytes })));
          return;
        }
        const st = await c.status();
        if (st.accessDenied) {
          setEntries([]);
          setError('This device has no access to any shared folder on this host.');
          return;
        }
        if (st.roots.length === 0) {
          setEntries([]);
          setError('The host has no shared folders configured.');
          return;
        }
        setEntries(st.roots.map((r) => ({ name: r, path: r, isDir: true, isSymlink: false })));
        return;
      }
      const l = await c.list(start);
      setPath(l.path || start);
      setEntries(l.entries);
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  useEffect(() => {
    (async () => {
      const host = (await hostStore.listHosts()).find((h) => h.id === id);
      if (!host) return setError('Host not found');
      try {
        const c = await clientForHost(host);
        setClient(c);
        await load(c, null);
      } catch (e) {
        setError((e as Error).message);
      }
    })();
  }, [id, load]);

  async function download(e: Entry) {
    if (!client) return;
    setStatus(`Downloading ${e.name}…`);
    try {
      const dir = new Directory(Paths.cache, 'downloads');
      dir.create({ idempotent: true, intermediates: true });
      const dest = new File(dir, e.name);
      const spec = client.downloadSpec(e.path);
      const bytes = await downloadToFile(spec.url, spec.headers, spec.pin, dest.uri.replace('file://', ''), 0);
      setStatus(`Saved ${e.name} (${fmt(bytes)}) to app cache`);
    } catch (err) {
      setStatus(`Download failed: ${(err as Error).message}`);
    }
  }

  return (
    <View style={{ flex: 1 }}>
      <Stack.Screen options={{ title: path ?? 'Drives' }} />
      {error && <Text accessibilityRole="alert" style={{ padding: 16, color: '#b00020' }}>{error}</Text>}
      {entries === null && !error && <ActivityIndicator style={{ margin: 24 }} />}
      {entries?.length === 0 && !error && <Text style={{ padding: 16 }}>This folder is empty.</Text>}
      <FlatList
        data={entries ?? []}
        keyExtractor={(e) => e.path}
        renderItem={({ item }) => (
          <Pressable
            accessibilityRole="button"
            onPress={() => (item.isDir ? client && load(client, item.path) : download(item))}
            style={{ padding: 16, borderBottomWidth: 1, borderColor: '#ddd' }}
          >
            <Text style={{ fontSize: 16 }}>{item.isDir ? '📁 ' : ''}{item.name}</Text>
            {!item.isDir && <Text>{fmt(item.size)}</Text>}
          </Pressable>
        )}
      />
      {status && <Text style={{ padding: 16 }} accessibilityLiveRegion="polite">{status}</Text>}
    </View>
  );
}
