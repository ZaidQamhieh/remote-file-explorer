import { Image } from 'expo-image';
import { Database, Fingerprint, ShieldOff, Trash2 } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { authenticate, deviceAuthState } from '../../core/security/deviceAuth';
import type { Host } from '../../core/models/host';
import { Pressable, Text, useDialogs, useToast } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { lockEnableBlocker } from '../../features/security/lockLogic';
import { shortFingerprint } from '../../features/settings/hostSettingsLogic';
import { InfoRow, NavRow, RowBadge, SettingsPage, SettingsSection, ToggleRow } from '../../features/settings/parts';
import { hostStore, listingCache } from '../../services';
import { useLock } from '../../state/lock';
import { useSettings } from '../../state/settings';

type Trusted = { host: Host; pin: string | null };

/** App lock, the certificates this app trusts (one pin per paired computer), and cached data. */
export default function StorageSecuritySettings() {
  const c = useScheme();
  const dialogs = useDialogs();
  const toast = useToast();
  const lockOn = useSettings((s) => s.state.app.appLockEnabled);
  const setApp = useSettings((s) => s.setApp);
  const setUnlocked = useLock((s) => s.setUnlocked);
  const [trusted, setTrusted] = useState<Trusted[] | null>(null);
  const [cached, setCached] = useState<number | null>(null);

  const fetchAll = useCallback(async () => {
    const hosts = await hostStore.listHosts();
    return {
      trusted: await Promise.all(hosts.map(async (host) => ({ host, pin: await hostStore.getPin(host.id) }))),
      cached: await listingCache.count(hosts.map((h) => h.id)),
    };
  }, []);
  const apply = useCallback((r: { trusted: Trusted[]; cached: number }) => {
    setTrusted(r.trusted);
    setCached(r.cached);
  }, []);
  const reload = useCallback(() => fetchAll().then(apply), [fetchAll, apply]);
  useEffect(() => {
    let live = true;
    void fetchAll().then((r) => live && apply(r));
    return () => {
      live = false;
    };
  }, [fetchAll, apply]);

  const toggleLock = async (next: boolean) => {
    if (next) {
      const { hasHardware, level } = await deviceAuthState();
      const blocked = lockEnableBlocker(hasHardware, level);
      if (blocked) return void toast.error(t(blocked === 'noHardware' ? 'appLockNoHardware' : 'appLockNoScreenLock'));
      // Prove the user can pass the check before it starts guarding the app.
      if ((await authenticate(t('appLockConfirmReason'))) !== 'success') return;
      setUnlocked(true);
    }
    await setApp('appLockEnabled', next);
  };

  const forget = async ({ host }: Trusted) => {
    const label = host.label || host.address;
    const ok = await dialogs.confirm({ title: t('forgetHostTitle', { host: label }), description: t('forgetHostMessage'), confirmLabel: t('forgetButton'), cancelLabel: t('cancelButton'), destructive: true });
    if (!ok) return;
    await hostStore.removeHost(host.id);
    toast.success(t('hostForgotten', { host: label }));
    await reload();
  };

  const clearCache = async () => {
    const hosts = await hostStore.listHosts();
    await Promise.all(hosts.map((h) => listingCache.evictHost(h.id)));
    await Image.clearDiskCache();
    await Image.clearMemoryCache();
    toast.success(t('cacheCleared'));
    await reload();
  };

  return (
    <SettingsPage>
      <SettingsSection title={t('appLockTitle')}>
        <ToggleRow icon={Fingerprint} tint={c.primary} title={t('appLockTitle')} subtitle={t('appLockSubtitle')} value={lockOn} onChange={(v) => void toggleLock(v)} />
      </SettingsSection>
      <SettingsSection title={t('trustedCertsSection')}>
        {trusted === null ? (
          <InfoRow icon={Database} title={t('cacheCalculating')} />
        ) : trusted.length === 0 ? (
          <InfoRow icon={ShieldOff} title={t('noTrustedCerts')} />
        ) : (
          trusted.map((x) => (
            <View key={x.host.id} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 11 }}>
              <RowBadge icon={Fingerprint} tint={c.primary} />
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 14 }}>{x.host.label || x.host.address}</Text>
                <Text muted style={{ fontSize: 11.5 }}>{shortFingerprint(x.pin) ?? t('probeMissingPinHint')}</Text>
              </View>
              <Pressable onPress={() => void forget(x)} accessibilityLabel={`${t('forgetButton')} ${x.host.label || x.host.address}`} style={{ padding: Spacing.sm }}>
                <Trash2 size={18} color={c.error} />
              </Pressable>
            </View>
          ))
        )}
      </SettingsSection>
      <SettingsSection title={t('cacheSection')}>
        <InfoRow icon={Database} tint={c.primary} title={t('cacheListingLabel')} subtitle={cached === null ? t('cacheCalculating') : t('cacheListingsSummary', { count: cached })} />
        <NavRow icon={Trash2} tint={c.error} title={t('cacheClearAll')} onPress={() => void clearCache()} />
      </SettingsSection>
    </SettingsPage>
  );
}
