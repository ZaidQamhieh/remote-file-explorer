import * as Clipboard from 'expo-clipboard';
import { Archive, Calendar, CalendarClock, Copy, Download, ExternalLink, Eye, FilePen, Info, Link as LinkIcon, Lock, QrCode, Route, Ruler, Share2, Star, Tag, Trash2, type LucideIcon } from 'lucide-react-native';
import { useEffect, useState, type ReactNode } from 'react';
import { ScrollView, View } from 'react-native';

import type { AgentClient } from '../../core/api/agentClient';
import { can, type Entry, type FileCapability, type ShareLink } from '../../core/api/models';
import { formatDate, formatSize } from '../../core/format';
import type { Host } from '../../core/models/host';
import { BottomSheet, Pressable, SheetGrabber, SheetHero, Text, useDialogs, useToast } from '../../design/components';
import { useScheme } from '../../design/theme';
import { FontFamily, Radii, Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { useCollections } from '../../state/collections';
import { humanizeError } from '../pairing/pairingService';
import { useExternalActions } from '../preview/useExternalActions';
import { isPreviewable } from '../preview/previewKind';
import { HandoffQrSheet } from '../handoff/HandoffQrSheet';
import { ShareLinkSheet } from '../share/ShareLinkSheet';
import { enqueueDownloads } from '../transfers/enqueueDownloads';
import { ChmodDialog } from './ChmodDialog';
import { EntryLeading, useIconChipBg } from './EntryIcon';
import { isExtractableArchive } from './metaLogic';
import { useFileCapabilities } from './useFileCapabilities';
import { folderLabel, parentDirOf, renameDestination } from './paths';
import { clientForHost, hostStore } from '../../services';

type Action = { key: string; icon: LucideIcon; label: string; onPress: () => void; tint?: string };

/**
 * Per-entry details sheet (port of MetaSheet): a row of quick actions, a list of secondary actions and a
 * Details view with permissions and an on-demand checksum. Every mutation reports through `onChanged` so the
 * caller can refresh its listing, then closes the sheet.
 */
export function MetaSheet({ visible, host, entry: initial, onClose, onChanged, onPreview }: { visible: boolean; host: Host; entry: Entry; onClose: () => void; onChanged?: () => void; onPreview?: (e: Entry) => void }) {
  const c = useScheme();
  const toast = useToast();
  const dialogs = useDialogs();
  const favorites = useCollections((s) => s.favorites);
  const toggleFavorite = useCollections((s) => s.toggleFavorite);
  const [entry, setEntry] = useState(initial);
  const [view, setView] = useState<'actions' | 'details'>('actions');
  const [client, setClient] = useState<AgentClient | null>(null);
  const caps = useFileCapabilities(host);
  const allowed = (c: FileCapability) => can(caps, c);
  const [chmodOpen, setChmodOpen] = useState(false);
  const [checksum, setChecksum] = useState<string | null>(null);
  const [checksumBusy, setChecksumBusy] = useState(false);
  const [link, setLink] = useState<ShareLink | null>(null);
  const [qr, setQr] = useState<{ certFingerprint: string; path: string; name: string } | null>(null);
  const chip = useIconChipBg(entry);
  const external = useExternalActions(host);

  // Re-seed whenever a (different) entry is shown, then refresh its metadata from the agent.
  const [seenFor, setSeenFor] = useState<Entry | null>(null);
  if (visible && seenFor !== initial) {
    setSeenFor(initial);
    setEntry(initial);
    setView('actions');
    setChecksum(null);
  }
  useEffect(() => {
    if (!visible) return;
    let live = true;
    clientForHost(host).then(async (cl) => {
      if (!live) return;
      setClient(cl);
      try {
        const fresh = await cl.meta(initial.path);
        if (live) setEntry(fresh);
      } catch {
        // keep the listed entry
      }
    });
    return () => {
      live = false;
    };
  }, [visible, host, initial.path]);

  const isFav = entry.isDir && favorites.some((f) => f.hostId === host.id && f.path === entry.path);
  const previewable = !entry.isDir && isPreviewable(entry);
  const changed = () => onChanged?.();

  /** Runs a client call; failures toast. Toasts render under the sheet's window, so a still-open sheet is closed first. */
  async function run<T>(task: (cl: AgentClient) => Promise<T>, fail: (e: string) => string, closeOnError = false): Promise<T | undefined> {
    try {
      return await task(client ?? (await clientForHost(host)));
    } catch (e) {
      if (closeOnError) onClose();
      toast.error(fail(humanizeError(e)));
      return undefined;
    }
  }

  async function favorite() {
    onClose();
    await toggleFavorite({ hostId: host.id, path: entry.path, label: folderLabel(entry.path) });
    if (isFav) toast.info(t('removedFavorite', { name: entry.name }));
    else toast.success(t('addedFavorite', { name: entry.name }));
  }

  async function download() {
    onClose();
    try {
      await enqueueDownloads(host, [entry.path]);
      toast.info(t('downloadingFile', { name: entry.name }));
    } catch (e) {
      toast.error(humanizeError(e));
    }
  }

  async function rename() {
    onClose();
    const name = await dialogs.prompt({ title: t('renameButton'), placeholder: t('newNameLabel'), initialValue: entry.name, confirmLabel: t('renameButton') });
    if (!name || name === entry.name) return;
    const updated = await run((cl) => cl.rename(entry.path, renameDestination(entry.path, name)), (e) => t('renameFailed', { error: e }));
    if (updated) {
      changed();
      toast.success(t('renamedTo', { newName: name }));
    }
  }

  async function duplicate() {
    onClose();
    const res = await run((cl) => cl.copy([entry.path], parentDirOf(entry.path), { duplicate: true }), (e) => t('duplicateFailed', { error: e }));
    if (!res) return;
    if (!(res.results.length > 0 && res.results[0].ok)) return void toast.error(t('couldNotDuplicate', { name: entry.name }));
    changed();
    toast.success(t('duplicatedFile', { name: entry.name }));
  }

  async function extract() {
    onClose();
    const out = await run((cl) => cl.extract(entry.path, parentDirOf(entry.path)), (e) => t('extractFailed', { error: e }));
    if (out) {
      changed();
      toast.success(t('extractedFile', { name: entry.name }));
    }
  }

  async function remove() {
    onClose();
    const choice = await dialogs.choose<'trash' | 'forever'>({
      title: t('deleteTitle'),
      subtitle: t('moveToTrashConfirm', { name: entry.name }),
      tint: c.error,
      options: [
        { value: 'trash', label: t('moveToTrashButton') },
        { value: 'forever', label: t('deleteForeverButton'), tint: c.error },
      ],
    });
    if (!choice) return;
    const permanent = choice === 'forever';
    const res = await run((cl) => cl.delete([entry.path], { permanent }), (e) => t('deleteFailed', { error: e }));
    if (res) {
      changed();
      toast.success(permanent ? t('deletedName', { name: entry.name }) : t('movedToTrashName', { name: entry.name }));
    }
  }

  async function shareLink() {
    const minted = await run((cl) => cl.mintShareLink(entry.path), (e) => t('shareLinkFailed', { error: e }), true);
    if (minted) setLink(minted);
  }

  /** The QR names the host by its secure-store pin, never the record's mirrored copy. */
  async function sendViaQr() {
    const pin = await hostStore.getPin(host.id).catch(() => null);
    if (!pin) return void toast.error(t('qrHandoffNoFingerprint'));
    setQr({ certFingerprint: pin, path: entry.path, name: entry.name });
  }

  async function computeChecksum() {
    setChecksumBusy(true);
    const sum = await run((cl) => cl.checksum(entry.path), (e) => `Checksum failed: ${e}`);
    if (sum) setChecksum(sum);
    setChecksumBusy(false);
  }

  const quick: Action[] = ([
    entry.isDir
      ? { key: 'fav', icon: Star, label: isFav ? t('unfavoriteButton') : t('favoriteButton'), onPress: favorite }
      : previewable && onPreview
        ? { key: 'preview', icon: Eye, label: t('previewButton'), onPress: () => { onClose(); onPreview(entry); } }
        : null,
    entry.isDir
      ? allowed('modify') ? { key: 'rename', icon: FilePen, label: t('renameButton'), onPress: rename } : null
      : allowed('download') ? { key: 'download', icon: Download, label: t('downloadButton'), onPress: download } : null,
    entry.isDir && allowed('modify') ? { key: 'dup', icon: Copy, label: t('duplicateButton'), onPress: duplicate } : null,
    allowed('delete') ? { key: 'delete', icon: Trash2, label: t('deleteButton'), onPress: remove, tint: c.error } : null,
  ] as (Action | null)[]).filter((a): a is Action => a !== null);

  const more: Action[] = ([
    !entry.isDir && allowed('download') ? { key: 'openwith', icon: ExternalLink, label: t('openWithButton'), onPress: () => { onClose(); void external.openWith(entry); } } : null,
    !entry.isDir && allowed('download') ? { key: 'share', icon: Share2, label: t('shareTooltip'), onPress: () => { onClose(); void external.share(entry); } } : null,
    !entry.isDir && allowed('share') ? { key: 'link', icon: LinkIcon, label: t('shareLinkButton'), onPress: shareLink } : null,
    !entry.isDir && allowed('download') ? { key: 'qr', icon: QrCode, label: t('qrHandoffSheetTitle'), onPress: () => void sendViaQr() } : null,
    !entry.isDir && allowed('modify') && isExtractableArchive(entry.name) ? { key: 'extract', icon: Archive, label: t('extractHereButton'), onPress: extract } : null,
    !entry.isDir && allowed('modify') ? { key: 'rename', icon: FilePen, label: t('renameButton'), onPress: rename } : null,
    !entry.isDir && allowed('modify') ? { key: 'dup', icon: Copy, label: t('duplicateButton'), onPress: duplicate } : null,
    { key: 'details', icon: Info, label: t('detailsButton'), onPress: () => setView('details') },
  ] as (Action | null)[]).filter((a): a is Action => a !== null);

  const subtitle = [entry.size != null ? formatSize(entry.size) : null, entry.modified ? formatDate(new Date(entry.modified)) : null].filter(Boolean).join(' · ');

  return (
    <>
      <BottomSheet visible={visible && link === null && qr === null} onClose={onClose}>
        {view === 'actions' ? (
          <ScrollView>
            <SheetHero badge={<EntryLeading entry={entry} size={30} />} badgeColor={chip} title={entry.name} subtitle={subtitle} onClose={onClose} />
            <View style={{ paddingHorizontal: Spacing.lg, paddingBottom: Spacing.xl, gap: Spacing.md }}>
              <View style={{ flexDirection: 'row' }}>
                {quick.map((a) => (
                  <QuickAction key={a.key} action={a} />
                ))}
              </View>
              <View>
                {more.map((a, i) => (
                  <MoreRow key={a.key} action={a} divider={i > 0} />
                ))}
              </View>
            </View>
          </ScrollView>
        ) : (
          <ScrollView>
            <View style={{ paddingTop: Spacing.md, paddingHorizontal: Spacing.lg, paddingBottom: Spacing.xl, gap: Spacing.md }}>
              <SheetGrabber />
              <Text variant="titleLarge">{t('detailsButton')}</Text>
              <View style={{ backgroundColor: c.surface, borderRadius: Radii.card, borderWidth: 1, borderColor: c.outlineVariant, paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs }}>
                <DetailRows entry={entry} checksum={checksum} checksumBusy={checksumBusy} onComputeChecksum={computeChecksum} onEditPermissions={() => setChmodOpen(true)} />
              </View>
            </View>
          </ScrollView>
        )}
      </BottomSheet>
      {client && (
        <ChmodDialog
          visible={chmodOpen}
          entry={entry}
          client={client}
          onClose={() => setChmodOpen(false)}
          onApplied={(updated) => {
            setEntry(updated);
            setChmodOpen(false);
            changed();
          }}
        />
      )}
      {qr && <HandoffQrSheet visible payload={qr} onClose={() => { setQr(null); onClose(); }} />}
      {link && client && <ShareLinkSheet visible client={client} link={link} fileName={entry.name} onClose={() => { setLink(null); onClose(); }} />}
    </>
  );
}

function QuickAction({ action }: { action: Action }) {
  const c = useScheme();
  const Icon = action.icon;
  return (
    <Pressable onPress={action.onPress} accessibilityLabel={action.label} style={{ flex: 1 }}>
      <View style={{ marginHorizontal: 3, paddingVertical: Spacing.md2, paddingHorizontal: Spacing.xs, borderWidth: 1, borderColor: c.outlineVariant, borderRadius: Radii.sm, alignItems: 'center', gap: Spacing.xs }}>
        <Icon size={20} color={action.tint ?? c.primary} />
        <Text numberOfLines={1} color={action.tint} style={{ textAlign: 'center', fontSize: 11.5 }}>{action.label}</Text>
      </View>
    </Pressable>
  );
}

function MoreRow({ action, divider }: { action: Action; divider: boolean }) {
  const c = useScheme();
  const Icon = action.icon;
  return (
    <Pressable onPress={action.onPress} accessibilityLabel={action.label}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: Spacing.md, paddingVertical: Spacing.sm, borderTopWidth: divider ? 1 : 0, borderColor: c.outlineVariant }}>
        <View style={{ width: 38, height: 38, borderRadius: Radii.sm, backgroundColor: c.surfaceContainerHighest, alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={18} color={c.onSurfaceVariant} />
        </View>
        <Text variant="bodyLarge">{action.label}</Text>
      </View>
    </Pressable>
  );
}

function DetailRows({ entry, checksum, checksumBusy, onComputeChecksum, onEditPermissions }: { entry: Entry; checksum: string | null; checksumBusy: boolean; onComputeChecksum: () => void; onEditPermissions: () => void }) {
  const c = useScheme();
  const toast = useToast();
  const rows: ReactNode[] = [];
  const add = (key: string, icon: LucideIcon, label: string, value: ReactNode, onPress?: () => void) => rows.push(<DetailRow key={key} icon={icon} label={label} value={value} onPress={onPress} />);
  add('path', Route, t('metaPath'), entry.path);
  if (entry.size != null) add('size', Ruler, t('metaSize'), formatSize(entry.size));
  if (entry.mimeType) add('type', Tag, t('metaType'), entry.mimeType);
  if (entry.mode) add('mode', Lock, t('metaPermissions'), entry.mode, onEditPermissions);
  if (entry.modified) add('mod', CalendarClock, t('metaModified'), new Date(entry.modified).toLocaleString());
  if (entry.created) add('created', Calendar, t('metaCreated'), new Date(entry.created).toLocaleString());
  add('link', LinkIcon, t('metaSymlink'), entry.isSymlink ? (entry.symlinkTarget ?? t('yesLabel')) : t('noLabel'));
  if (!entry.isDir) {
    add(
      'sum',
      Tag,
      'SHA-256',
      checksum ? (
        <Text selectable style={{ fontFamily: FontFamily.mono, fontSize: 12 }} onLongPress={() => void Clipboard.setStringAsync(checksum).then(() => toast.info(t('copiedPath', { path: checksum })))}>{checksum}</Text>
      ) : (
        <Pressable onPress={checksumBusy ? undefined : onComputeChecksum} accessibilityLabel="Compute checksum">
          <Text color={c.primary} style={{ textDecorationLine: 'underline' }}>{checksumBusy ? '…' : 'Compute'}</Text>
        </Pressable>
      ),
    );
  }
  return (
    <>
      {rows.map((r, i) => (
        <View key={i} style={{ borderTopWidth: i ? 1 : 0, borderColor: c.outlineVariant }}>{r}</View>
      ))}
    </>
  );
}

function DetailRow({ icon: Icon, label, value, onPress }: { icon: LucideIcon; label: string; value: ReactNode; onPress?: () => void }) {
  const c = useScheme();
  const body = (
    <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: Spacing.sm, paddingVertical: Spacing.sm }}>
      <Icon size={18} color={c.onSurfaceVariant} />
      <Text variant="labelLarge" muted style={{ width: 100 }}>{label}</Text>
      <View style={{ flex: 1 }}>{typeof value === 'string' ? <Text>{value}</Text> : value}</View>
    </View>
  );
  return onPress ? <Pressable onPress={onPress} accessibilityLabel={label}>{body}</Pressable> : body;
}
