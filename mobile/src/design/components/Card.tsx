import type { ReactNode } from 'react';
import { View, type StyleProp, type ViewStyle } from 'react-native';

import { useScheme } from '../theme';
import { Radii } from '../tokens';
import { Text } from './Text';

/** Mockup `.card` (GroupedCard): flat surface, 1px outlineVariant border, 20 radius, 14 padding, no elevation. */
export function GroupedCard({ children, padded = true, style }: { children: ReactNode; padded?: boolean; style?: StyleProp<ViewStyle> }) {
  const c = useScheme();
  return (
    <View
      style={[
        { backgroundColor: c.surface, borderRadius: Radii.card, borderWidth: 1, borderColor: c.outlineVariant, padding: padded ? 14 : 0, overflow: 'hidden' },
        style,
      ]}
    >
      {children}
    </View>
  );
}

/** Mockup `.section-label`: uppercase, tracked, faint. */
export function SectionLabel({ title, trailing }: { title: string; trailing?: ReactNode }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 4, paddingBottom: 8 }}>
      <Text variant="sectionLabel" muted accessibilityRole="header" style={{ flex: 1, textTransform: 'uppercase' }}>
        {title}
      </Text>
      {trailing}
    </View>
  );
}
