import { Link2 } from 'lucide-react-native';
import { useState } from 'react';
import { View } from 'react-native';

import { normalizeFingerprint } from '../../core/api/pin';
import { Button, HintCard, InlineError } from '../../design/components';
import { Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { AddressField, CodeBoxRow, FingerprintField, fingerprintError } from './fields';
import { humanizeError, pairWithCode } from './pairingService';
import { pairingDeps } from '../../services';
import { CertPinMismatch } from '../../core/api/pin';

export function ManualPanel({ prefillAddress, onPaired }: { prefillAddress?: string; onPaired: (label: string) => void }) {
  const [address, setAddress] = useState(prefillAddress ?? '');
  const [fingerprint, setFingerprint] = useState('');
  const [code, setCode] = useState('');
  const [touched, setTouched] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setTouched(true);
    if (!address.trim() || fingerprintError(fingerprint) || code.trim().length < 8) {
      if (code.trim().length < 8) setError(t('requiredLabel'));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const host = await pairWithCode(pairingDeps, { address, fingerprint: normalizeFingerprint(fingerprint)! }, code);
      onPaired(host.label);
    } catch (e) {
      setError(e instanceof CertPinMismatch ? t('fingerprintMismatch', { error: humanizeError(e) }) : t('pairingFailed', { error: humanizeError(e) }));
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={{ gap: Spacing.md }}>
      <AddressField value={address} onChange={setAddress} error={touched && !address.trim() ? t('requiredLabel') : null} />
      <FingerprintField value={fingerprint} onChange={setFingerprint} error={touched ? fingerprintError(fingerprint) : null} />
      <CodeBoxRow value={code} onChange={setCode} />
      <HintCard text={t('pairingHint')} />
      {error && <InlineError message={error} />}
      <Button label={t('pairButton')} busy={busy} onPress={submit} icon={<Link2 size={18} color="#fff" />} />
    </View>
  );
}
