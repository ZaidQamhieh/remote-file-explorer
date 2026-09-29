import { File } from 'expo-file-system';
import { useEffect, useState } from 'react';
import { FlatList, View } from 'react-native';

import type { Entry } from '../../../core/api/models';
import type { Host } from '../../../core/models/host';
import { Text } from '../../../design/components';
import { useScheme } from '../../../design/theme';
import { FontFamily, Spacing } from '../../../design/tokens';
import { humanizeError } from '../../pairing/pairingService';
import { PreviewError, PreviewLoading, PreviewTooLarge } from '../PreviewChrome';
import { MAX_IN_MEMORY_PREVIEW_BYTES, usePreviewFile } from '../previewFile';
import { NotTextError, decodeAsText } from '../textDecode';

export const MONO = { fontFamily: FontFamily.mono, fontSize: 13, lineHeight: 18.2 } as const;

type Loaded = { status: 'idle' } | { status: 'ready'; text: string } | { status: 'error'; error: unknown };

/** Fetches [entry] and decodes it as strict UTF-8 (shared by the text, markdown and CSV viewers). */
export function usePreviewText(host: Host, entry: Entry) {
  const { state, retry } = usePreviewFile(host, entry, MAX_IN_MEMORY_PREVIEW_BYTES);
  const [loaded, setLoaded] = useState<Loaded>({ status: 'idle' });
  const uri = state.status === 'ready' ? state.uri : null;
  useEffect(() => {
    if (!uri) return;
    let live = true;
    new File(uri).bytes().then(
      (b) => {
        if (!live) return;
        try {
          setLoaded({ status: 'ready', text: decodeAsText(b) });
        } catch (error) {
          setLoaded({ status: 'error', error });
        }
      },
      (error) => live && setLoaded({ status: 'error', error }),
    );
    return () => {
      live = false;
    };
  }, [uri]);
  return { file: state, text: loaded, retry };
}

/** Shared loading / too-large / error body for the text-based viewers; null once the text is ready. */
export function textStateView(file: ReturnType<typeof usePreviewText>['file'], text: Loaded, retry: () => void, loadingLabel: string) {
  if (file.status === 'tooLarge') return <PreviewTooLarge size={file.size} />;
  if (file.status === 'error') return <PreviewError message={`Could not load this file.\n${humanizeError(file.error)}`} onRetry={retry} />;
  if (text.status === 'error') {
    return text.error instanceof NotTextError ? <PreviewError message={text.error.message} /> : <PreviewError message={`Could not load this file.\n${humanizeError(text.error)}`} onRetry={retry} />;
  }
  if (text.status !== 'ready') return <PreviewLoading message={loadingLabel} />;
  return null;
}

/** Port of TextPreviewScreen's body: monospace, selectable, optional 1-based line-number gutter. */
export function TextViewer({ host, entry, showLineNumbers, onText }: { host: Host; entry: Entry; showLineNumbers: boolean; onText?: (text: string | null) => void }) {
  const c = useScheme();
  const { file, text, retry } = usePreviewText(host, entry);
  const ready = text.status === 'ready' ? text.text : null;
  useEffect(() => onText?.(ready), [ready, onText]);
  const lines = ready === null ? [] : ready.split('\n');
  const gutter = String(lines.length).length;

  const pending = textStateView(file, text, retry, 'Loading text…');
  if (pending) return pending;
  if (ready === '') {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <Text color={c.outline}>(empty file)</Text>
      </View>
    );
  }
  return (
    <FlatList
      data={lines}
      keyExtractor={(_, i) => String(i)}
      contentContainerStyle={{ padding: Spacing.md }}
      initialNumToRender={60}
      windowSize={11}
      renderItem={({ item, index }) => (
        <View style={{ flexDirection: 'row' }}>
          {showLineNumbers && (
            <Text style={[MONO, { color: c.outline, textAlign: 'right', width: gutter * 8 + 4, marginRight: Spacing.md }]} selectable={false}>
              {index + 1}
            </Text>
          )}
          <Text selectable style={[MONO, { flex: 1, color: c.onSurface }]}>{item.length ? item : ' '}</Text>
        </View>
      )}
    />
  );
}
