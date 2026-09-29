import { useRouter } from 'expo-router';
import { ArrowLeftRight, ChevronDown, ChevronUp, FolderOpen, Lock, Monitor, RefreshCw, Search, Settings, Trash2, TriangleAlert } from 'lucide-react-native';
import { useState } from 'react';
import { View } from 'react-native';

import type { Drive } from '../../core/api/models';
import { formatSize } from '../../core/format';
import { sendWakeOnLan } from '../../core/native';
import type { Host, HostRoute } from '../../core/models/host';
import { routeForAddress } from '../../core/models/host';
import { usedFraction } from '../../core/storage/usage';
import { Button, ConfirmDialog, Menu, Pressable, Text, useToast } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { hostStore } from '../../services';
import { useActiveHost } from '../../state/activeHost';
import { relativeLabel } from './relative';
import { useHostStatus } from './useHostStatus';

const routeLabel = (r: HostRoute) =>
  r === 'lan' ? t('networkLan') : r === 'tailscale' ? t('networkTailscale') : r === 'directHttps' ? t('networkInternet') : 'Custom route';

/**
 * Host dashboard card: status dot, active route and version, drive gauges, quick actions.
 * Tapping opens the explorer when online, or sends Wake-on-LAN when offline and a MAC is known.
 * Long-press forgets the host.
 */
export function HostCard({
  host,
  isHero,
  lowDiskThresholdBytes = 0,
  onOnlineChanged,
  onChanged,
}: {
  host: Host;
  isHero?: boolean;
  lowDiskThresholdBytes?: number;
  onOnlineChanged?: (online: boolean) => void;
  onChanged: () => void;
}) {
  const c = useScheme();
  const router = useRouter();
  const toast = useToast();
  const setActive = useActiveHost((s) => s.setActive);
  const st = useHostStatus(host, onChanged);
  const [confirming, setConfirming] = useState(false);
  const { online, checking, health } = st;

  // report resolved status up to the list header
  const reported = useReportedOnline(checking, online, onOnlineChanged);
  void reported;

  const subtitle =
    !online || checking
      ? ''
      : [health?.version?.trim() ? `v${health.version.trim()}` : '', routeLabel(routeForAddress(host, st.activeAddress ?? host.address))].filter(Boolean).join(' · ');
  const statusLabel = checking ? t('checkingStatus') : online ? t('onlineStatus') : st.lastSeen ? t('statusOfflineLastSeen', { relative: relativeLabel(st.lastSeen) }) : t('offlineStatus');
  const statusColor = checking ? c.outline : online ? Brand.online : c.onSurfaceVariant;
  const readOnly = online && health?.readOnly === true;
  const lowDisk = online && lowDiskThresholdBytes > 0 && (st.drives ?? []).some((d) => d.freeBytes != null && d.freeBytes < lowDiskThresholdBytes);

  const openExplorer = () => {
    setActive({ host, health });
    router.navigate('/files');
  };
  const openTransfers = () => {
    setActive({ host, health: null });
    router.navigate('/transfers');
  };
  const wol = async () => {
    if (!host.macAddress) return;
    const sent = await sendWakeOnLan(host.macAddress).catch(() => false);
    if (sent) toast.info(t('wolPacketSent', { hostname: host.label }));
    else toast.error(t('wolPacketFailed'));
  };
  const onTap = checking || (!online && !host.macAddress) ? undefined : online ? openExplorer : wol;

  return (
    <>
      <View style={{ opacity: online ? 1 : 0.55 }}>
        <Pressable
          onPress={onTap}
          onLongPress={() => setConfirming(true)}
          accessibilityLabel={`${host.label}, ${statusLabel}`}
          style={{ padding: isHero ? Spacing.md3 : Spacing.md, backgroundColor: c.surfaceContainer, borderRadius: 24, borderWidth: 1, borderColor: c.outlineVariant }}
        >
          <View style={{ flexDirection: 'row', alignItems: 'flex-start' }}>
            <View style={{ width: 48, height: 48, borderRadius: 16, backgroundColor: c.surfaceContainerHigh, alignItems: 'center', justifyContent: 'center' }}>
              <Monitor size={24} color={online ? c.primary : c.onSurfaceVariant} />
            </View>
            <View style={{ flex: 1, marginLeft: Spacing.md }}>
              <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                <Text variant={isHero ? 'headlineSmall' : 'titleMedium'} numberOfLines={1} style={{ flexShrink: 1 }}>
                  {host.label}
                </Text>
                {readOnly && (
                  <View style={{ width: 32, height: 32, alignItems: 'center', justifyContent: 'center' }} accessibilityLabel="Read-only">
                    <Lock size={16} color={c.onSurfaceVariant} />
                  </View>
                )}
                {lowDisk && (
                  <View style={{ width: 32, height: 32, alignItems: 'center', justifyContent: 'center' }} accessibilityLabel={t('lowDiskWarning')}>
                    <TriangleAlert size={16} color={c.error} />
                  </View>
                )}
              </View>
              <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: Spacing.xs }} accessibilityLabel={subtitle ? `${statusLabel} · ${subtitle}` : statusLabel}>
                <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: statusColor, marginRight: Spacing.xs }} />
                <Text variant="labelMedium" muted numberOfLines={1}>{statusLabel}</Text>
                {subtitle ? <Text variant="bodySmall" muted numberOfLines={1} style={{ flex: 1, marginLeft: Spacing.sm }}>{subtitle}</Text> : null}
              </View>
            </View>
            <Pressable onPress={checking ? undefined : st.refresh} accessibilityLabel={t('refreshTooltip')} style={{ width: 48, height: 48, alignItems: 'center', justifyContent: 'center', opacity: checking ? 0.4 : 1 }}>
              <RefreshCw size={18} color={c.onSurfaceVariant} />
            </Pressable>
            <Menu
              accessibilityLabel={t('moreOptionsTooltip')}
              trigger={<DotsChip dimmed={!online} />}
              items={[
                { label: t('settingsMenuItem'), icon: <Settings size={16} color={c.onSurface} />, onPress: () => router.push({ pathname: '/host/[id]/settings', params: { id: host.id } }) },
                { label: t('forgetButton'), icon: <Trash2 size={16} color={c.error} />, destructive: true, onPress: () => setConfirming(true) },
              ]}
            />
          </View>
          {online && st.drives ? <DriveGauges drives={st.drives} /> : !online && !checking ? <Text variant="bodySmall" muted style={{ marginTop: Spacing.sm }}>Browse cached files while this computer is offline.</Text> : null}
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.sm, marginTop: Spacing.md }}>
            <Button kind="filled" disabled={checking} onPress={openExplorer} label={online ? t('openButton') : 'Browse cache'} renderIcon={(k) => <FolderOpen size={18} color={k} />} />
            <Button kind="tonal" disabled={!online || checking} onPress={() => router.push({ pathname: '/host/[id]/search', params: { id: host.id } })} label={t('searchButton')} renderIcon={(k) => <Search size={18} color={k} />} />
            <Button kind="tonal" onPress={openTransfers} label={t('transfersMenuItem')} renderIcon={(k) => <ArrowLeftRight size={18} color={k} />} />
            <Button kind="tonal" onPress={() => router.push({ pathname: '/host/[id]/settings', params: { id: host.id } })} label={t('settingsMenuItem')} renderIcon={(k) => <Settings size={18} color={k} />} />
            <Button kind="tonal" disabled={!online || checking} onPress={() => router.push({ pathname: '/host/[id]/apps', params: { id: host.id } })} label={t('hostAppsButton')} renderIcon={(k) => <Monitor size={18} color={k} />} />
          </View>
        </Pressable>
      </View>
      <ConfirmDialog
        visible={confirming}
        title={t('forgetComputerTitle')}
        description={t('forgetComputerConfirm', { hostLabel: host.label })}
        confirmLabel={t('forgetButton')}
        cancelLabel={t('cancelButton')}
        destructive
        onCancel={() => setConfirming(false)}
        onConfirm={async () => {
          setConfirming(false);
          await hostStore.removeHost(host.id);
          onChanged();
        }}
      />
    </>
  );
}

import { useEffect, useRef } from 'react';
function useReportedOnline(checking: boolean, online: boolean, cb?: (o: boolean) => void) {
  const last = useRef<boolean | null>(null);
  useEffect(() => {
    if (!checking && last.current !== online) {
      last.current = online;
      cb?.(online);
    }
  }, [checking, online, cb]);
  return last.current;
}

/** Mockup 3-dot chip surface (`.flt-orbits`). */
function DotsChip({ dimmed }: { dimmed: boolean }) {
  const c = useScheme();
  return (
    <View style={{ paddingHorizontal: 6, paddingVertical: 8, gap: 4, borderRadius: 9, borderWidth: 1, borderColor: `${c.onSurface}0D`, backgroundColor: `${c.onSurface}08` }}>
      {[0, 1, 2].map((i) => (
        <View key={i} style={{ width: 4, height: 4, borderRadius: 2, backgroundColor: c.onSurfaceVariant, opacity: dimmed ? 0.4 : 0.7 }} />
      ))}
    </View>
  );
}

/** Up to three real per-drive gauges with an expand affordance for machines reporting more volumes. */
function DriveGauges({ drives }: { drives: Drive[] }) {
  const c = useScheme();
  const [expanded, setExpanded] = useState(false);
  const usable = drives.filter((d) => usedFraction(d) !== null);
  if (usable.length === 0) return null;
  const visible = expanded ? usable : usable.slice(0, 3);
  return (
    <View style={{ marginTop: Spacing.md, gap: Spacing.sm }}>
      {visible.map((d) => {
        const f = usedFraction(d)!;
        const label = d.label ? d.label : d.path;
        return (
          <View key={d.path} accessible accessibilityLabel={label} accessibilityValue={{ text: `${Math.round(f * 100)}% used · ${formatSize(d.freeBytes)} free of ${formatSize(d.totalBytes)}` }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.sm }}>
              <Text variant="labelMedium" muted numberOfLines={1} style={{ flex: 1 }}>{label}</Text>
              <Text variant="bodySmall" muted>{`${formatSize(d.freeBytes)} free · ${formatSize(d.totalBytes)}`}</Text>
            </View>
            <View style={{ height: 8, marginTop: Spacing.xs, borderRadius: Radii.stadium, backgroundColor: c.tertiaryContainer, overflow: 'hidden' }}>
              <View style={{ width: `${f * 100}%`, height: 8, backgroundColor: c.tertiary }} />
            </View>
          </View>
        );
      })}
      {usable.length > 3 && (
        <Button
          kind="text"
          label={expanded ? 'Show fewer drives' : `+${usable.length - 3} more drives`}
          onPress={() => setExpanded((e) => !e)}
          renderIcon={(k) => (expanded ? <ChevronUp size={18} color={k} /> : <ChevronDown size={18} color={k} />)}
        />
      )}
    </View>
  );
}
