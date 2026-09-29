import { LinearGradient } from 'expo-linear-gradient';
import type { ReactNode } from 'react';
import { ActivityIndicator, View, type StyleProp, type ViewStyle } from 'react-native';

import { useScheme } from '../theme';
import { Brand, Radii, Spacing } from '../tokens';
import { Pressable } from './Pressable';
import { Text } from './Text';

type Kind = 'gradient' | 'filled' | 'outlined' | 'text';
type Props = {
  label: string;
  onPress?: () => void;
  kind?: Kind;
  icon?: ReactNode;
  busy?: boolean;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
  destructive?: boolean;
};

/**
 * Stadium buttons with centered content (a hard UI rule). `gradient` is the
 * mockup `.btn-primary`: 135° gradient with a tinted glow (GradientButton).
 */
export function Button({ label, onPress, kind = 'gradient', icon, busy, disabled, style, destructive }: Props) {
  const c = useScheme();
  const off = disabled || busy;
  const fg = kind === 'gradient' ? '#FFFFFF' : kind === 'filled' ? c.onPrimary : destructive ? c.error : c.primary;
  const inner = (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: Spacing.sm }}>
      {busy ? <ActivityIndicator size="small" color={fg} /> : icon}
      <Text variant="labelLarge" color={fg} style={{ fontFamily: 'Inter-SemiBold', textAlign: 'center' }}>
        {label}
      </Text>
    </View>
  );
  const pad = { paddingHorizontal: Spacing.lg, paddingVertical: Spacing.sm + 2, minHeight: 44, justifyContent: 'center' } as const;
  return (
    <Pressable
      onPress={off ? undefined : onPress}
      disabled={off}
      accessibilityState={{ disabled: !!off, busy: !!busy }}
      accessibilityLabel={label}
      style={[{ opacity: off ? 0.5 : 1, borderRadius: Radii.stadium }, style]}
    >
      {kind === 'gradient' ? (
        <LinearGradient
          colors={[...Brand.primaryGradient]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={[
            pad,
            { borderRadius: Radii.stadium, shadowColor: Brand.seed, shadowOpacity: off ? 0 : 0.35, shadowRadius: 14, shadowOffset: { width: 0, height: 4 }, elevation: off ? 0 : 4 },
          ]}
        >
          {inner}
        </LinearGradient>
      ) : (
        <View
          style={[
            pad,
            { borderRadius: Radii.stadium },
            kind === 'filled' && { backgroundColor: c.primary },
            kind === 'outlined' && { borderWidth: 1, borderColor: destructive ? c.error : c.outline },
          ]}
        >
          {inner}
        </View>
      )}
    </Pressable>
  );
}
