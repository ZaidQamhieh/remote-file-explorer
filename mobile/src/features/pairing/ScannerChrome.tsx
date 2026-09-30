import { useEffect, useState } from 'react';
import { Animated, Easing, View } from 'react-native';

import { Pressable } from '../../design/components';

export function Scanline({ height }: { height: number }) {
  const v = useState(() => new Animated.Value(0))[0];
  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(v, { toValue: 1, duration: 2200, easing: Easing.inOut(Easing.ease), useNativeDriver: true }),
        Animated.timing(v, { toValue: 0, duration: 2200, easing: Easing.inOut(Easing.ease), useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [v]);
  const travel = height / 2 - 8;
  return (
    <Animated.View
      style={{ position: 'absolute', left: 8, right: 8, top: height / 2, height: 2, backgroundColor: '#4C8DFF', shadowColor: '#4C8DFF', shadowOpacity: 0.6, shadowRadius: 8, transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [-travel, travel] }) }] }}
    />
  );
}

export const DarkIconButton = ({ children, onPress, label }: { children: React.ReactNode; onPress: () => void; label: string }) => (
  <Pressable onPress={onPress} accessibilityLabel={label}>
    <View style={{ width: 34, height: 34, borderRadius: 17, backgroundColor: 'rgba(255,255,255,0.08)', alignItems: 'center', justifyContent: 'center' }}>{children}</View>
  </Pressable>
);

