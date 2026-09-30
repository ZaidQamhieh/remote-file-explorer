import { Search, type LucideIcon } from 'lucide-react-native';
import { useState } from 'react';
import { FlatList, Modal, Pressable as RNPressable, TextInput, View } from 'react-native';

import { Pressable, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { FontFamily, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { filterPalette, type PaletteItem } from './paletteLogic';

export type PaletteAction = PaletteItem & { icon: LucideIcon; run: () => void };

/** Type-to-filter list of the explorer's commands; picking one closes the palette first, then runs it. */
export function CommandPalette({ visible, actions, onClose }: { visible: boolean; actions: PaletteAction[]; onClose: () => void }) {
  const c = useScheme();
  const [query, setQuery] = useState('');
  const shown = filterPalette(actions, query);
  const close = () => {
    setQuery('');
    onClose();
  };
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={close} statusBarTranslucent>
      <RNPressable style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', paddingHorizontal: 24, paddingVertical: 80 }} onPress={close} accessibilityLabel={t('cancelButton')}>
        <RNPressable accessibilityViewIsModal style={{ backgroundColor: c.surfaceContainerHigh, borderRadius: Radii.card, borderWidth: 1, borderColor: c.outlineVariant, overflow: 'hidden', maxHeight: '100%' }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.sm, margin: 12, paddingHorizontal: 12, borderRadius: Radii.chip, borderWidth: 1, borderColor: c.outlineVariant, backgroundColor: c.surfaceContainerHighest }}>
            <Search size={18} color={c.onSurfaceVariant} />
            <TextInput
              autoFocus
              value={query}
              onChangeText={setQuery}
              placeholder={t('commandPaletteHint')}
              placeholderTextColor={c.onSurfaceVariant}
              accessibilityLabel={t('commandPaletteTitle')}
              style={{ flex: 1, color: c.onSurface, fontFamily: FontFamily.regular, fontSize: 15, paddingVertical: 10 }}
            />
          </View>
          <FlatList
            data={shown}
            keyExtractor={(a) => a.id}
            keyboardShouldPersistTaps="handled"
            renderItem={({ item }) => (
              <Pressable
                accessibilityLabel={item.label}
                onPress={() => {
                  close();
                  item.run();
                }}
              >
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingHorizontal: 16, paddingVertical: 12 }}>
                  <item.icon size={20} color={c.onSurfaceVariant} />
                  <Text>{item.label}</Text>
                </View>
              </Pressable>
            )}
          />
        </RNPressable>
      </RNPressable>
    </Modal>
  );
}
