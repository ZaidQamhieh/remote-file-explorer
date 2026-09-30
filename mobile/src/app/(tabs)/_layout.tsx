import { Redirect, Tabs, useRouter } from 'expo-router';
import { Activity, Database, Folder, FolderOpen, Settings } from 'lucide-react-native';

import { BottomNav, type NavDestination } from '../../design/components/BottomNav';
import { useEffect, useState } from 'react';

import { useScheme } from '../../design/theme';
import { isOnboarded } from '../../features/onboarding/onboardingState';
import { ensureLegacyImport, hostStore, keyValue } from '../../services';

const DESTINATIONS: NavDestination[] = [
  { name: 'index', label: 'Devices', Icon: Database },
  { name: 'files', label: 'Files', Icon: Folder, SelectedIcon: FolderOpen },
  { name: 'transfers', label: 'Transfers', Icon: Activity },
  { name: 'settings', label: 'Settings', Icon: Settings },
];

export default function TabsLayout() {
  const router = useRouter();
  const c = useScheme();
  // null while the first-run flag is read; a fresh install is sent to the pager before it sees any tab.
  const [onboarded, setOnboarded] = useState<boolean | null>(null);
  useEffect(() => {
    ensureLegacyImport()
      .then(() => isOnboarded(keyValue, async () => (await hostStore.listHosts()).length))
      .catch(() => true)
      .then(setOnboarded);
  }, []);
  if (onboarded === null) return null;
  if (!onboarded) return <Redirect href="/onboarding" />;
  return (
    <Tabs
      backBehavior="initialRoute"
      tabBar={(p) => <BottomNav {...p} destinations={DESTINATIONS} onAdd={() => router.push('/pair')} />}
      screenOptions={{ headerStyle: { backgroundColor: c.surface }, headerTintColor: c.onSurface, headerShadowVisible: false, sceneStyle: { backgroundColor: c.surface } }}
    >
      {DESTINATIONS.map((d) => (
        <Tabs.Screen key={d.name} name={d.name} options={{ title: d.label, headerShown: false }} />
      ))}
    </Tabs>
  );
}
