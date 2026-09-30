import Constants from 'expo-constants';
import { Info } from 'lucide-react-native';

import { useScheme } from '../../design/theme';
import { t } from '../../i18n';
import { InfoRow, SettingsPage, SettingsSection } from '../../features/settings/parts';

export default function AboutSettings() {
  const c = useScheme();
  const version = Constants.expoConfig?.version ?? '';
  return (
    <SettingsPage>
      <SettingsSection title={t('aboutSection')}>
        <InfoRow icon={Info} tint={c.primary} title={t('appNameLabel')} subtitle={`${t('appVersionLabel')} ${version}`} />
      </SettingsSection>
    </SettingsPage>
  );
}
