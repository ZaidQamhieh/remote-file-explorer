import { View } from 'react-native';

import { Text } from '../../design/components';

/** Apps tab (placeholder until the Apps screen moves here). */
export default function AppsTab() {
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <Text muted>Apps</Text>
    </View>
  );
}
