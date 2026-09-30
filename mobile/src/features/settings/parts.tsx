import { ChevronRight, type LucideIcon } from 'lucide-react-native';
import { Fragment, type ReactNode } from 'react';
import { View } from 'react-native';

import { GroupedCard, MockupSwitch, Pressable, SectionLabel, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { FontFamily, Radii, Spacing } from '../../design/tokens';

/** A labelled group: the section header, then one card whose rows are split by hairlines. */
export function SettingsSection({ title, children, trailing }: { title: string; children: ReactNode; trailing?: ReactNode }) {
  const c = useScheme();
  const rows = (Array.isArray(children) ? children.flat(Infinity) : [children]).filter(Boolean) as ReactNode[];
  return (
    <View>
      <View style={{ paddingHorizontal: Spacing.xs }}>
        <SectionLabel title={title} trailing={trailing} />
      </View>
      <GroupedCard>
        {rows.map((row, i) => (
          <Fragment key={i}>
            {i > 0 && <View style={{ height: 1, backgroundColor: c.outlineVariant }} />}
            {row}
          </Fragment>
        ))}
      </GroupedCard>
    </View>
  );
}

/** The 38dp tinted square that leads a settings row. */
export function RowBadge({ icon: Icon, tint }: { icon: LucideIcon; tint: string }) {
  return (
    <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: `${tint}26`, alignItems: 'center', justifyContent: 'center' }}>
      <Icon size={18} color={tint} />
    </View>
  );
}

type RowBase = { icon: LucideIcon; title: string; subtitle?: string; tint?: string };

function RowBody({ icon, title, subtitle, tint, trailing }: RowBase & { trailing?: ReactNode }) {
  const c = useScheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 11 }}>
      <RowBadge icon={icon} tint={tint ?? c.onSurfaceVariant} />
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 14, fontFamily: FontFamily.medium }}>{title}</Text>
        {subtitle ? <Text muted style={{ fontSize: 11.5, marginTop: 1 }}>{subtitle}</Text> : null}
      </View>
      {trailing}
    </View>
  );
}

/** A row that only displays a fact. */
export function InfoRow(p: RowBase) {
  return <RowBody {...p} />;
}

/** A row that opens something. */
export function NavRow({ onPress, ...p }: RowBase & { onPress: () => void }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} accessibilityLabel={p.title}>
      <RowBody {...p} trailing={<ChevronRight size={16} color={c.onSurfaceVariant} />} />
    </Pressable>
  );
}

/** A row showing its current value; tapping picks a new one. */
export function ValueRow({ onPress, value, ...p }: RowBase & { onPress: () => void; value: string }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} accessibilityLabel={`${p.title}, ${value}`}>
      <RowBody
        {...p}
        trailing={
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
            <Text muted style={{ fontSize: 13.5 }} numberOfLines={1}>{value}</Text>
            <ChevronRight size={16} color={c.onSurfaceVariant} />
          </View>
        }
      />
    </Pressable>
  );
}

/** A row with a switch; the whole row toggles. */
export function ToggleRow({ value, onChange, disabled, ...p }: RowBase & { value: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <Pressable onPress={disabled ? undefined : () => onChange(!value)} disabled={disabled} accessibilityRole="switch" accessibilityLabel={p.title} accessibilityState={{ checked: value, disabled: !!disabled }} style={{ opacity: disabled ? 0.5 : 1 }}>
      <RowBody {...p} trailing={<MockupSwitch value={value} />} />
    </Pressable>
  );
}

/** A plain labelled switch used inside a row (device grants). */
export function SmallSwitchRow({ label, subtitle, value, onChange, disabled }: { label: string; subtitle?: string; value: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <Pressable onPress={disabled ? undefined : () => onChange(!value)} disabled={disabled} accessibilityRole="switch" accessibilityLabel={label} accessibilityState={{ checked: value, disabled: !!disabled }} style={{ opacity: disabled ? 0.5 : 1 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 6 }}>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 13.5 }}>{label}</Text>
          {subtitle ? <Text muted style={{ fontSize: 11.5 }}>{subtitle}</Text> : null}
        </View>
        <MockupSwitch value={value} />
      </View>
    </Pressable>
  );
}
