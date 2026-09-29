import { ClipboardPaste, FilePlus, FolderPlus, Upload } from 'lucide-react-native';

import { BottomSheet, GradientActionCircle, QuickActionRow, SheetGrabber } from '../../design/components';
import { Spacing } from '../../design/tokens';
import { t } from '../../i18n';
import { View } from 'react-native';

/** "+" sheet: new folder / new file / upload / paste (paste only when the clipboard belongs to this host). */
export function CreateMenu({ visible, onClose, onNewFolder, onNewFile, onUpload, onPaste, pasteLabel }: { visible: boolean; onClose: () => void; onNewFolder: () => void; onNewFile: () => void; onUpload?: () => void; onPaste?: () => void; pasteLabel?: string }) {
  const go = (fn?: () => void) => () => {
    onClose();
    fn?.();
  };
  return (
    <BottomSheet visible={visible} onClose={onClose}>
      <View style={{ padding: Spacing.lg, paddingTop: Spacing.md, gap: Spacing.md }}>
        <SheetGrabber />
        <QuickActionRow>
          <GradientActionCircle icon={<FolderPlus size={20} color="#fff" />} label={t('newFolderButton')} gradient={['#42A5F5', '#1565C0']} onPress={go(onNewFolder)} />
          <GradientActionCircle icon={<FilePlus size={20} color="#fff" />} label={t('newFileButton')} gradient={['#66BB6A', '#2E7D32']} onPress={go(onNewFile)} />
          {onUpload && <GradientActionCircle icon={<Upload size={20} color="#fff" />} label={t('uploadFileTooltip')} gradient={['#FFA726', '#EF6C00']} onPress={go(onUpload)} />}
          {onPaste && pasteLabel && <GradientActionCircle icon={<ClipboardPaste size={20} color="#fff" />} label={pasteLabel} gradient={['#AB47BC', '#6A1B9A']} onPress={go(onPaste)} />}
        </QuickActionRow>
      </View>
    </BottomSheet>
  );
}
