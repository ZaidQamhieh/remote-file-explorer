import { Check, Pin as PinIcon, Star } from 'lucide-react-native';
import { View } from 'react-native';

import type { Entry } from '../../core/api/models';
import { Pressable, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, Radii, Spacing } from '../../design/tokens';
import { EntryLeading, useIconChipBg } from './EntryIcon';
import { Thumbnail } from './Thumbnail';

export function EntryGridCell({
  entry, hostId, selected, multiSelect, isFavorite, isPinned, onPress, onLongPress, onPeek,
}: {
  entry: Entry; hostId: string; selected: boolean; multiSelect: boolean; isFavorite?: boolean; isPinned?: boolean;
  onPress: () => void; onLongPress: () => void; onPeek?: () => void;
}) {
  const c = useScheme();
  const chip = useIconChipBg(entry);
  const isImage = !entry.isDir && (entry.mimeType ?? '').startsWith('image/');
  const fallback = (
    <View style={{ width: 56, height: 56, borderRadius: Radii.chip, backgroundColor: chip, alignItems: 'center', justifyContent: 'center' }}>
      <EntryLeading entry={entry} size={32} />
    </View>
  );
  const thumb = isImage ? <Thumbnail hostId={hostId} entry={entry} size={256} style={{ width: 56, height: 56, borderRadius: Radii.chip }} fallback={fallback} /> : fallback;
  const badge = (pos: object, children: React.ReactNode) => (
    <View style={{ position: 'absolute', width: 18, height: 18, borderRadius: 9, backgroundColor: c.surface, alignItems: 'center', justifyContent: 'center', ...pos }}>{children}</View>
  );
  return (
    <Pressable
      onPress={onPress}
      onLongPress={onLongPress}
      accessibilityLabel={entry.name}
      accessibilityState={{ selected }}
      style={{ flex: 1, minHeight: 132, padding: Spacing.sm, alignItems: 'center', justifyContent: 'center', backgroundColor: selected ? `${c.secondaryContainer}A6` : c.surfaceContainerLow, borderRadius: Radii.card, borderWidth: selected ? 3 : 1, borderColor: selected ? c.primary : c.outlineVariant }}
    >
      {!multiSelect && !entry.isDir && onPeek ? <Pressable onLongPress={onPeek} style={{}}>{thumb}</Pressable> : thumb}
      <Text variant="titleSmall" numberOfLines={2} style={{ textAlign: 'center', marginTop: Spacing.sm }}>{entry.name}</Text>
      {selected && badge({ top: 0, right: 0, width: 22, height: 22, borderRadius: 11, backgroundColor: c.primary }, <Check size={16} color={c.onPrimary} />)}
      {isFavorite && entry.isDir && badge({ top: 0, left: 0 }, <Star size={13} color={Brand.amber} />)}
      {isPinned && entry.isDir && badge({ bottom: 0, left: 0 }, <PinIcon size={12} color={c.primary} />)}
    </Pressable>
  );
}
