import { Check, Gauge, RefreshCw, Route, Shield, X, type LucideIcon } from 'lucide-react-native';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, ScrollView, View } from 'react-native';

import { normalizeFingerprint } from '../../core/api/pin';
import type { Host, HostRoute } from '../../core/models/host';
import { nativeTransport } from '../../core/native';
import { BottomSheet, GhostBlockButton, SheetHead, Text } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, FontFamily, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { hostStore } from '../../services';
import { probeAll, type ProbeResult } from './diagnostics';

const ROUTE_NAME: Record<HostRoute, () => string> = {
  lan: () => t('routeLanName'),
  tailscale: () => t('routeTailscaleName'),
  directHttps: () => t('routeInternetName'),
  custom: () => t('routeCustomName'),
};

/**
 * Checks each route to a host separately: reachability, pinned TLS, whether this device is let in, latency and the path
 * used, with a hint for the first thing that failed. Nothing is sent to a host whose certificate does not match the pin.
 */
export function ConnectionDiagnosticsSheet({ host, onClose }: { host: Host; onClose: () => void }) {
  const [outcome, setOutcome] = useState<{ results: ProbeResult[]; pin: string | null } | null>(null);

  const run = useCallback(async () => {
    const [token, fingerprint] = await Promise.all([hostStore.getToken(host.id), hostStore.getPin(host.id)]);
    return { results: await probeAll({ transport: nativeTransport, deviceToken: token, fingerprint }, host), pin: normalizeFingerprint(fingerprint) };
  }, [host]);
  useEffect(() => {
    let live = true;
    void run().then((r) => live && setOutcome(r));
    return () => {
      live = false;
    };
  }, [run]);
  const again = () => {
    setOutcome(null);
    void run().then(setOutcome);
  };
  const results = outcome?.results ?? null;
  const pin = outcome?.pin ?? null;

  return (
    <BottomSheet visible onClose={onClose}>
      <SheetHead title={t('connectionDiagnosticsTitle')} subtitle={`${host.label} · ${host.address}`} />
      <ScrollView contentContainerStyle={{ paddingHorizontal: 12, paddingBottom: 24 }}>
        {results === null ? (
          <View style={{ paddingVertical: Spacing.lg, alignItems: 'center' }}><ActivityIndicator /></View>
        ) : (
          results.map((r, i) => (
            <View key={r.address} style={{ marginTop: i > 0 ? Spacing.md : 0 }}>
              {results.length > 1 && <Text style={{ fontSize: 10.5, fontFamily: FontFamily.semibold, letterSpacing: 0.9, paddingHorizontal: 8, paddingBottom: Spacing.xs, textTransform: 'uppercase' }} muted>{ROUTE_NAME[r.route]()}</Text>}
              <Checks result={r} pin={pin} />
            </View>
          ))
        )}
        <View style={{ paddingHorizontal: 4, paddingTop: 16 }}>
          <GhostBlockButton label={t('runAgainButton')} icon={<RefreshCw size={16} />} onPress={results === null ? () => {} : again} />
        </View>
      </ScrollView>
    </BottomSheet>
  );
}

function Checks({ result: r, pin }: { result: ProbeResult; pin: string | null }) {
  const c = useScheme();
  const grey = c.outline;
  const reachable = r.health !== undefined;
  const mismatch = r.failure === 'pinMismatch';
  const bad = Brand.red;
  const failureBadge = { none: t('diagOkBadge'), missingPin: t('diagPinRequiredBadge'), pinMismatch: t('diagMismatchBadge'), dns: t('probeDnsFailedBadge'), unreachable: t('probeNoResponseBadge'), other: t('probeError') }[r.failure];
  const authBadge = { accepted: t('diagAuthAcceptedBadge'), denied: t('diagAuthDeniedBadge'), notChecked: t('diagAuthUnknownBadge') }[r.auth];
  const authTint = r.auth === 'accepted' ? Brand.online : r.auth === 'denied' ? bad : grey;
  const hint =
    r.failure === 'pinMismatch' ? t('probePinMismatchHint')
    : r.failure === 'missingPin' ? t('probeMissingPinHint')
    : r.failure === 'dns' ? t('probeDnsHint')
    : r.failure === 'unreachable' ? t('probeReachabilityHint')
    : r.failure === 'other' ? t('probeGenericHint')
    : r.auth === 'denied' ? t('probeAuthRejectedHint')
    : null;
  const pathBadge = { lan: t('diagLanDirect'), tailscale: t('networkTailscale'), directHttps: t('routeInternetName'), custom: t('routeCustomName') }[r.route];
  return (
    <View>
      <Row icon={reachable ? Check : X} tint={reachable ? Brand.online : mismatch ? bad : grey} title={t('diagHostReachable')} subtitle={r.address} badge={failureBadge} />
      <Row
        icon={mismatch ? X : reachable ? Check : Shield}
        tint={mismatch ? bad : reachable ? Brand.online : grey}
        title={t('diagTlsPinned')}
        subtitle={pin ? (pin.length > 12 ? `${pin.slice(0, 12)}…` : pin) : undefined}
        badge={mismatch ? t('diagMismatchBadge') : reachable ? t('diagPinnedBadge') : r.failure === 'missingPin' ? t('diagPinRequiredBadge') : t('diagUnknownBadge')}
      />
      <Row icon={r.auth === 'accepted' ? Check : r.auth === 'denied' ? X : Shield} tint={authTint} title={t('diagAuthentication')} badge={authBadge} />
      <Row icon={Gauge} tint={reachable ? Brand.online : grey} title={t('diagLatency')} badge={reachable ? t('probeLatencyMs', { ms: r.latencyMs ?? 0 }) : '—'} mono />
      <Row icon={Route} tint={Brand.seed} title={t('diagPath')} badge={pathBadge} badgeTint={reachable ? Brand.seed : grey} last />
      {hint ? <Text muted style={{ fontSize: 12, paddingHorizontal: 4, paddingTop: 8 }}>{hint}</Text> : null}
    </View>
  );
}

function Row({ icon: Icon, tint, title, subtitle, badge, badgeTint, mono, last }: { icon: LucideIcon; tint: string; title: string; subtitle?: string; badge: string; badgeTint?: string; mono?: boolean; last?: boolean }) {
  const c = useScheme();
  const bt = badgeTint ?? tint;
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md2, paddingVertical: 11, paddingHorizontal: 4, borderBottomWidth: last ? 0 : 1, borderColor: c.outlineVariant }}>
      <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: `${tint}24`, alignItems: 'center', justifyContent: 'center' }}>
        <Icon size={16} color={tint} />
      </View>
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 14, fontFamily: FontFamily.medium }}>{title}</Text>
        {subtitle ? <Text muted numberOfLines={1} style={{ fontSize: 11.5, fontFamily: FontFamily.mono }}>{subtitle}</Text> : null}
      </View>
      <View style={{ flexShrink: 1, paddingHorizontal: 7, paddingVertical: 2, borderRadius: Radii.stadium, backgroundColor: `${bt}24` }}>
        <Text numberOfLines={1} style={{ fontSize: 10.5, fontFamily: mono ? FontFamily.monoMedium : FontFamily.semibold }} color={bt}>{badge}</Text>
      </View>
    </View>
  );
}
