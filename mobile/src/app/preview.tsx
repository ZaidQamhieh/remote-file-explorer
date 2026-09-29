import { Stack, useRouter } from 'expo-router';
import { Download, FileCode, Info, ListOrdered, Pencil, Trash2 } from 'lucide-react-native';
import { useCallback, useRef, useState } from 'react';
import { FlatList, StatusBar, useWindowDimensions, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { Entry } from '../core/api/models';
import { ActionListCard, ActionListTile, BottomSheet, SheetHead, Text, useDialogs, useToast } from '../design/components';
import { useScheme } from '../design/theme';
import { lightScheme, Radii, Spacing } from '../design/tokens';
import { t } from '../i18n';
import { clientForHost } from '../services';
import { humanizeError } from '../features/pairing/pairingService';
import { MetaSheet } from '../features/explorer/MetaSheet';
import { PreviewIconButton, PreviewTopBar } from '../features/preview/PreviewChrome';
import { MAX_EDITABLE_BYTES } from '../features/preview/previewFile';
import { previewKindOf } from '../features/preview/previewKind';
import { useEditorSession, usePreviewSession } from '../features/preview/session';
import { utf8Length } from '../features/preview/textDecode';
import { PreviewPage } from '../features/preview/viewers/PreviewPage';
import { enqueueDownloads } from '../features/transfers/enqueueDownloads';

/**
 * Port of PreviewPager: swipe between the previewable siblings the explorer handed over, one shared
 * top bar for the current page, and a "n of m" indicator.
 */
export default function Preview() {
  const session = usePreviewSession((s) => s.session);
  const router = useRouter();
  if (!session || session.entries.length === 0) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <Stack.Screen options={{ headerShown: false }} />
        <Text muted>Nothing to preview.</Text>
      </View>
    );
  }
  return <Pager key={session.entries[session.index]?.path} onClose={() => router.back()} />;
}

function Pager({ onClose }: { onClose: () => void }) {
  const c = useScheme();
  const toast = useToast();
  const dialogs = useDialogs();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const session = usePreviewSession((s) => s.session)!;
  const openEditor = useEditorSession((s) => s.open);
  const [entries, setEntries] = useState<Entry[]>(session.entries);
  const [index, setIndex] = useState(Math.min(Math.max(session.index, 0), session.entries.length - 1));
  const [zoomed, setZoomed] = useState(false);
  const [lineNumbers, setLineNumbers] = useState(false);
  const [rawMarkdown, setRawMarkdown] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const [metaOpen, setMetaOpen] = useState(false);
  const [texts, setTexts] = useState<Record<string, string>>({});
  const list = useRef<FlatList<Entry>>(null);

  const current = entries[index];
  const kind = previewKindOf(current);
  const onDark = kind === 'image' || kind === 'video';
  const loadedText = texts[current.path] as string | undefined;
  const canEdit = (kind === 'text' || kind === 'markdown') && loadedText !== undefined && (current.size ?? utf8Length(loadedText)) <= MAX_EDITABLE_BYTES;

  const onText = useCallback((path: string, text: string | null) => {
    setTexts((m) => {
      if (text === null) {
        if (!(path in m)) return m;
        const { [path]: _drop, ...rest } = m;
        return rest;
      }
      return m[path] === text ? m : { ...m, [path]: text };
    });
  }, []);

  function replaceCurrent(e: Entry) {
    setEntries((l) => l.map((x) => (x.path === e.path ? e : x)));
    session.onChanged?.();
  }

  function dropCurrent() {
    session.onChanged?.();
    if (entries.length <= 1) return onClose();
    const next = entries.filter((_, i) => i !== index);
    const ni = Math.min(index, next.length - 1);
    setEntries(next);
    setIndex(ni);
    requestAnimationFrame(() => list.current?.scrollToIndex({ index: ni, animated: false }));
  }

  async function save() {
    setMoreOpen(false);
    try {
      await enqueueDownloads(session.host, [current.path]);
      toast.info(t('savingFile', { name: current.name }));
    } catch (e) {
      toast.error(humanizeError(e));
    }
  }

  async function remove() {
    setMoreOpen(false);
    const choice = await dialogs.choose<'trash' | 'forever'>({
      title: t('deleteTitle'),
      subtitle: t('moveToTrashConfirm', { name: current.name }),
      options: [
        { value: 'trash', label: t('moveToTrashButton') },
        { value: 'forever', label: t('deleteForeverButton'), tint: c.error },
      ],
    });
    if (!choice) return;
    try {
      const client = await clientForHost(session.host);
      await client.delete([current.path], { permanent: choice === 'forever' });
      toast.success(choice === 'forever' ? t('deletedName', { name: current.name }) : t('movedToTrashName', { name: current.name }));
      dropCurrent();
    } catch (e) {
      toast.error(t('deleteFailed', { error: humanizeError(e) }));
    }
  }

  function edit() {
    if (loadedText === undefined) return;
    openEditor({
      host: session.host,
      entry: current,
      text: loadedText,
      onSaved: (e) => {
        onText(e.path, null);
        replaceCurrent(e);
      },
    });
    router.push('/edit');
  }

  const leading = (
    <>
      {kind === 'text' && (
        <PreviewIconButton label="Line numbers" selected={lineNumbers} onPress={() => setLineNumbers((v) => !v)}>
          <ListOrdered size={19} color={lineNumbers ? c.primary : c.onSurfaceVariant} />
        </PreviewIconButton>
      )}
      {kind === 'markdown' && (
        <PreviewIconButton label="Show source" selected={rawMarkdown} onPress={() => setRawMarkdown((v) => !v)}>
          <FileCode size={19} color={rawMarkdown ? c.primary : c.onSurfaceVariant} />
        </PreviewIconButton>
      )}
      {canEdit && (
        <PreviewIconButton label="Edit" onPress={edit}>
          <Pencil size={19} color={c.onSurfaceVariant} />
        </PreviewIconButton>
      )}
    </>
  );

  return (
    <View style={{ flex: 1, backgroundColor: onDark ? '#000' : c.surface }}>
      <Stack.Screen options={{ headerShown: false }} />
      <StatusBar barStyle={onDark || c.surface !== lightScheme.surface ? 'light-content' : 'dark-content'} />
      <PreviewTopBar entry={current} onDark={onDark} onBack={onClose} onShare={() => toast.info('Share links arrive with the shares port (phase 5).')} onMore={() => setMoreOpen(true)} leading={leading} />
      <FlatList
        ref={list}
        data={entries}
        horizontal
        pagingEnabled
        scrollEnabled={!zoomed}
        keyExtractor={(e) => e.path}
        initialScrollIndex={index}
        getItemLayout={(_, i) => ({ length: width, offset: width * i, index: i })}
        windowSize={3}
        initialNumToRender={1}
        maxToRenderPerBatch={1}
        showsHorizontalScrollIndicator={false}
        onMomentumScrollEnd={(e) => {
          const i = Math.round(e.nativeEvent.contentOffset.x / width);
          if (i !== index && i >= 0 && i < entries.length) {
            setIndex(i);
            setZoomed(false);
          }
        }}
        renderItem={({ item, index: i }) => (
          // Documents stop above the gesture bar; image/video stay full-bleed.
          <View style={{ width, flex: 1, paddingBottom: ['image', 'video'].includes(previewKindOf(item)) ? 0 : insets.bottom }}>
            <PreviewPage host={session.host} entry={item} isCurrent={i === index} lineNumbers={lineNumbers} rawMarkdown={rawMarkdown} onZoomChange={setZoomed} onText={onText} />
          </View>
        )}
      />
      {entries.length > 1 && (
        <View pointerEvents="none" style={{ position: 'absolute', bottom: insets.bottom + Spacing.md, left: 0, right: 0, alignItems: 'center' }}>
          <View style={{ backgroundColor: 'rgba(0,0,0,0.54)', borderRadius: Radii.stadium, paddingHorizontal: Spacing.md, paddingVertical: Spacing.xs }}>
            <Text variant="bodySmall" color="#FFFFFF">{t('previewPageIndicator', { current: index + 1, total: entries.length })}</Text>
          </View>
        </View>
      )}
      <BottomSheet visible={moreOpen} onClose={() => setMoreOpen(false)}>
        <SheetHead title={current.name} />
        <View style={{ padding: Spacing.md }}>
          <ActionListCard>
            {[
              <ActionListTile key="info" icon={<Info size={20} color={c.onSurfaceVariant} />} label={t('detailsButton')} onPress={() => { setMoreOpen(false); setMetaOpen(true); }} />,
              <ActionListTile key="save" icon={<Download size={20} color={c.onSurfaceVariant} />} label={t('downloadButton')} onPress={save} />,
              <ActionListTile key="del" icon={<Trash2 size={20} color={c.error} />} label={t('deleteButton')} tint={c.error} onPress={remove} />,
            ]}
          </ActionListCard>
        </View>
      </BottomSheet>
      {/* Mutations here (rename, delete, extract...) leave the pager stale, so they return to the refreshed folder. */}
      {metaOpen && <MetaSheet visible host={session.host} entry={current} onClose={() => setMetaOpen(false)} onChanged={() => { session.onChanged?.(); onClose(); }} />}
    </View>
  );
}
