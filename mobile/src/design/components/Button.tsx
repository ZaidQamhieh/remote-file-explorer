import { LinearGradient } from 'expo-linear-gradient';
import type { ReactNode } from 'react';
import { ActivityIndicator, View, type StyleProp, type ViewStyle } from 'react-native';

import { useScheme } from '../theme';
import { Brand, Radii, Spacing } from '../tokens';
import { Pressable } from './Pressable';
import { Text } from './Text';

type Kind = 'gradient' | 'filled' | 'tonal' | 'outlined' | 'text';
type Props = {
  label: string;
  onPress?: () => void;
  kind?: Kind;
  icon?: ReactNode;
  busy?: boolean;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
  /** `lg` is the 52 dp primary-action height. */
  size?: 'md' | 'lg';
  destructive?: boolean;
  /** Render the icon in the button's foreground color. */
  renderIcon?: (color: string) => ReactNode;
};

/**
 * Stadium buttons with centered content (a hard UI rule). `gradient` is the
 * mockup `.btn-primary`: 135° gradient with a tinted glow (GradientButton).
 */
export function Button({ label, onPress, kind = 'gradient', icon, renderIcon, busy, disabled, style, destructive, size = 'md' }: Props) {
  const c = useScheme();
  const off = disabled || busy;
  const fg = kind === 'gradient' ? '#FFFFFF' : kind === 'filled' ? c.onPrimary : kind === 'tonal' ? c.onSecondaryContainer : destructive ? c.error : c.primary;
  const inner = (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: Spacing.sm }}>
      {busy ? <ActivityIndicator size="small" color={fg} /> : renderIcon ? renderIcon(fg) : icon}
      <Text variant="labelLarge" color={fg} style={{ fontFamily: 'Inter-SemiBold', textAlign: 'center' }}>
        {label}
      </Text>
    </View>
  );
  const pad = { paddingHorizontal: Spacing.lg, paddingVertical: Spacing.sm + 2, minHeight: size === 'lg' ? 52 : 44, justifyContent: 'center' } as const;
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
            kind === 'tonal' && { backgroundColor: c.secondaryContainer },
            kind === 'outlined' && { borderWidth: 1, borderColor: destructive ? c.error : c.outline },
          ]}
        >
          {inner}
        </View>
      )}
    </Pressable>
  );
}
