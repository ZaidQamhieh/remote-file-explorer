import { Folder, HardDrive, ShieldX } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { ScrollView, View } from 'react-native';

import type { AgentStatus, Drive, Health } from '../../core/api/models';
import { formatSize } from '../../core/format';
import type { Host } from '../../core/models/host';
import { AppBar, EmptyState, OfflineBanner, ErrorRetry, GroupedCard, ListingSkeleton, Loading, Pressable, SectionLabel, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Radii, Spacing } from '../../design/tokens';
import { AgentApiError } from '../../core/api/agentClient';
import { clientForHost, keyValue } from '../../services';
import { humanizeError } from '../pairing/pairingService';
import { t } from '../../i18n';
import { folderLabel } from './paths';
import { resolveRoots, type RootResolution } from './rootResolution';
import { loadRoots, saveRoots } from './rootsCache';

/** Resolves what this device may browse on a host (allowed roots, Windows drives, or nothing) and lets the user pick a root. */
export function HostRootView({ host, health, initialPath, onSelectRoot }: { host: Host; health: Health | null; initialPath?: string; onSelectRoot: (root: string, initialPath?: string) => void }) {
  const [res, setRes] = useState<RootResolution | null>(null);
  const [drives, setDrives] = useState<Drive[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [offline, setOffline] = useState(false);

  const load = useCallback(() => {
    let live = true;
    (async () => {
      const client = await clientForHost(host);
      try {
        const settings: AgentStatus = await client.status();
        const r = resolveRoots(settings, health, initialPath);
        const drives = r.kind === 'drives' ? await client.drives() : null;
        if (!settings.accessDenied) await saveRoots(keyValue, host.id, { roots: settings.roots, os: health?.os, drives: drives ?? undefined }).catch(() => {});
        return { r, drives, offline: false };
      } catch (e) {
        // Unreachable host: fall back to what it last allowed, so cached listings stay browsable.
        const cached = e instanceof AgentApiError && e.code === 'CONNECTION' ? await loadRoots(keyValue, host.id) : null;
        if (!cached) throw e;
        return { r: resolveRoots({ roots: cached.roots, accessDenied: false }, health ?? (cached.os ? { os: cached.os } : null), initialPath), drives: cached.drives ?? null, offline: true };
      }
    })().then(
      ({ r, drives, offline: off }) => {
        if (!live) return;
        setOffline(off);
        if (r.kind === 'select') return onSelectRoot(r.rootPath, r.initialPath);
        setDrives(drives);
        setRes(r);
      },
      (e) => live && setError(humanizeError(e)),
    );
    return () => {
      live = false;
    };
  }, [host, health, initialPath, onSelectRoot]);
  useEffect(() => load(), [load]);

  if (error) return <Shell host={host}><ErrorRetry
          message={t('errorLabel', { error })}
          onRetry={() => {
            setError(null);
            setRes(null);
            load();
          }}
        /></Shell>;
  if (!res) return <Shell host={host}><Loading /></Shell>;
  if (res.kind === 'denied') return <Shell host={host}><Denied /></Shell>;
  const banner = offline ? <OfflineBanner text={t('offlineBannerText')} /> : null;
  if (res.kind === 'drives') return <Shell host={host}>{banner}{drives === null ? <ListingSkeleton /> : drives.length === 0 ? <EmptyState /> : <DrivesList drives={drives} onSelect={(p) => onSelectRoot(p)} />}</Shell>;
  if (res.kind === 'roots') return <Shell host={host} subtitle="Shared folders">{banner}<Roots roots={res.roots} unavailablePath={res.unavailablePath} onSelect={(r) => onSelectRoot(r)} /></Shell>;
  return null;
}

function Shell({ host, subtitle, children }: { host: Host; subtitle?: string; children: React.ReactNode }) {
  return (
    <View style={{ flex: 1 }}>
      <AppBar title={host.label} subtitle={subtitle} tall />
      <View style={{ flex: 1 }}>{children}</View>
    </View>
  );
}

function Denied() {
  const c = useScheme();
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: Spacing.lg, gap: Spacing.md }}>
      <ShieldX size={48} color={c.error} />
      <Text style={{ textAlign: 'center' }}>This device has no file access on this computer.</Text>
    </View>
  );
}

function Roots({ roots, unavailablePath, onSelect }: { roots: string[]; unavailablePath?: string; onSelect: (r: string) => void }) {
  const c = useScheme();
  const sorted = [...roots].sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
  return (
    <ScrollView contentContainerStyle={{ padding: Spacing.md, gap: Spacing.md }}>
      {unavailablePath ? <Text color={c.error}>This saved location is no longer available to this device. Choose a shared folder below.</Text> : null}
      <View>
        <SectionLabel title="Available folders" />
        <GroupedCard padded={false}>
          {sorted.map((r, i) => (
            <Pressable key={r} onPress={() => onSelect(r)} accessibilityLabel={folderLabel(r)}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16, paddingHorizontal: Spacing.md, paddingVertical: 10, borderTopWidth: i ? 1 : 0, borderColor: c.outlineVariant }}>
                <Folder size={22} color={c.onSurfaceVariant} />
                <View style={{ flex: 1 }}>
                  <Text variant="bodyLarge" numberOfLines={1}>{folderLabel(r)}</Text>
                  <Text variant="bodySmall" muted numberOfLines={1}>{r}</Text>
                </View>
              </View>
            </Pressable>
          ))}
        </GroupedCard>
      </View>
    </ScrollView>
  );
}

function DrivesList({ drives, onSelect }: { drives: Drive[]; onSelect: (p: string) => void }) {
  const c = useScheme();
  return (
    <ScrollView contentContainerStyle={{ padding: Spacing.md }}>
      <GroupedCard padded={false}>
        {drives.map((d, i) => {
          const label = d.label ? d.label : folderLabel(d.path);
          const cap = d.totalBytes != null && d.freeBytes != null;
          return (
            <Pressable key={d.path} onPress={() => onSelect(d.path)} accessibilityLabel={label}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16, paddingHorizontal: Spacing.md, paddingVertical: 10, borderTopWidth: i ? 1 : 0, borderColor: c.outlineVariant }}>
                <View style={{ width: 40, height: 40, borderRadius: Radii.sm, backgroundColor: c.surfaceContainerHighest, alignItems: 'center', justifyContent: 'center' }}>
                  <HardDrive size={20} color={c.onSurfaceVariant} />
                </View>
                <View style={{ flex: 1 }}>
                  <Text variant="bodyLarge" numberOfLines={1}>{label}</Text>
                  <Text variant="bodySmall" muted numberOfLines={1}>{cap ? `${formatSize(d.freeBytes)} free of ${formatSize(d.totalBytes)}  ·  ${d.path}` : d.path}</Text>
                </View>
              </View>
            </Pressable>
          );
        })}
      </GroupedCard>
    </ScrollView>
  );
}
