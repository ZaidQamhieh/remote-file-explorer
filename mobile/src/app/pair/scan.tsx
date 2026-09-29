import { CameraView, useCameraPermissions } from 'expo-camera';
import { Stack, useRouter } from 'expo-router';
import { ArrowLeft, Flashlight } from 'lucide-react-native';
import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Animated, Easing, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CertPinMismatch } from '../../core/api/pin';
import { Button, GhostBlockButton, InlineError, Pressable, Text, useToast } from '../../design/components';
import { Spacing } from '../../design/tokens';
import { Brackets } from '../../features/pairing/QrPanel';
import { humanizeError, pairWithCode, parsePairingQr } from '../../features/pairing/pairingService';
import { t } from '../../i18n';
import { pairingDeps } from '../../services';

function Scanline({ height }: { height: number }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(v, { toValue: 1, duration: 2200, easing: Easing.inOut(Easing.ease), useNativeDriver: true }),
        Animated.timing(v, { toValue: 0, duration: 2200, easing: Easing.inOut(Easing.ease), useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [v]);
  const travel = height / 2 - 8;
  return (
    <Animated.View
      style={{ position: 'absolute', left: 8, right: 8, top: height / 2, height: 2, backgroundColor: '#4C8DFF', shadowColor: '#4C8DFF', shadowOpacity: 0.6, shadowRadius: 8, transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [-travel, travel] }) }] }}
    />
  );
}

const DarkIconButton = ({ children, onPress, label }: { children: React.ReactNode; onPress: () => void; label: string }) => (
  <Pressable onPress={onPress} accessibilityLabel={label}>
    <View style={{ width: 34, height: 34, borderRadius: 17, backgroundColor: 'rgba(255,255,255,0.08)', alignItems: 'center', justifyContent: 'center' }}>{children}</View>
  </Pressable>
);

export default function Scan() {
  const router = useRouter();
  const toast = useToast();
  const insets = useSafeAreaInsets();
  const [perm, requestPerm] = useCameraPermissions();
  const [torch, setTorch] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const handling = useRef(false);

  async function onScan(raw: string) {
    if (handling.current) return;
    const parsed = parsePairingQr(raw);
    if (!parsed.ok) {
      setError(t(parsed.error));
      return;
    }
    handling.current = true;
    setBusy(true);
    setError(null);
    try {
      const host = await pairWithCode(pairingDeps, { address: parsed.qr.address, fingerprint: parsed.qr.certFingerprint }, parsed.qr.pairingCode);
      toast.success(t('pairedWith', { name: host.label }));
      router.dismissTo('/');
    } catch (e) {
      setError(e instanceof CertPinMismatch ? t('fingerprintMismatch', { error: humanizeError(e) }) : t('pairingFailed', { error: humanizeError(e) }));
      handling.current = false;
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={{ flex: 1, backgroundColor: '#000' }}>
      <Stack.Screen options={{ headerShown: false }} />
      {perm?.granted ? (
        <CameraView
          style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
          facing="back"
          enableTorch={torch}
          barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          onBarcodeScanned={(r) => onScan(r.data)}
        />
      ) : (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: Spacing.lg, gap: Spacing.md }}>
          <Text color="#fff" style={{ textAlign: 'center' }}>
            {perm && !perm.canAskAgain ? 'Camera access is blocked. Enable it in system settings, or enter the code manually.' : 'Camera access is needed to scan the pairing QR.'}
          </Text>
          {(!perm || perm.canAskAgain) && <Button label="Allow camera" onPress={requestPerm} />}
        </View>
      )}
      <View style={{ flex: 1, paddingTop: insets.top }} pointerEvents="box-none">
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: Spacing.md, paddingVertical: Spacing.sm }}>
          <DarkIconButton onPress={() => router.back()} label="Back"><ArrowLeft size={19} color="#fff" /></DarkIconButton>
          <Text variant="screenTitle" color="#fff" style={{ fontSize: 19 }}>{t('scanQrTab')}</Text>
          <DarkIconButton onPress={() => setTorch((v) => !v)} label="Torch"><Flashlight size={19} color={torch ? '#4C8DFF' : '#fff'} /></DarkIconButton>
        </View>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }} pointerEvents="none">
          <View style={{ width: 230, height: 230 }}>
            <Brackets size={36} width={4} inset={0} color="#4C8DFF" />
            <Scanline height={230} />
          </View>
        </View>
        <View style={{ paddingHorizontal: Spacing.lg, paddingBottom: insets.bottom + Spacing.xl, gap: Spacing.md }}>
          {error && <InlineError message={error} />}
          <Text variant="bodySmall" color="rgba(255,255,255,0.7)" style={{ textAlign: 'center', fontSize: 12.5 }}>{t('pairingScanHint')}</Text>
          <GhostBlockButton label={t('enterCodeManuallyButton')} onPress={() => router.replace({ pathname: '/pair', params: { mode: 'code' } })} />
        </View>
      </View>
      {busy && (
        <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.4)', alignItems: 'center', justifyContent: 'center' }}>
          <ActivityIndicator size="large" />
        </View>
      )}
    </View>
  );
}
