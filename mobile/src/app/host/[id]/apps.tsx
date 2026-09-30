import { Stack, useLocalSearchParams } from 'expo-router';
import { Code, FileText, Globe, Monitor, Play, RefreshCw, SearchX, Settings, ShieldAlert, Terminal, type LucideIcon } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, RefreshControl, View } from 'react-native';

import { AgentApiError } from '../../../core/api/agentClient';
import type { HostApp, HostAppCatalog } from '../../../core/api/models';
import { AppBarIconButton, Button, ErrorRetry, GroupedCard, HintCard, SearchBar, Text, useToast } from '../../../design/components';
import { useScheme } from '../../../design/theme';
import { Brand, FontFamily, Spacing } from '../../../design/tokens';
import { filterApps, launchFailure, platformKey, safeIcon, type IconKey } from '../../../features/apps/appsLogic';
import { humanizeError } from '../../../features/pairing/pairingService';
import { t } from '../../../i18n';
import { clientForHost, hostStore } from '../../../services';

const ICONS: Record<IconKey, LucideIcon> = { browser: Globe, code: Code, office: FileText, media: Play, terminal: Terminal, system: Settings, monitor: Monitor };

type Failure = { kind: 'denied' | 'unsupported' | 'error'; message: string };
type Load = { catalog: HostAppCatalog } | { failure: Failure };

/** Apps the computer chose to expose. Launch sends only the server-issued id; the agent re-checks it. */
export default function HostApps() {
  const c = useScheme();
  const toast = useToast();
  const { id } = useLocalSearchParams<{ id: string }>();
  const [hostLabel, setHostLabel] = useState('');
  const [catalog, setCatalog] = useState<HostAppCatalog | null>(null);
  const [failure, setFailure] = useState<Failure | null>(null);
  const [query, setQuery] = useState('');
  const [launching, setLaunching] = useState<ReadonlySet<string>>(new Set());
  const [refreshing, setRefreshing] = useState(false);

  const fetchCatalog = useCallback(async (): Promise<Load & { label?: string }> => {
    try {
      const host = (await hostStore.listHosts()).find((h) => h.id === id);
      if (!host) return { failure: { kind: 'error', message: 'This computer is no longer paired.' } };
      return { catalog: await (await clientForHost(host)).listApps(), label: host.label };
    } catch (e) {
      if (e instanceof AgentApiError && e.statusCode === 403) return { failure: { kind: 'denied', message: '' } };
      if (e instanceof AgentApiError && e.code === 'APP_CATALOG_UNSUPPORTED') return { failure: { kind: 'unsupported', message: t('hostAppsUnsupported') } };
      return { failure: { kind: 'error', message: `${t('hostAppsLoadFailed')}\n${humanizeError(e)}` } };
    }
  }, [id]);
  const apply = useCallback((r: Load & { label?: string }) => {
    if ('catalog' in r) {
      setCatalog(r.catalog);
      setFailure(null);
      if (r.label) setHostLabel(r.label);
    } else {
      setFailure(r.failure);
    }
  }, []);
  useEffect(() => {
    let live = true;
    void fetchCatalog().then((r) => live && apply(r));
    return () => {
      live = false;
    };
  }, [apply, fetchCatalog]);

  const reload = () => {
    setCatalog(null);
    setFailure(null);
    void fetchCatalog().then(apply);
  };

  const launch = async (app: HostApp) => {
    if (launching.has(app.id)) return;
    setLaunching((s) => new Set(s).add(app.id));
    try {
      const host = (await hostStore.listHosts()).find((h) => h.id === id);
      if (!host) throw new Error('unpaired');
      await (await clientForHost(host)).launchApp(app.id);
      toast.success(t('hostAppLaunchStarted', { appName: app.name, hostLabel: host.label }));
    } catch (e) {
      const f = launchFailure(e);
      toast.error(t(f.key, { appName: app.name }));
      if (f.refresh) void fetchCatalog().then(apply);
    } finally {
      setLaunching((s) => {
        const next = new Set(s);
        next.delete(app.id);
        return next;
      });
    }
  };

  const centered = (icon: React.ReactNode, title: string, message: string, action?: React.ReactNode) => (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: Spacing.xl, gap: Spacing.md }}>
      {icon}
      <Text variant="titleMedium" style={{ textAlign: 'center' }}>{title}</Text>
      <Text muted style={{ textAlign: 'center' }}>{message}</Text>
      {action}
    </View>
  );

  let body: React.ReactNode;
  if (failure?.kind === 'denied') {
    body = centered(<ShieldAlert size={48} color={c.primary} />, t('hostAppsAccessDeniedTitle'), t('hostAppsAccessDeniedMessage'), <Button kind="tonal" label={t('retryButton')} onPress={reload} />);
  } else if (failure) {
    body = <ErrorRetry message={failure.message} onRetry={reload} />;
  } else if (catalog === null) {
    body = (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: Spacing.md }}>
        <ActivityIndicator />
        <Text muted>{t('hostAppsLoading')}</Text>
      </View>
    );
  } else if (catalog.apps.length === 0) {
    body = centered(<Monitor size={48} color={c.onSurfaceVariant} />, t('hostAppsEmptyTitle'), t('hostAppsEmptyMessage'));
  } else {
    const shown = filterApps(catalog.apps, query);
    body = (
      <FlatList
        data={shown}
        keyExtractor={(a) => a.id}
        keyboardShouldPersistTaps="handled"
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={async () => {
              setRefreshing(true);
              apply(await fetchCatalog());
              setRefreshing(false);
            }}
          />
        }
        contentContainerStyle={{ padding: Spacing.md, gap: Spacing.sm, paddingBottom: Spacing.xl }}
        ListHeaderComponent={
          <View style={{ gap: Spacing.md, marginBottom: Spacing.xs }}>
            {catalog.launchAllowed ? null : <HintCard kind="warning" text={t('hostAppsLaunchPermissionOffHint')} />}
            <GroupedCard>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md2 }}>
                <Monitor size={22} color={Brand.seed} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontFamily: FontFamily.semibold }}>{t('hostAppsCatalogTitle')}</Text>
                  <Text muted style={{ fontSize: 12 }}>{t('hostAppsCatalogPlatform', { platform: t(platformKey(catalog.platform)) })}</Text>
                  <Text muted style={{ fontSize: 12 }}>{t('hostAppsCatalogScope')}</Text>
                </View>
                <Text style={{ fontFamily: FontFamily.semibold }}>{t('hostAppsCount', { count: catalog.apps.length })}</Text>
              </View>
            </GroupedCard>
            <SearchBar value={query} onChange={setQuery} placeholder={t('hostAppsSearchHint')} />
            <View style={{ flexDirection: 'row', paddingHorizontal: Spacing.xs }}>
              <Text muted style={{ flex: 1 }}>{t('hostAppsInstruction')}</Text>
              {query.trim() !== '' ? <Text muted style={{ fontSize: 12 }}>{t('hostAppsMatches', { count: shown.length })}</Text> : null}
            </View>
          </View>
        }
        ListEmptyComponent={
          <View style={{ alignItems: 'center', gap: Spacing.xs, padding: Spacing.lg }}>
            <SearchX size={32} color={c.onSurfaceVariant} />
            <Text style={{ fontFamily: FontFamily.semibold }}>{t('hostAppsNoMatchesTitle')}</Text>
            <Text muted>{t('hostAppsNoMatchesMessage')}</Text>
          </View>
        }
        renderItem={({ item }) => <AppCard app={item} launching={launching.has(item.id)} launchAllowed={catalog.launchAllowed} onRun={() => void launch(item)} />}
      />
    );
  }

  return (
    <View style={{ flex: 1 }}>
      <Stack.Screen
        options={{
          title: t('hostAppsTitle'),
          headerRight: () => (
            <AppBarIconButton label={t('hostAppsRefreshTooltip')} onPress={reload}>
              <RefreshCw size={19} color={c.onSurfaceVariant} />
            </AppBarIconButton>
          ),
        }}
      />
      {hostLabel ? <Text muted style={{ paddingHorizontal: Spacing.md, paddingTop: Spacing.xs }} numberOfLines={1}>{hostLabel}</Text> : null}
      {body}
    </View>
  );
}

function AppCard({ app, launching, launchAllowed, onRun }: { app: HostApp; launching: boolean; launchAllowed: boolean; onRun: () => void }) {
  const c = useScheme();
  const Icon = ICONS[safeIcon(app.icon)];
  const canRun = launchAllowed && app.launchable;
  return (
    <GroupedCard>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md2 }}>
        <View style={{ width: 44, height: 44, borderRadius: 12, backgroundColor: `${Brand.seed}26`, alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={22} color={Brand.seed} />
        </View>
        <View style={{ flex: 1 }}>
          <Text style={{ fontFamily: FontFamily.semibold }} numberOfLines={1}>{app.name}</Text>
          {app.description ? <Text muted style={{ fontSize: 12 }} numberOfLines={2}>{app.description}</Text> : null}
          {!app.launchable ? <Text style={{ fontSize: 12 }} color={c.error}>{t('hostAppCannotRun')}</Text> : null}
        </View>
        <Button kind="tonal" label={launching ? t('hostAppStartingButton') : t('hostAppRunButton')} busy={launching} disabled={!canRun} onPress={onRun} />
      </View>
    </GroupedCard>
  );
}
