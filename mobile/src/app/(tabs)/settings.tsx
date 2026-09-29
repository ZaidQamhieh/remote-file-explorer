import { View } from 'react-native';

import { AppBar, EmptyState } from '../../design/components';

// Placeholder until the settings port (phase 5).
export default function Settings() {
  return (
    <View style={{ flex: 1 }}>
      <AppBar title="Settings" />
      <EmptyState message="Settings are coming in a later phase" />
    </View>
  );
}
