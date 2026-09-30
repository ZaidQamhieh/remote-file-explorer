import { Send } from 'lucide-react-native';
import { useState } from 'react';
import { View } from 'react-native';

import { Button, HintCard } from '../../design/components';
import { Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { AddressField } from './fields';

/** Enter a computer's address; it then asks the owner to approve on that computer (nothing else to type). */
export function ManualPanel({ prefillAddress, onRequest }: { prefillAddress?: string; onRequest: (address: string) => void }) {
  const [address, setAddress] = useState(prefillAddress ?? '');
  const [touched, setTouched] = useState(false);

  function submit() {
    setTouched(true);
    if (address.trim()) onRequest(address.trim());
  }

  return (
    <View style={{ gap: Spacing.md }}>
      <AddressField value={address} onChange={setAddress} error={touched && !address.trim() ? t('requiredLabel') : null} />
      <HintCard text={t('pairingHint')} />
      <Button label={t('requestPairingButton')} onPress={submit} icon={<Send size={18} color="#fff" />} />
    </View>
  );
}
