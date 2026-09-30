import { useState } from 'react';
import { FlatList, View } from 'react-native';

import { Pressable, SectionLabel, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { FontFamily, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { bundledPackages, licenseText, nativeComponents } from '../../features/support/licenses';

/** Open-source licenses of everything built into the app. Tap a package to read its license text. */
export default function Licenses() {
  const c = useScheme();
  const [open, setOpen] = useState<string | null>(null);
  return (
    <FlatList
      data={bundledPackages}
      keyExtractor={(p) => `${p.n}@${p.v}`}
      contentContainerStyle={{ padding: Spacing.md, gap: 4 }}
      ListHeaderComponent={
        <View style={{ gap: 6, marginBottom: Spacing.sm }}>
          <Text muted>{t('licensesIntro')}</Text>
          <SectionLabel title={t('licensesNative')} />
          {nativeComponents.map((n) => (
            <View key={n.name} style={{ paddingVertical: 4 }}>
              <Text style={{ fontSize: 13.5 }}>{n.name}</Text>
              <Text muted style={{ fontSize: 11.5 }}>{n.license}</Text>
            </View>
          ))}
          <SectionLabel title={t('licensesPackages', { count: bundledPackages.length })} />
        </View>
      }
      renderItem={({ item }) => {
        const key = `${item.n}@${item.v}`;
        const expanded = open === key;
        const text = licenseText(item.t);
        return (
          <Pressable onPress={() => setOpen(expanded ? null : key)} accessibilityRole="button" accessibilityLabel={`${item.n} ${item.v}, ${item.l}`} accessibilityState={{ expanded }}>
            <View style={{ paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: c.outlineVariant }}>
              <Text style={{ fontSize: 13.5, fontFamily: FontFamily.medium }}>{item.n}</Text>
              <Text muted style={{ fontSize: 11.5 }}>{`${item.v} · ${item.l}`}</Text>
              {expanded ? <Text style={{ fontSize: 11, marginTop: 8, fontFamily: FontFamily.mono }}>{text ?? t('licenseTextMissing', { license: item.l })}</Text> : null}
            </View>
          </Pressable>
        );
      }}
    />
  );
}
