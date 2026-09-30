import { EyeOff, Plus, X } from 'lucide-react-native';
import { useState } from 'react';
import { TextInput, View } from 'react-native';

import { Pressable, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, FontFamily, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { visibilityPresets, type VisibilityPrefs } from '../../core/visibility';
import { ToggleRow } from './parts';
import { addExtension, addName, customExtensions, removeExtension, removeName, setHideDotfiles } from './visibilityEdit';

/**
 * Which files the explorer hides: dotfiles, and per file type (extension or exact name) grouped by category. It edits
 * a value and reports the next one, so the same editor serves the app default and a device's own override.
 */
export function VisibilityEditor({ prefs, onChange }: { prefs: VisibilityPrefs; onChange: (next: VisibilityPrefs) => void }) {
  const c = useScheme();
  const [draft, setDraft] = useState('');
  const custom = customExtensions(prefs);
  const lowerNames = new Set([...prefs.hiddenNames].map((n) => n.toLowerCase()));

  const submit = () => {
    if (draft.trim() === '') return;
    onChange(addExtension(prefs, draft));
    setDraft('');
  };

  return (
    <View style={{ gap: Spacing.md }}>
      <ToggleRow icon={EyeOff} tint={c.primary} title={t('hideDotfiles')} subtitle={t('hideDotfilesSubtitle')} value={prefs.hideDotfiles} onChange={(v) => onChange(setHideDotfiles(prefs, v))} />
      {visibilityPresets.map((preset) => (
        <View key={preset.label} style={{ gap: Spacing.xs }}>
          <Text variant="titleSmall">{preset.label}</Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.xs }}>
            {[...preset.extensions].sort().map((ext) => {
              const on = prefs.hiddenExtensions.has(ext);
              return <Chip key={ext} label={`.${ext}`} selected={on} onPress={() => onChange(on ? removeExtension(prefs, ext) : addExtension(prefs, ext))} />;
            })}
            {[...preset.names].sort().map((name) => {
              const on = lowerNames.has(name.toLowerCase());
              return <Chip key={name} label={name} selected={on} onPress={() => onChange(on ? removeName(prefs, name) : addName(prefs, name))} />;
            })}
          </View>
        </View>
      ))}
      <View style={{ gap: Spacing.xs }}>
        <Text variant="labelLarge">{t('customLabel')}</Text>
        {custom.length === 0 ? (
          <Text muted>{t('noCustomExtensions')}</Text>
        ) : (
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.xs }}>
            {custom.map((ext) => (
              <Chip key={ext} label={`.${ext}`} selected onPress={() => onChange(removeExtension(prefs, ext))} trailing={<X size={12} color="#fff" />} />
            ))}
          </View>
        )}
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.xs, borderWidth: 1, borderColor: c.outlineVariant, borderRadius: Radii.chip, paddingLeft: 12, backgroundColor: c.surfaceContainerHighest }}>
          <Text muted>.</Text>
          <TextInput
            accessibilityLabel={t('addExtensionHint')}
            value={draft}
            onChangeText={setDraft}
            onSubmitEditing={submit}
            placeholder={t('addExtensionHint')}
            placeholderTextColor={c.onSurfaceVariant}
            autoCapitalize="none"
            autoCorrect={false}
            returnKeyType="done"
            style={{ flex: 1, paddingVertical: 10, color: c.onSurface, fontFamily: FontFamily.regular, fontSize: 14 }}
          />
          <Pressable onPress={submit} pressedScale={0.92} accessibilityLabel={t('addExtensionTooltip')} style={{ width: 44, height: 44, alignItems: 'center', justifyContent: 'center' }}>
            <Plus size={18} color={c.onSurface} />
          </Pressable>
        </View>
      </View>
    </View>
  );
}

function Chip({ label, selected, onPress, trailing }: { label: string; selected: boolean; onPress: () => void; trailing?: React.ReactNode }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} accessibilityLabel={label} accessibilityState={{ selected }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 12, paddingVertical: 6, borderRadius: Radii.stadium, backgroundColor: selected ? Brand.seed : 'transparent', borderWidth: selected ? 0 : 1, borderColor: c.outlineVariant }}>
        <Text style={{ fontSize: 12 }} color={selected ? '#fff' : c.onSurfaceVariant}>{label}</Text>
        {selected ? trailing : null}
      </View>
    </Pressable>
  );
}
