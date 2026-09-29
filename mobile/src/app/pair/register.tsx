import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { ScrollView } from 'react-native';

import { useToast } from '../../design/components';
import { Spacing } from '../../design/tokens';
import { AccountForm } from '../../features/pairing/AccountForm';
import { t } from '../../i18n';

export default function Screen() {
  const router = useRouter();
  const toast = useToast();
  const { address } = useLocalSearchParams<{ address?: string }>();
  return (
    <ScrollView contentContainerStyle={{ padding: Spacing.lg }} keyboardShouldPersistTaps="handled">
      <Stack.Screen options={{ title: t('registerTab') }} />
      <AccountForm
        mode="register"
        prefillAddress={address}
        onPaired={(label) => {
          toast.success(t('pairedWith', { name: label }));
          router.dismissTo('/');
        }}
      />
    </ScrollView>
  );
}
