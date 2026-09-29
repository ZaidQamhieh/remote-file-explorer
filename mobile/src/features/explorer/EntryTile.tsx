import { Check, ChevronRight, Pin as PinIcon, Star } from 'lucide-react-native';
import { View } from 'react-native';

import type { Entry } from '../../core/api/models';
import { formatDate, formatSize } from '../../core/format';
import { Pressable, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { EntryLeading, useIconChipBg } from './EntryIcon';
import { Thumbnail } from './Thumbnail';
import type { EntryDensity } from './sort';

export function entryMeta(e: Entry): string {
  if (e.isDir) return '';
  const parts: string[] = [];
  const size = formatSize(e.size);
  if (size) parts.push(size);
  if (e.modified) parts.push(formatDate(new Date(e.modified)));
  return parts.join('  ·  ');
}

export function EntryTile({
  entry, hostId, selected, multiSelect, density = 'comfortable', isFavorite, isPinned, onPress, onLongPress, onSelect, onShowMeta, onBookmark, onPeek,
}: {
  entry: Entry; hostId: string; selected: boolean; multiSelect: boolean; density?: EntryDensity; isFavorite?: boolean; isPinned?: boolean;
  onPress: () => void; onLongPress: () => void; onSelect: () => void; onShowMeta?: () => void; onBookmark?: () => void; onPeek?: () => void;
}) {
  const c = useScheme();
  const compact = density === 'compact';
  const meta = entryMeta(entry);
  const size = compact ? 32 : 40;
  const chip = useIconChipBg(entry);
  const isImage = !entry.isDir && (entry.mimeType ?? '').startsWith('image/');

  const icon = (
    <View style={{ width: size, height: size }}>
      {isImage ? (
        <Thumbnail hostId={hostId} entry={entry} size={128} style={{ width: size, height: size, borderRadius: Radii.sm }} fallback={<Chip size={size} bg={chip}><EntryLeading entry={entry} size={size * 0.55} /></Chip>} />
      ) : (
        <Chip size={size} bg={chip}>
          <EntryLeading entry={entry} size={size * 0.55} />
        </Chip>
      )}
      {isFavorite && entry.isDir && <Badge right top><Star size={12} color={Brand.amber} /></Badge>}
      {isPinned && entry.isDir && <Badge right bottom><PinIcon size={11} color={c.primary} /></Badge>}
    </View>
  );

  return (
    <Pressable
      onPress={onPress}
      onLongPress={!multiSelect && onBookmark ? onBookmark : onLongPress}
      accessibilityLabel={`${entry.name}${meta ? `, ${meta}` : ''}`}
      accessibilityState={{ selected }}
      style={{ backgroundColor: selected ? `${c.primary}24` : 'transparent', paddingHorizontal: Spacing.md, paddingVertical: compact ? Spacing.xs : Spacing.sm, flexDirection: 'row', alignItems: 'center', gap: Spacing.md }}
    >
      {multiSelect ? <SelBox checked={selected} onPress={onSelect} /> : !entry.isDir && onPeek ? <Pressable onLongPress={onPeek} style={{}}>{icon}</Pressable> : icon}
      <View style={{ flex: 1 }}>
        {compact ? (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.sm }}>
            <Text variant="titleMedium" numberOfLines={1} style={{ flex: 1 }}>{entry.name}</Text>
            {meta ? <Text variant="bodySmall" muted numberOfLines={1}>{meta}</Text> : null}
          </View>
        ) : (
          <View>
            <Text variant="titleMedium" numberOfLines={1}>{entry.name}</Text>
            {meta ? <Text variant="bodySmall" muted numberOfLines={1} style={{ marginTop: 2 }}>{meta}</Text> : null}
          </View>
        )}
      </View>
      {entry.isDir &&
        (onShowMeta ? (
          <Pressable onPress={onShowMeta} pressedScale={0.92} accessibilityLabel={t('folderDetailsTooltip')} style={{ width: 44, height: 44, alignItems: 'center', justifyContent: 'center' }}>
            <ChevronRight size={18} color={c.primary} />
          </Pressable>
        ) : (
          <ChevronRight size={24} color={c.primary} />
        ))}
    </Pressable>
  );
}

function Chip({ size, bg, children }: { size: number; bg: string; children: React.ReactNode }) {
  return <View style={{ width: size, height: size, borderRadius: Radii.sm, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>{children}</View>;
}

function Badge({ children, top, bottom, right }: { children: React.ReactNode; top?: boolean; bottom?: boolean; right?: boolean }) {
  const c = useScheme();
  return (
    <View style={{ position: 'absolute', width: 16, height: 16, borderRadius: 8, backgroundColor: c.surface, alignItems: 'center', justifyContent: 'center', ...(top ? { top: -4 } : {}), ...(bottom ? { bottom: -4 } : {}), ...(right ? { right: -4 } : {}) }}>{children}</View>
  );
}

export function SelBox({ checked, onPress }: { checked: boolean; onPress: () => void }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} accessibilityRole="checkbox" accessibilityState={{ checked }} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
      <View style={{ width: 20, height: 20, borderRadius: 6, backgroundColor: checked ? Brand.seed : 'transparent', borderWidth: checked ? 0 : 1.5, borderColor: c.outlineVariant, alignItems: 'center', justifyContent: 'center' }}>
        {checked ? <Check size={13} color="#fff" /> : null}
      </View>
    </Pressable>
  );
}
