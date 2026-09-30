import { Stack, useLocalSearchParams } from 'expo-router';
import { Ban, CircleDot, Link as LinkIcon, Link2Off, LogIn, RefreshCw, ScrollText, Settings2, ShieldAlert, Smartphone, Trash2, UserPlus, type LucideIcon } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, RefreshControl, View } from 'react-native';

import { AgentApiError } from '../../../core/api/agentClient';
import type { AuditEntry } from '../../../core/api/models';
import { formatRelative } from '../../../core/format';
import { ErrorRetry, Text } from '../../../design/components';
import { useScheme } from '../../../design/theme';
import { Brand, FontFamily, Spacing } from '../../../design/tokens';
import { auditLabel } from '../../../features/settings/hostSettingsLogic';
import { humanizeError } from '../../../features/pairing/pairingService';
import { t } from '../../../i18n';
import { clientForHost, hostStore } from '../../../services';

const VISUALS: Record<string, { icon: LucideIcon; tint: (c: ReturnType<typeof useScheme>) => string }> = {
  pair: { icon: Smartphone, tint: () => Brand.online },
  register: { icon: UserPlus, tint: () => Brand.online },
  login: { icon: LogIn, tint: (c) => c.primary },
  login_failed: { icon: ShieldAlert, tint: (c) => c.error },
  device_revoked: { icon: Ban, tint: (c) => c.error },
  device_removed: { icon: Trash2, tint: (c) => c.error },
  device_updated: { icon: Settings2, tint: () => Brand.amber },
  share_created: { icon: LinkIcon, tint: () => Brand.accent },
  share_revoked: { icon: Link2Off, tint: () => Brand.amber },
  agent_restart: { icon: RefreshCw, tint: (c) => c.primary },
};

/** The host's activity log: pairings, logins, device changes and share links, newest first. Owner-only on the agent. */
export default function Audit() {
  const c = useScheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const [entries, setEntries] = useState<AuditEntry[] | null>(null);
  const [error, setError] = useState<{ message: string; adminOnly: boolean } | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const fetchEntries = useCallback(async (): Promise<{ entries: AuditEntry[] } | { error: { message: string; adminOnly: boolean } }> => {
    try {
      const host = (await hostStore.listHosts()).find((h) => h.id === id);
      if (!host) return { error: { message: 'This computer is no longer paired.', adminOnly: false } };
      return { entries: await (await clientForHost(host)).audit() };
    } catch (e) {
      return { error: { message: humanizeError(e), adminOnly: e instanceof AgentApiError && e.statusCode === 403 } };
    }
  }, [id]);
  const apply = useCallback((r: Awaited<ReturnType<typeof fetchEntries>>) => {
    if ('entries' in r) {
      setEntries(r.entries);
      setError(null);
    } else setError(r.error);
  }, []);
  useEffect(() => {
    let live = true;
    void fetchEntries().then((r) => live && apply(r));
    return () => {
      live = false;
    };
  }, [apply, fetchEntries]);

  const notice = (message: string) => (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 12 }}>
      <ScrollText size={56} color={c.onSurfaceVariant} />
      <Text muted style={{ textAlign: 'center' }}>{message}</Text>
    </View>
  );

  let body: React.ReactNode;
  if (error) body = error.adminOnly ? notice(t('activityLogAdminOnly')) : <ErrorRetry message={error.message} onRetry={() => void fetchEntries().then(apply)} />;
  else if (entries === null) body = <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator /></View>;
  else if (entries.length === 0) body = notice(t('activityLogEmpty'));
  else {
    body = (
      <FlatList
        data={entries}
        keyExtractor={(e) => String(e.id)}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={async () => {
              setRefreshing(true);
              apply(await fetchEntries());
              setRefreshing(false);
            }}
          />
        }
        contentContainerStyle={{ paddingHorizontal: Spacing.md, paddingTop: Spacing.sm, paddingBottom: Spacing.xl }}
        renderItem={({ item }) => <Row entry={item} />}
      />
    );
  }
  return (
    <View style={{ flex: 1 }}>
      <Stack.Screen options={{ title: t('activityLogTitle') }} />
      {body}
    </View>
  );
}

function Row({ entry }: { entry: AuditEntry }) {
  const c = useScheme();
  const v = VISUALS[entry.action];
  const Icon = v?.icon ?? CircleDot;
  const tint = v ? v.tint(c) : c.onSurfaceVariant;
  const sub = [entry.actor, entry.target, entry.detail].filter(Boolean).join(' · ');
  return (
    <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: Spacing.sm, paddingVertical: Spacing.xs }}>
      <View style={{ width: 38, height: 38, borderRadius: 10, backgroundColor: `${tint}1F`, alignItems: 'center', justifyContent: 'center' }}>
        <Icon size={18} color={tint} />
      </View>
      <View style={{ flex: 1 }}>
        <Text style={{ fontFamily: FontFamily.semibold }}>{auditLabel(entry.action)}</Text>
        {sub ? <Text muted style={{ fontSize: 12 }}>{sub}</Text> : null}
      </View>
      <Text muted style={{ fontSize: 12 }}>{formatRelative(entry.at)}</Text>
    </View>
  );
}
