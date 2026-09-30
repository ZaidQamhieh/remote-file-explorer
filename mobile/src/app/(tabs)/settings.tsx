import { useRouter } from 'expo-router';
import { ArchiveRestore, ArrowLeftRight, FolderSync, EyeOff, HardDrive, Images, Info, Palette } from 'lucide-react-native';
import { View } from 'react-native';

import { AppBar } from '../../design/components';
import { useScheme } from '../../design/theme';
import { t } from '../../i18n';
import { NavRow, SettingsPage, SettingsSection } from '../../features/settings/parts';

/** App-wide settings hub; each row opens a stack screen. Per-computer settings live under a host. */
export default function Settings() {
  const router = useRouter();
  const c = useScheme();
  return (
    <View style={{ flex: 1 }}>
      <AppBar title={t('settingsTitle')} />
      <SettingsPage>
        <SettingsSection title={t('preferencesSection')}>
          <NavRow icon={Palette} tint={c.primary} title={t('appearanceSection')} subtitle={t('appearanceSubtitle')} onPress={() => router.push('/settings/appearance')} />
          <NavRow icon={EyeOff} tint={c.primary} title={t('fileVisibilityTitle')} subtitle={t('fileVisibilitySubtitle')} onPress={() => router.push('/settings/visibility')} />
          <NavRow icon={ArrowLeftRight} tint={c.primary} title={t('transfersSettingsTitle')} subtitle={t('transfersSettingsSubtitle')} onPress={() => router.push('/settings/transfers')} />
        </SettingsSection>
        <SettingsSection title={t('dataSection')}>
          <NavRow icon={Images} tint={c.primary} title={t('photoBackupTitle')} subtitle={t('copyPhonePhotos')} onPress={() => router.push('/settings/photo-backup')} />
          <NavRow icon={FolderSync} tint={c.primary} title={t('syncRulesTitle')} subtitle={t('syncRulesSubtitle')} onPress={() => router.push('/settings/sync')} />
          <NavRow icon={ArchiveRestore} tint={c.primary} title={t('backupRestoreSection')} subtitle={t('exportConfigSubtitle')} onPress={() => router.push('/settings/backup')} />
          <NavRow icon={HardDrive} tint={c.primary} title={t('storageSecurityTitle')} subtitle={t('storageSecuritySubtitle')} onPress={() => router.push('/settings/storage')} />
        </SettingsSection>
        <SettingsSection title={t('supportSection')}>
          <NavRow icon={Info} tint={c.primary} title={t('aboutSupportTitle')} subtitle={t('aboutSupportSubtitle')} onPress={() => router.push('/settings/about')} />
        </SettingsSection>
      </SettingsPage>
    </View>
  );
}
