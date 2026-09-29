import { ArrowLeft, CircleAlert, File as FileIcon, MoreVertical, RefreshCw, Share2 } from 'lucide-react-native';
import type { ReactNode } from 'react';
import { ActivityIndicator, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { Entry } from '../../core/api/models';
import { formatSize } from '../../core/format';
import { Pressable, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { FontFamily, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';

/** The mockup `.iconbtn` (34x34, 19px glyph), colour-adjustable for dark media canvases. */
export function PreviewIconButton({ label, onPress, selected, children }: { label: string; onPress: () => void; selected?: boolean; children: ReactNode }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} accessibilityLabel={label} accessibilityState={selected === undefined ? undefined : { selected }} pressedScale={0.9}>
      <View style={{ width: 34, height: 34, borderRadius: Radii.stadium, alignItems: 'center', justifyContent: 'center', backgroundColor: selected ? `${c.primary}24` : 'transparent' }}>{children}</View>
    </Pressable>
  );
}

/**
 * Port of PreviewTopBar: back, name + size, per-viewer actions, then Share and "…". On image/video
 * it floats as translucent black with white foreground over the media.
 */
export function PreviewTopBar({ entry, onDark, onBack, onShare, onMore, leading }: { entry: Entry; onDark: boolean; onBack: () => void; onShare: () => void; onMore: () => void; leading?: ReactNode }) {
  const c = useScheme();
  const insets = useSafeAreaInsets();
  const fg = onDark ? '#FFFFFF' : c.onSurface;
  const dim = onDark ? 'rgba(255,255,255,0.7)' : c.onSurfaceVariant;
  const size = formatSize(entry.size);
  return (
    <View style={{ paddingTop: insets.top + 6, paddingBottom: 8, paddingHorizontal: 12, flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: onDark ? 'rgba(0,0,0,0.45)' : c.surface }}>
      <PreviewIconButton label="Back" onPress={onBack}>
        <ArrowLeft size={19} color={fg} />
      </PreviewIconButton>
      <View style={{ flex: 1, marginLeft: 4 }}>
        <Text numberOfLines={1} style={{ fontSize: 15.5, fontFamily: FontFamily.semibold, color: fg }}>{entry.name}</Text>
        {size ? <Text numberOfLines={1} style={{ fontSize: 11.5, color: dim }}>{size}</Text> : null}
      </View>
      {leading}
      <PreviewIconButton label="Share" onPress={onShare}>
        <Share2 size={19} color={fg} />
      </PreviewIconButton>
      <PreviewIconButton label={t('moreTooltip')} onPress={onMore}>
        <MoreVertical size={19} color={fg} />
      </PreviewIconButton>
    </View>
  );
}

export function PreviewLoading({ message, onDark }: { message?: string; onDark?: boolean }) {
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: Spacing.md }}>
      <ActivityIndicator color={onDark ? '#FFFFFF' : undefined} />
      {message ? <Text muted color={onDark ? 'rgba(255,255,255,0.8)' : undefined}>{message}</Text> : null}
    </View>
  );
}

export function PreviewError({ message, onRetry, onDark }: { message: string; onRetry?: () => void; onDark?: boolean }) {
  const c = useScheme();
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: Spacing.lg, gap: Spacing.md }}>
      <CircleAlert size={48} color={c.error} />
      <Text style={{ textAlign: 'center' }} color={onDark ? '#FFFFFF' : undefined}>{message}</Text>
      {onRetry ? (
        <Pressable onPress={onRetry} pressedScale={0.97} accessibilityLabel={t('retryButton')}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 18, paddingVertical: 11, borderRadius: Radii.sm, borderWidth: 1, borderColor: c.outlineVariant, backgroundColor: c.surfaceContainerHigh }}>
            <Text style={{ fontSize: 13.5, fontFamily: FontFamily.semibold }}>{t('retryButton')}</Text>
            <RefreshCw size={16} color={c.onSurface} />
          </View>
        </Pressable>
      ) : null}
    </View>
  );
}

export function PreviewTooLarge({ size, onDark }: { size: number; onDark?: boolean }) {
  const c = useScheme();
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: Spacing.lg, gap: Spacing.md }}>
      <FileIcon size={48} color={c.outline} />
      <Text style={{ textAlign: 'center' }} color={onDark ? '#FFFFFF' : undefined}>{t('fileTooLargeToPreview', { sizeLabel: formatSize(size) })}</Text>
    </View>
  );
}
