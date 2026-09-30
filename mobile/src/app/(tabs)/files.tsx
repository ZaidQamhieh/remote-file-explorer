import { useRouter } from 'expo-router';
import { Server } from 'lucide-react-native';
import { useCallback } from 'react';
import { View } from 'react-native';

import { Button, GroupedCard, PageHead, Text, TopBar } from '../../design/components';
import { LumenType } from '../../design/lumen';
import { useScheme } from '../../design/theme';
import { ExplorerScreen } from '../../features/explorer/ExplorerScreen';
import { HostRootView } from '../../features/explorer/HostRootView';
import { useActiveHost } from '../../state/activeHost';

/** Files tab: pick a host on the Devices tab, then a shared root, then browse. */
export default function Files() {
  const c = useScheme();
  const router = useRouter();
  const active = useActiveHost((s) => s.active);
  const setActive = useActiveHost((s) => s.setActive);

  const onSelectRoot = useCallback(
    (rootPath: string, initialPath?: string) => {
      const cur = useActiveHost.getState().active;
      if (!cur) return;
      setActive({ ...cur, rootPath, initialPath });
    },
    [setActive],
  );

  if (!active) {
    return (
      <View style={{ flex: 1 }}>
        <TopBar context="Files" />
        <PageHead title="Files" subtitle="Select a server to browse its files" />
        <View style={{ paddingHorizontal: 18 }}>
          <GroupedCard style={{ alignItems: 'center', gap: 14, paddingVertical: 24 }}>
            <Server size={40} color={c.onSurfaceVariant} />
            <Text style={[LumenType.meta, { textAlign: 'center' }]} muted>Pick a computer on the Home tab, then a shared folder, to start browsing.</Text>
            <Button size="lg" kind="filled" label="Go to Home" renderIcon={(k) => <Server size={20} color={k} />} onPress={() => router.navigate('/')} />
          </GroupedCard>
        </View>
      </View>
    );
  }
  if (active.rootPath) return <ExplorerScreen key={`${active.host.id}:${active.rootPath}:${active.initialPath ?? ''}`} host={active.host} rootPath={active.rootPath} initialPath={active.initialPath} />;
  return <HostRootView key={`${active.host.id}:${active.initialPath ?? ''}`} host={active.host} health={active.health} initialPath={active.initialPath} onSelectRoot={onSelectRoot} />;
}
