import { Stack } from 'expo-router';
import { useEffect, useState } from 'react';

import type { Host } from '../core/models/host';
import { Loading } from '../design/components';
import { CrossHostSearchScreen } from '../features/search/CrossHostSearchScreen';
import { hostStore } from '../services';

/** Search every paired computer. */
export default function CrossHostSearch() {
  const [hosts, setHosts] = useState<Host[] | null>(null);
  useEffect(() => {
    let live = true;
    void hostStore.listHosts().then((l) => live && setHosts(l));
    return () => {
      live = false;
    };
  }, []);
  return (
    <>
      <Stack.Screen options={{ headerShown: false }} />
      {hosts === null ? <Loading /> : <CrossHostSearchScreen hosts={hosts} />}
    </>
  );
}
