import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { useEffect } from 'react';

import { DialogHost, ToastProvider } from '../design/components';
import { ThemeProvider, useScheme } from '../design/theme';
import { FontFamily } from '../design/tokens';
import { t } from '../i18n';
import { LockGate } from '../features/security/LockGate';
import { ensureLegacyImport } from '../services';
import { useCollections } from '../state/collections';
import { useSettings } from '../state/settings';

function Shell() {
  const c = useScheme();
  return (
    <>
      <StatusBar style={c.dark ? 'light' : 'dark'} />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: c.surface },
          headerTintColor: c.onSurface,
          headerTitleStyle: { fontFamily: FontFamily.semibold, fontSize: 19 },
          headerShadowVisible: false,
          contentStyle: { backgroundColor: c.surface },
        }}
      >
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen name="onboarding" options={{ headerShown: false }} />
        <Stack.Screen name="pair/index" options={{ title: t('addComputerTitle') }} />
        <Stack.Screen name="pair/scan" options={{ headerShown: false }} />
        <Stack.Screen name="pair/login" options={{ title: t('loginTab') }} />
        <Stack.Screen name="pair/register" options={{ title: t('registerTab') }} />
        <Stack.Screen name="settings/appearance" options={{ title: t('appearanceSection') }} />
        <Stack.Screen name="settings/visibility" options={{ title: t('fileVisibilityTitle') }} />
        <Stack.Screen name="settings/storage" options={{ title: t('storageSecurityTitle') }} />
        <Stack.Screen name="settings/transfers" options={{ title: t('transfersSettingsTitle') }} />
        <Stack.Screen name="settings/about" options={{ title: t('aboutSupportTitle') }} />
        <Stack.Screen name="dev/gallery" options={{ title: 'Design gallery' }} />
      </Stack>
    </>
  );
}

export default function RootLayout() {
  const settings = useSettings((s) => s.state.app);
  const load = useSettings((s) => s.load);
  const loadCollections = useCollections((s) => s.load);
  useEffect(() => {
    // The one-time Flutter import must finish before settings and collections are read.
    ensureLegacyImport().finally(() => {
      void load();
      void loadCollections();
    });
  }, [load, loadCollections]);
  const mode = settings.amoledDark ? 'amoled' : settings.themeMode;
  return (
    <SafeAreaProvider>
      <ThemeProvider mode={mode} seed={settings.seedColor}>
        <ToastProvider>
          <DialogHost>
            <LockGate>
              <Shell />
            </LockGate>
          </DialogHost>
        </ToastProvider>
      </ThemeProvider>
    </SafeAreaProvider>
  );
}
