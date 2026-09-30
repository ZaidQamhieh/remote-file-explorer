import { View } from 'react-native';

import { useScheme } from '../theme';
import { Spacing } from '../tokens';
import { Button } from './Button';
import type { ReactNode } from 'react';

export type FooterButton = { key: string; label: string; primary: boolean; onPress: () => void; renderIcon?: (color: string) => ReactNode };

/** Persistent bottom action row: the primary button takes 60%, a secondary 40%, a lone button the full width. */
export function ActionFooter({ buttons }: { buttons: FooterButton[] }) {
  const c = useScheme();
  if (buttons.length === 0) return null;
  const lone = buttons.length === 1;
  return (
    <View style={{ flexDirection: 'row', gap: Spacing.sm, paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm, backgroundColor: c.surface }}>
      {buttons.map((b) => (
        <Button key={b.key} size="lg" kind={b.primary ? 'filled' : 'tonal'} label={b.label} onPress={b.onPress} renderIcon={b.renderIcon} style={{ flex: lone ? 1 : b.primary ? 3 : 2 }} />
      ))}
    </View>
  );
}
