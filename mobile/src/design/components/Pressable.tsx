import { useRef, type ReactNode } from 'react';
import { Animated, Pressable as RNPressable, type PressableProps, type StyleProp, type ViewStyle } from 'react-native';

type Props = Omit<PressableProps, 'style' | 'children'> & {
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
  pressedScale?: number;
};

/** Port of core/ui/pressable.dart: opaque hit area, 100ms scale to 0.985 on press. */
export function Pressable({ children, style, pressedScale = 0.985, onPressIn, onPressOut, ...rest }: Props) {
  const scale = useRef(new Animated.Value(1)).current;
  const to = (v: number) => Animated.timing(scale, { toValue: v, duration: 100, useNativeDriver: true }).start();
  return (
    <RNPressable
      accessibilityRole="button"
      {...rest}
      onPressIn={(e) => {
        to(pressedScale);
        onPressIn?.(e);
      }}
      onPressOut={(e) => {
        to(1);
        onPressOut?.(e);
      }}
    >
      <Animated.View style={[{ transform: [{ scale }] }, style]}>{children}</Animated.View>
    </RNPressable>
  );
}
