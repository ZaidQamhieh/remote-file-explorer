import { ArrowRight, QrCode } from 'lucide-react-native';
import { View } from 'react-native';
import Svg, { Rect } from 'react-native-svg';

import { GhostBlockButton, HintCard } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';

/** Static viewfinder placeholder (dashed 1.5px border, corner brackets) + button to the live scanner. */
export function QrPanel({ onOpenCamera }: { onOpenCamera: () => void }) {
  const c = useScheme();
  return (
    <View style={{ gap: Spacing.md2 + Spacing.xs }}>
      <View style={{ aspectRatio: 1, borderRadius: Radii.lg, backgroundColor: c.surface, alignItems: 'center', justifyContent: 'center' }}>
        <Svg width="100%" height="100%" style={{ position: 'absolute' }}>
          <Rect x={0.75} y={0.75} width="99.4%" height="99.4%" rx={Radii.lg} ry={Radii.lg} fill="none" stroke={c.outlineVariant} strokeWidth={1.5} strokeDasharray="6 4" />
        </Svg>
        <Brackets size={26} width={3} inset={16} color="#4C8DFF" />
        <QrCode size={64} color={c.onSurfaceVariant} style={{ opacity: 0.4 }} />
      </View>
      <GhostBlockButton label={t('openCameraViewfinder')} icon={<ArrowRight size={16} color={c.onSurface} />} onPress={onOpenCamera} />
      <HintCard text={t('pairingHint')} />
    </View>
  );
}

/** Four L-shaped corner brackets (the mockup's QR viewfinder chrome). */
export function Brackets({ size, width, inset, color }: { size: number; width: number; inset: number; color: string }) {
  const corner = (top: boolean, left: boolean) => (
    <View
      key={`${top}${left}`}
      style={{
        position: 'absolute',
        [top ? 'top' : 'bottom']: inset,
        [left ? 'left' : 'right']: inset,
        width: size,
        height: size,
        borderColor: color,
        [top ? 'borderTopWidth' : 'borderBottomWidth']: width,
        [left ? 'borderLeftWidth' : 'borderRightWidth']: width,
      }}
    />
  );
  return <>{[corner(true, true), corner(true, false), corner(false, true), corner(false, false)]}</>;
}
