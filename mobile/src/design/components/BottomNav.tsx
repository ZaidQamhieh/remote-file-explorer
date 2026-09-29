import type { BottomTabBarProps } from 'expo-router/tabs';
import { LinearGradient } from 'expo-linear-gradient';
import { Plus, type LucideIcon } from 'lucide-react-native';
import { useState } from 'react';
import { Pressable as RNPressable, View } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useScheme } from '../theme';
import { Brand, Radii, Spacing } from '../tokens';
import { Text } from './Text';

const BAR_H = 76;
const NOTCH_D = 14;
const HALF_NOTCH_W = 40;
const FAB = 48;

export type NavDestination = { name: string; label: string; Icon: LucideIcon; SelectedIcon?: LucideIcon };

/** Port of AppBottomNav: notched bar (cubic curve) with a centered accent-gradient FAB and 4 destinations. */
export function BottomNav({ state, navigation, destinations, onAdd }: BottomTabBarProps & { destinations: NavDestination[]; onAdd: () => void }) {
  const c = useScheme();
  const insets = useSafeAreaInsets();
  const [w, setW] = useState(0);
  const cx = w / 2;
  const cc = 20;
  const fill = `M0 ${NOTCH_D} L${cx - HALF_NOTCH_W} ${NOTCH_D} C${cx - HALF_NOTCH_W + cc} ${NOTCH_D} ${cx - HALF_NOTCH_W + cc} 0 ${cx} 0 C${cx + HALF_NOTCH_W - cc} 0 ${cx + HALF_NOTCH_W - cc} ${NOTCH_D} ${cx + HALF_NOTCH_W} ${NOTCH_D} L${w} ${NOTCH_D} L${w} ${BAR_H} L0 ${BAR_H} Z`;
  const border = `M0 ${NOTCH_D} L${cx - HALF_NOTCH_W} ${NOTCH_D} C${cx - HALF_NOTCH_W + cc} ${NOTCH_D} ${cx - HALF_NOTCH_W + cc} 0 ${cx} 0 C${cx + HALF_NOTCH_W - cc} 0 ${cx + HALF_NOTCH_W - cc} ${NOTCH_D} ${cx + HALF_NOTCH_W} ${NOTCH_D} L${w} ${NOTCH_D}`;

  const button = (i: number) => {
    const d = destinations[i];
    const selected = state.index === i;
    const tint = selected ? c.primary : c.outline;
    const Icon = selected ? (d.SelectedIcon ?? d.Icon) : d.Icon;
    return (
      <RNPressable
        key={d.name}
        accessibilityRole="tab"
        accessibilityState={{ selected }}
        accessibilityLabel={d.label}
        onPress={() => {
          const route = state.routes[i];
          const ev = navigation.emit({ type: 'tabPress', target: route.key, canPreventDefault: true });
          if (!selected && !ev.defaultPrevented) navigation.navigate(route.name);
        }}
        style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}
      >
        <View style={{ height: 4, width: 32, borderRadius: Radii.stadium, backgroundColor: selected ? c.primary : 'transparent' }} />
        <View style={{ height: Spacing.xs }} />
        <View style={{ paddingHorizontal: Spacing.md2, paddingVertical: 4, borderRadius: Radii.stadium, backgroundColor: selected ? `${c.primary}29` : 'transparent' }}>
          <Icon size={22} color={tint} />
        </View>
        <View style={{ height: Spacing.xs }} />
        <Text style={{ fontSize: 10, fontFamily: selected ? 'Inter-SemiBold' : 'Inter-Regular', letterSpacing: 0.5 }} color={tint}>
          {d.label}
        </Text>
      </RNPressable>
    );
  };

  return (
    <View style={{ backgroundColor: c.surface, paddingBottom: insets.bottom }}>
      <View style={{ height: BAR_H }} onLayout={(e) => setW(e.nativeEvent.layout.width)}>
        {w > 0 && (
          <Svg width={w} height={BAR_H} style={{ position: 'absolute' }}>
            <Path d={fill} fill={c.surfaceContainerLow} />
            <Path d={border} fill="none" stroke={c.outlineVariant} strokeWidth={1} />
          </Svg>
        )}
        <View style={{ position: 'absolute', top: NOTCH_D, left: 0, right: 0, bottom: 0, flexDirection: 'row' }}>
          <View style={{ flex: 1, flexDirection: 'row' }}>{[0, 1].map(button)}</View>
          <View style={{ width: HALF_NOTCH_W * 2 }} />
          <View style={{ flex: 1, flexDirection: 'row' }}>{[2, 3].map(button)}</View>
        </View>
        <View style={{ position: 'absolute', top: 2, left: 0, right: 0, alignItems: 'center' }} pointerEvents="box-none">
          <RNPressable accessibilityRole="button" accessibilityLabel="Add computer" onPress={onAdd} hitSlop={8}>
            <LinearGradient
              colors={[...Brand.accentGradient]}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 1 }}
              style={{ width: FAB, height: FAB, borderRadius: FAB / 2, borderWidth: 3, borderColor: c.surface, alignItems: 'center', justifyContent: 'center', shadowColor: Brand.accent, shadowOpacity: 0.4, shadowRadius: 10, shadowOffset: { width: 0, height: 4 }, elevation: 6 }}
            >
              <Plus size={22} color="#fff" />
            </LinearGradient>
          </RNPressable>
        </View>
      </View>
    </View>
  );
}
