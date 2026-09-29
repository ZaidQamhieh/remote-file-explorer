import { History } from 'lucide-react-native';
import { useEffect, useState } from 'react';
import { FlatList, View } from 'react-native';

import { formatSize } from '../../core/format';
import { transfers, type TransferRecord } from '../../core/native';
import { AppBar, Button, EmptyState, GroupedCard, Text } from '../../design/components';
import { Spacing } from '../../design/tokens';

/** Interim Transfers tab over the native engine (phase-5 port adds stats grid, grouping, journal history). */
export default function Transfers() {
  const [items, setItems] = useState<TransferRecord[] | null>(null);
  useEffect(() => {
    let live = true;
    transfers.list().then((l) => live && setItems(l));
    const off = transfers.subscribe((r) => setItems((cur) => [...(cur ?? []).filter((x) => x.id !== r.id), r].sort((a, b) => a.id.localeCompare(b.id))));
    return () => {
      live = false;
      off();
    };
  }, []);
  const active = (items ?? []).filter((r) => r.state === 'RUNNING' || r.state === 'PAUSED').length;
  return (
    <View style={{ flex: 1 }}>
      <AppBar title="Transfers" subtitle={active > 0 ? `${active} active` : undefined} tall />
      {items === null ? null : items.length === 0 ? (
        <EmptyState message="No transfers yet" />
      ) : (
        <FlatList
          contentContainerStyle={{ padding: Spacing.md, gap: Spacing.sm }}
          data={items}
          keyExtractor={(r) => r.id}
          renderItem={({ item: r }) => (
            <GroupedCard>
              <View style={{ gap: 6 }}>
                <Text variant="titleMedium" numberOfLines={1}>{r.remotePath.split('/').pop()}</Text>
                <Text variant="bodySmall" muted>
                  {r.state}
                  {r.total > 0 ? ` · ${formatSize(r.received)} / ${formatSize(r.total)}` : r.received > 0 ? ` · ${formatSize(r.received)}` : ''}
                </Text>
                {r.error ? <Text variant="bodySmall" color="#F1596B">{r.error}</Text> : null}
                <View style={{ flexDirection: 'row', gap: 8 }}>
                  {r.state === 'RUNNING' && <Button kind="outlined" label="Pause" onPress={() => transfers.pause(r.id)} />}
                  {(r.state === 'PAUSED' || r.state === 'FAILED') && <Button kind="outlined" label="Resume" onPress={() => transfers.resume(r.id)} />}
                  {r.state !== 'DONE' && r.state !== 'CANCELLED' && <Button kind="text" label="Cancel" destructive onPress={() => transfers.cancel(r.id)} />}
                </View>
              </View>
            </GroupedCard>
          )}
        />
      )}
    </View>
  );
}
