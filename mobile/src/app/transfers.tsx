import { useEffect, useState } from 'react';
import { FlatList, Pressable, Text, View } from 'react-native';

import { transfers, type TransferRecord } from '../core/native';

const fmt = (n: number) => (n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1048576).toFixed(1)} MB`);

export default function Transfers() {
  const [items, setItems] = useState<TransferRecord[] | null>(null);
  useEffect(() => {
    let live = true;
    transfers.list().then((l) => live && setItems(l));
    const off = transfers.subscribe((r) =>
      setItems((cur) => [...(cur ?? []).filter((x) => x.id !== r.id), r].sort((a, b) => a.id.localeCompare(b.id))),
    );
    return () => {
      live = false;
      off();
    };
  }, []);

  if (items === null) return <Text style={{ padding: 16 }}>Loading…</Text>;
  if (items.length === 0) return <Text style={{ padding: 16 }}>No transfers yet.</Text>;
  const btn = { padding: 10, borderWidth: 1, borderColor: '#999', borderRadius: 8 } as const;
  return (
    <FlatList
      data={items}
      keyExtractor={(r) => r.id}
      renderItem={({ item: r }) => (
        <View style={{ padding: 16, borderBottomWidth: 1, borderColor: '#ddd', gap: 6 }}>
          <Text style={{ fontSize: 16 }}>{r.remotePath.split('/').pop()}</Text>
          <Text>
            {r.state}
            {r.total > 0 ? ` · ${fmt(r.received)} / ${fmt(r.total)}` : r.received > 0 ? ` · ${fmt(r.received)}` : ''}
          </Text>
          {r.error && <Text style={{ color: '#b00020' }}>{r.error}</Text>}
          <View style={{ flexDirection: 'row', gap: 8 }}>
            {r.state === 'RUNNING' && <Pressable accessibilityRole="button" style={btn} onPress={() => transfers.pause(r.id)}><Text>Pause</Text></Pressable>}
            {(r.state === 'PAUSED' || r.state === 'FAILED') && <Pressable accessibilityRole="button" style={btn} onPress={() => transfers.resume(r.id)}><Text>Resume</Text></Pressable>}
            {r.state !== 'DONE' && r.state !== 'CANCELLED' && <Pressable accessibilityRole="button" style={btn} onPress={() => transfers.cancel(r.id)}><Text>Cancel</Text></Pressable>}
          </View>
        </View>
      )}
    />
  );
}
