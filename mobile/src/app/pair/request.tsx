import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, ScrollView, View } from 'react-native';

import { Button, GroupedCard, HintCard, InlineError, Text, useToast } from '../../design/components';
import { useScheme } from '../../design/theme';
import { FontFamily, Spacing } from '../../design/tokens';
import { awaitPairing, humanizeError, PairExpired, PairRejected, requestPairing, type PairRequestHandle } from '../../features/pairing/pairingService';
import { t } from '../../i18n';
import { pairingDeps } from '../../services';

type Phase = { kind: 'connecting' } | { kind: 'waiting'; handle: PairRequestHandle } | { kind: 'failed'; message: string };

/** Asks the computer to approve this phone and waits for the answer; the only thing shown is a match code to compare. */
export default function PairRequest() {
  const router = useRouter();
  const toast = useToast();
  const c = useScheme();
  const { address } = useLocalSearchParams<{ address: string }>();
  const [phase, setPhase] = useState<Phase>({ kind: 'connecting' });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const ctl = new AbortController();
    void (async () => {
      try {
        const handle = await requestPairing(pairingDeps, address);
        if (ctl.signal.aborted) return;
        setPhase({ kind: 'waiting', handle });
        const host = await awaitPairing(pairingDeps, handle, { signal: ctl.signal });
        toast.success(t('pairedWith', { name: host.label }));
        router.dismissTo('/');
      } catch (e) {
        if (ctl.signal.aborted) return;
        const message = e instanceof PairRejected ? t('pairRequestRejected') : e instanceof PairExpired ? t('pairRequestExpired') : t('pairRequestFailed', { error: humanizeError(e) });
        setPhase({ kind: 'failed', message });
      }
    })();
    return () => ctl.abort();
  }, [address, attempt, router, toast]);

  return (
    <ScrollView contentContainerStyle={{ padding: Spacing.lg, gap: Spacing.lg }}>
      <Stack.Screen options={{ title: t('pairRequestTitle') }} />
      <Text muted>{address}</Text>
      {phase.kind === 'connecting' && (
        <View style={{ alignItems: 'center', gap: Spacing.md, paddingVertical: Spacing.xl }}>
          <ActivityIndicator />
          <Text muted>{t('pairRequestConnecting')}</Text>
        </View>
      )}
      {phase.kind === 'waiting' && (
        <>
          <GroupedCard>
            <View style={{ alignItems: 'center', gap: Spacing.sm, paddingVertical: Spacing.md }}>
              <Text variant="labelMedium" muted>{t('pairRequestMatchCode')}</Text>
              <Text style={{ fontFamily: FontFamily.monoMedium, fontSize: 36, lineHeight: 44, letterSpacing: 2, color: c.primary }} accessibilityLabel={phase.handle.matchCode.replace(/\D/g, ' ').trim()}>
                {phase.handle.matchCode}
              </Text>
            </View>
          </GroupedCard>
          <View style={{ alignItems: 'center', gap: Spacing.sm }}>
            <ActivityIndicator />
            <Text variant="titleMedium">{t('pairRequestApprove')}</Text>
          </View>
          <HintCard text={t('pairRequestApproveBody', { name: address })} />
        </>
      )}
      {phase.kind === 'failed' && (
        <>
          <InlineError message={phase.message} />
          <Button label={t('pairRequestRetry')} onPress={() => {
            setPhase({ kind: 'connecting' });
            setAttempt((a) => a + 1);
          }} />
        </>
      )}
      <Button kind="text" label={t('pairRequestCancel')} onPress={() => router.back()} />
    </ScrollView>
  );
}
