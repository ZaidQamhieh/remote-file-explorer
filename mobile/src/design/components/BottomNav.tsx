import type { BottomTabBarProps } from 'expo-router/tabs';
import type { LucideIcon } from 'lucide-react-native';
import { Pressable as RNPressable, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { mix } from '../color';
import { useScheme } from '../theme';
import { Text } from './Text';

const BAR_H = 64;
const PILL_W = 64;
const PILL_H = 32;

export type NavDestination = { name: string; label: string; Icon: LucideIcon; SelectedIcon?: LucideIcon };

/** Flat full-width dock with the four destinations; the selected one gets a single tinted pill (no notch, no FAB). */
export function BottomNav({ state, navigation, destinations }: BottomTabBarProps & { destinations: NavDestination[] }) {
  const c = useScheme();
  const insets = useSafeAreaInsets();

  return (
    <View style={{ backgroundColor: c.surfaceContainerLow, paddingBottom: insets.bottom, borderTopWidth: 1, borderTopColor: c.outlineVariant }}>
      <View style={{ height: BAR_H, flexDirection: 'row' }}>
        {destinations.map((d, i) => {
          const selected = state.index === i;
          const tint = selected ? c.primary : c.onSurfaceVariant;
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
              style={{ flex: 1, minHeight: 56, alignItems: 'center', justifyContent: 'center', gap: 2 }}
            >
              <View style={{ width: PILL_W, height: PILL_H, alignItems: 'center', justifyContent: 'center' }}>
                {/* Always mounted, only opacity changes: on Android a radius is lost when a view's background is swapped or mounted after the first layout. */}
                <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, borderRadius: PILL_H / 2, backgroundColor: mix(c.primary, c.surfaceContainerLow, 0.16), opacity: selected ? 1 : 0 }} />
                <Icon size={22} color={tint} />
              </View>
              <Text style={{ fontSize: 12, lineHeight: 16, fontFamily: selected ? 'Inter-SemiBold' : 'Inter-Regular', letterSpacing: 0.3 }} color={tint} numberOfLines={1}>
                {d.label}
              </Text>
            </RNPressable>
          );
        })}
      </View>
    </View>
  );
}
