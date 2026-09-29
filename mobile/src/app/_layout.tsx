import { Stack } from 'expo-router';

// Slice shell: plain native header. The Lumen design system replaces this in phase 2.
export default function RootLayout() {
  return (
    <Stack>
      <Stack.Screen name="index" options={{ title: 'Hosts' }} />
      <Stack.Screen name="pair" options={{ title: 'Pair a host' }} />
      <Stack.Screen name="host/[id]" options={{ title: 'Files' }} />
    </Stack>
  );
}
