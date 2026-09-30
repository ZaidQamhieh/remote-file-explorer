import type { ReactNode } from 'react';
import { View } from 'react-native';

import { useScheme } from '../theme';
import { Radii, Spacing } from '../tokens';
import { Pressable } from './Pressable';
import { Text } from './Text';

/** Secondary action: 64 dp tile with a role-coloured icon above a 12 sp label. Shown at 40% when disabled. */
export function ActionTile({ label, onPress, disabled, renderIcon }: { label: string; onPress?: () => void; disabled?: boolean; renderIcon: (color: string) => ReactNode }) {
  const c = useScheme();
  return (
    <Pressable onPress={disabled ? undefined : onPress} disabled={disabled} accessibilityLabel={label} accessibilityState={{ disabled: !!disabled }} style={{ flex: 1, opacity: disabled ? 0.4 : 1 }}>
      <View style={{ minHeight: 64, borderRadius: Radii.sm, backgroundColor: c.surfaceContainerHigh, alignItems: 'center', justifyContent: 'center', gap: Spacing.xs, paddingHorizontal: Spacing.xs }}>
        {renderIcon(c.onSurface)}
        <Text style={{ fontSize: 12, lineHeight: 16, fontFamily: 'Lato_700Bold' }} numberOfLines={1}>
          {label}
        </Text>
      </View>
    </Pressable>
  );
}
