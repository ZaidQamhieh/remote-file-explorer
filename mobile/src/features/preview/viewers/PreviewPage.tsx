import { FileQuestion } from 'lucide-react-native';
import { memo, useCallback } from 'react';
import { View } from 'react-native';

import type { Entry } from '../../../core/api/models';
import type { Host } from '../../../core/models/host';
import { Text } from '../../../design/components';
import { useScheme } from '../../../design/theme';
import { Spacing } from '../../../design/tokens';
import { previewKindOf } from '../previewKind';
import { ArchiveViewer } from './ArchiveViewer';
import { CsvViewer } from './CsvViewer';
import { ImageViewer } from './ImageViewer';
import { MarkdownViewer } from './MarkdownViewer';
import { PdfViewer } from './PdfViewer';
import { TextViewer } from './TextViewer';

type Props = {
  host: Host;
  entry: Entry;
  isCurrent: boolean;
  lineNumbers: boolean;
  rawMarkdown: boolean;
  onZoomChange: (zoomed: boolean) => void;
  onText: (path: string, text: string | null) => void;
};

/** Port of _viewerFor: the chromeless per-kind viewer for one pager page. */
export const PreviewPage = memo(function PreviewPage({ host, entry, isCurrent, lineNumbers, rawMarkdown, onZoomChange, onText }: Props) {
  const reportText = useCallback((text: string | null) => onText(entry.path, text), [onText, entry.path]);
  switch (previewKindOf(entry)) {
    case 'image':
      return <ImageViewer host={host} entry={entry} onZoomChange={isCurrent ? onZoomChange : undefined} />;
    case 'text':
      return <TextViewer host={host} entry={entry} showLineNumbers={lineNumbers} onText={reportText} />;
    case 'markdown':
      return <MarkdownViewer host={host} entry={entry} raw={rawMarkdown} onText={reportText} />;
    case 'csv':
      return <CsvViewer host={host} entry={entry} />;
    case 'archive':
      return <ArchiveViewer host={host} entry={entry} />;
    case 'pdf':
      return <PdfViewer host={host} entry={entry} />;
    default:
      return <NotPortedYet kind={previewKindOf(entry)} />;
  }
});

/** Video and audio land with the pinned media proxy (rfe-c1x.7). */
function NotPortedYet({ kind }: { kind: string }) {
  const c = useScheme();
  const dark = kind === 'video';
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: Spacing.lg, gap: Spacing.md }}>
      <FileQuestion size={48} color={dark ? '#FFFFFF' : c.outline} />
      <Text style={{ textAlign: 'center' }} color={dark ? '#FFFFFF' : undefined}>
        {`The ${kind.toUpperCase()} viewer isn't in this build yet. Use ⋮ → Download to save the file.`}
      </Text>
    </View>
  );
}
