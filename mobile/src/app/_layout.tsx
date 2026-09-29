import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

import { ThemeProvider, useScheme } from '../design/theme';
import { FontFamily } from '../design/tokens';

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
        <Stack.Screen name="index" options={{ title: 'Hosts' }} />
        <Stack.Screen name="pair" options={{ title: 'Pair a host' }} />
        <Stack.Screen name="transfers" options={{ title: 'Transfers' }} />
        <Stack.Screen name="host/[id]" options={{ title: 'Files' }} />
        <Stack.Screen name="dev/gallery" options={{ title: 'Design gallery' }} />
      </Stack>
    </>
  );
}

export default function RootLayout() {
  return (
    <ThemeProvider>
      <Shell />
    </ThemeProvider>
  );
}
