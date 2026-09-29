import { useRouter } from 'expo-router';
import { Server } from 'lucide-react-native';
import { useCallback } from 'react';
import { View } from 'react-native';

import { AppBar, Button, Text } from '../../design/components';
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
        <AppBar title="Files" />
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12 }}>
          <Server size={56} color={c.outline} />
          <Text>Select a server to browse its files</Text>
          <Button kind="filled" label="Go to Devices" renderIcon={(k) => <Server size={18} color={k} />} onPress={() => router.navigate('/')} />
        </View>
      </View>
    );
  }
  if (active.rootPath) return <ExplorerScreen key={`${active.host.id}:${active.rootPath}:${active.initialPath ?? ''}`} host={active.host} rootPath={active.rootPath} initialPath={active.initialPath} />;
  return <HostRootView key={`${active.host.id}:${active.initialPath ?? ''}`} host={active.host} health={active.health} initialPath={active.initialPath} onSelectRoot={onSelectRoot} />;
}
