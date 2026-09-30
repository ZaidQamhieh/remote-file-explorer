import { ArrowDown, ArrowUp, Pause, Play, RotateCw, Trash2, X, type LucideIcon } from 'lucide-react-native';
import { useEffect, useMemo, useState } from 'react';
import { ScrollView, View } from 'react-native';

import { formatSize } from '../../core/format';
import { openPublicUri, transfers, type TransferRecord } from '../../core/native';
import { AppBar, EmptyState, GroupedCard, Pressable, SectionLabel, Text, useToast } from '../../design/components';
import { useScheme } from '../../design/theme';
import { Brand, FontFamily, Spacing } from '../../design/tokens';
import { externalMime } from '../../features/preview/externalFiles';
import { etaSeconds, formatEta, formatSpeed, SpeedTracker } from '../../features/transfers/speedTracker';
import { groupTransfers, isActive, isUpload, savedWhere, transferErrorMessage, transferName, transferProgress } from '../../features/transfers/transferLogic';

/** Every transfer the native engine knows: running and paused first, then failures, then finished ones. */
export default function Transfers() {
  const [items, setItems] = useState<TransferRecord[] | null>(null);
  const [speeds, setSpeeds] = useState<Record<string, number>>({});
  useEffect(() => {
    let live = true;
    const tracker = new SpeedTracker();
    void transfers.list().then((l) => live && setItems(l));
    const off = transfers.subscribe((r) => {
      const speed = tracker.sample(r.id, r.received, r.state === 'RUNNING');
      setSpeeds((cur) => {
        if (speed === null) {
          if (!(r.id in cur)) return cur;
          const { [r.id]: _gone, ...rest } = cur;
          return rest;
        }
        return { ...cur, [r.id]: speed };
      });
      setItems((cur) => [...(cur ?? []).filter((x) => x.id !== r.id), r]);
    });
    return () => {
      live = false;
      off();
    };
  }, []);
  const groups = useMemo(() => groupTransfers(items ?? []), [items]);
  const running = groups.active.filter(isActive).length;

  const forget = async (rs: TransferRecord[]) => {
    await Promise.all(rs.map((r) => transfers.remove(r.id)));
    const gone = new Set(rs.map((r) => r.id));
    setItems((cur) => (cur ?? []).filter((x) => !gone.has(x.id)));
  };

  return (
    <View style={{ flex: 1 }}>
      <AppBar title="Transfers" subtitle={running > 0 ? `${running} active` : undefined} tall />
      {items === null ? null : items.length === 0 ? (
        <EmptyState message="No transfers yet" />
      ) : (
        <ScrollView contentContainerStyle={{ padding: Spacing.md, gap: Spacing.md, paddingBottom: Spacing.xl }}>
          <Group title="Active" rows={groups.active} speeds={speeds} onForget={forget} />
          <Group title="Failed" rows={groups.failed} onForget={forget} />
          <Group
            title="Finished"
            rows={groups.finished}
            onForget={forget}
            trailing={groups.finished.length > 0 ? <TextAction label="Clear" onPress={() => void forget(groups.finished)} /> : undefined}
          />
        </ScrollView>
      )}
    </View>
  );
}

function Group({ title, rows, trailing, speeds, onForget }: { title: string; rows: TransferRecord[]; trailing?: React.ReactNode; speeds?: Record<string, number>; onForget: (rs: TransferRecord[]) => Promise<void> }) {
  if (rows.length === 0) return null;
  return (
    <View>
      <SectionLabel title={`${title} · ${rows.length}`} trailing={trailing} />
      <View style={{ gap: Spacing.sm }}>
        {rows.map((r) => (
          <Row key={r.id} r={r} speed={speeds?.[r.id]} onForget={() => onForget([r])} />
        ))}
      </View>
    </View>
  );
}

function TextAction({ label, onPress }: { label: string; onPress: () => void }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} accessibilityLabel={label} style={{ paddingHorizontal: 8, paddingVertical: 4 }}>
      <Text style={{ fontFamily: FontFamily.semibold, fontSize: 13 }} color={c.primary}>{label}</Text>
    </Pressable>
  );
}

function Row({ r, speed, onForget }: { r: TransferRecord; speed?: number; onForget: () => void }) {
  const c = useScheme();
  const toast = useToast();
  const openable = r.state === 'DONE' && !!r.publicUri;
  const open = async () => {
    const name = transferName(r);
    if (!r.publicUri || !(await openPublicUri(r.publicUri, externalMime({ name })))) toast.info('No app can open this file');
  };
  const up = isUpload(r);
  const progress = transferProgress(r);
  const failed = r.state === 'FAILED';
  const tint = failed ? c.error : r.state === 'DONE' ? Brand.online : up ? Brand.accent : c.primary;
  const status =
    r.state === 'DONE' ? `${savedWhere(r)} · ${formatSize(r.total > 0 ? r.total : r.received)}`
    : r.state === 'CANCELLED' ? 'Cancelled'
    : r.state === 'PAUSED' ? `Paused${r.total > 0 ? ` · ${formatSize(r.received)} of ${formatSize(r.total)}` : ''}`
    : r.state === 'QUEUED' ? 'Waiting'
    : r.total > 0 ? `${formatSize(r.received)} of ${formatSize(r.total)}${runningPace(r, speed)}` : r.received > 0 ? formatSize(r.received) : up ? 'Preparing' : 'Starting';

  return (
    <GroupedCard>
      <View style={{ gap: 8 }}>
        <Pressable disabled={!openable} onPress={() => void open()} accessibilityLabel={openable ? `Open ${transferName(r)}` : undefined} style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md2 }}>
          <View style={{ width: 38, height: 38, borderRadius: 12, backgroundColor: `${tint}26`, alignItems: 'center', justifyContent: 'center' }}>
            {up ? <ArrowUp size={18} color={tint} /> : <ArrowDown size={18} color={tint} />}
          </View>
          <View style={{ flex: 1 }}>
            <Text style={{ fontFamily: FontFamily.semibold }} numberOfLines={1}>{transferName(r)}</Text>
            <Text muted style={{ fontSize: 12 }} numberOfLines={1}>{failed ? transferErrorMessage(r.error) : status}</Text>
          </View>
          <View style={{ flexDirection: 'row' }}>
            {r.state === 'RUNNING' || r.state === 'QUEUED' ? <IconAction Icon={Pause} label="Pause" onPress={() => void transfers.pause(r.id)} /> : null}
            {r.state === 'PAUSED' ? <IconAction Icon={Play} label="Resume" onPress={() => void transfers.resume(r.id)} /> : null}
            {failed ? <IconAction Icon={RotateCw} label="Retry" onPress={() => void transfers.resume(r.id)} /> : null}
            {r.state === 'RUNNING' || r.state === 'QUEUED' || r.state === 'PAUSED' ? <IconAction Icon={X} label="Cancel" onPress={() => void transfers.cancel(r.id)} /> : null}
            {failed || r.state === 'DONE' || r.state === 'CANCELLED' ? <IconAction Icon={Trash2} label="Remove" onPress={onForget} /> : null}
          </View>
        </Pressable>
        {progress !== null && r.state !== 'DONE' && r.state !== 'CANCELLED' ? (
          <View accessibilityRole="progressbar" accessibilityValue={{ min: 0, max: 100, now: Math.round(progress * 100) }} style={{ height: 4, borderRadius: 2, backgroundColor: c.outlineVariant, overflow: 'hidden' }}>
            <View style={{ width: `${progress * 100}%`, height: 4, backgroundColor: tint }} />
          </View>
        ) : null}
      </View>
    </GroupedCard>
  );
}

/** ' · 3.2 MB/s · 12 s left' once a speed estimate exists. */
function runningPace(r: TransferRecord, speed?: number): string {
  if (speed === undefined) return '';
  const eta = etaSeconds(r.total, r.received, speed);
  return ` · ${formatSpeed(speed)}${eta === null ? '' : ` · ${formatEta(eta)} left`}`;
}

function IconAction({ Icon, label, onPress }: { Icon: LucideIcon; label: string; onPress: () => void }) {
  const c = useScheme();
  return (
    <Pressable onPress={onPress} pressedScale={0.92} accessibilityLabel={label} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
      <Icon size={18} color={c.onSurfaceVariant} />
    </Pressable>
  );
}
