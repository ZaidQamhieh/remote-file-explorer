import { ScrollView } from 'react-native';

import { Text } from '../../design/components';
import { Spacing } from '../../design/tokens';
import { t } from '../../i18n';

export default function Privacy() {
  return (
    <ScrollView contentContainerStyle={{ padding: Spacing.md, gap: Spacing.md }}>
      <Text>{t('privacyBody1')}</Text>
      <Text>{t('privacyBody2')}</Text>
      <Text>{t('privacyBody3')}</Text>
    </ScrollView>
  );
}
