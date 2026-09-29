import { Link, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';

import type { Host } from '../core/models/host';
import { ensureLegacyImport, hostStore } from '../services';

export default function Hosts() {
  const router = useRouter();
  const [hosts, setHosts] = useState<Host[] | null>(null);
  const [needRepair, setNeedRepair] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      let live = true;
      (async () => {
        try {
          const report = await ensureLegacyImport();
          const list = await hostStore.listHosts();
          const missing: string[] = [];
          for (const h of list) if (!(await hostStore.getPin(h.id)) || !(await hostStore.getToken(h.id))) missing.push(h.id);
          if (live) {
            setHosts(list);
            setNeedRepair(missing.length ? missing : report.needRepair);
            setError(null);
          }
        } catch (e) {
          if (live) setError((e as Error).message);
        }
      })();
      return () => {
        live = false;
      };
    }, []),
  );

  return (
    <ScrollView contentContainerStyle={{ padding: 16, gap: 12 }}>
      {error && <Text accessibilityRole="alert">Could not load hosts: {error}</Text>}
      {hosts === null && !error && <Text>Loading…</Text>}
      {hosts?.length === 0 && <Text>No hosts yet. Pair one to browse its files.</Text>}
      {hosts?.map((h) => {
        const repair = needRepair.includes(h.id);
        return (
          <Pressable
            key={h.id}
            accessibilityRole="button"
            onPress={() => (repair ? router.push({ pathname: '/pair', params: { address: h.address, label: h.label } }) : router.push(`/host/${h.id}`))}
            style={{ padding: 16, borderRadius: 12, borderWidth: 1, borderColor: '#ccc' }}
          >
            <Text style={{ fontSize: 18, fontWeight: '600' }}>{h.label}</Text>
            <Text>{h.address}</Text>
            {repair && <Text style={{ color: '#b00020' }}>Trust needs to be restored — tap to re-pair.</Text>}
          </Pressable>
        );
      })}
      <View>
        <Link href="/pair" style={{ padding: 12, fontSize: 16 }}>
          Pair a new host
        </Link>
        <Link href="/transfers" style={{ padding: 12, fontSize: 16 }}>
          Transfers
        </Link>
      </View>
    </ScrollView>
  );
}
