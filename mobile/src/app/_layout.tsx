import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { ToastProvider } from '../design/components';
import { ThemeProvider, useScheme } from '../design/theme';
import { FontFamily } from '../design/tokens';
import { t } from '../i18n';

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
        <Stack.Screen name="pair/index" options={{ title: t('addComputerTitle') }} />
        <Stack.Screen name="pair/scan" options={{ headerShown: false }} />
        <Stack.Screen name="pair/login" options={{ title: t('loginTab') }} />
        <Stack.Screen name="pair/register" options={{ title: t('registerTab') }} />
        <Stack.Screen name="dev/gallery" options={{ title: 'Design gallery' }} />
      </Stack>
    </>
  );
}

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <ThemeProvider>
        <ToastProvider>
          <Shell />
        </ToastProvider>
      </ThemeProvider>
    </SafeAreaProvider>
  );
}
