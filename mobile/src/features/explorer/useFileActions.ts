import { SkipForward, CopyPlus, RefreshCw, X } from 'lucide-react-native';
import { createElement } from 'react';

import type { Entry , BatchResult } from '../../core/api/models';
import type { Host } from '../../core/models/host';
import { useDialogs, useToast } from '../../design/components';
import { useScheme } from '../../design/theme';
import { t } from '../../i18n';
import { humanizeError } from '../pairing/pairingService';
import { useFileClipboard } from './clipboard';
import { currentPath, type Explorer, type ExplorerState } from './explorerStore';
import { basenameOf, folderLabel, parentDirOf } from './paths';

export type ConflictResolution = 'keepBoth' | 'overwrite' | 'skip' | 'cancel';

/** Ports the explorer screen's copy/cut/paste/delete/compress flows, keeping their dialogs, messages and precedence rules. */
export function useFileActions(host: Host, ex: Explorer & { getState(): ExplorerState }) {
  const dialogs = useDialogs();
  const toast = useToast();
  const c = useScheme();
  const clip = useFileClipboard();

  async function askConflict(colliding: number, total: number, dest: string): Promise<ConflictResolution> {
    const r = await dialogs.choose<ConflictResolution>({
      title: t('nameConflictTitle'),
      subtitle: t('nameConflictBody', { collidingCount: colliding, totalCount: total, dest: folderLabel(dest) }),
      tint: '#F3A73F',
      options: [
        { value: 'skip', label: t('skipTheseButton'), icon: createElement(SkipForward, { size: 20, color: c.onSurfaceVariant }) },
        { value: 'keepBoth', label: t('keepBothButton'), icon: createElement(CopyPlus, { size: 20, color: c.onSurfaceVariant }) },
        { value: 'overwrite', label: t('overwriteButton'), tint: c.error, icon: createElement(RefreshCw, { size: 20, color: c.error }) },
        { value: 'cancel', label: t('cancelButton'), icon: createElement(X, { size: 20, color: c.onSurfaceVariant }) },
      ],
    });
    return r ?? 'cancel';
  }

  async function reportBatch(res: BatchResult, verb: string) {
    if (res.failed.length === 0) {
      toast.success(t('batchSuccessNItems', { verb, count: res.results.length }));
      return;
    }
    await dialogs.report({
      title: t('batchResultWithErrors', { verb, errorCount: res.failed.length }),
      items: res.failed.map((f) => ({ primary: f.path, secondary: f.errorMessage ?? f.errorCode ?? 'failed' })),
    });
  }

  const copySelection = () => {
    const paths = [...ex.getState().selected];
    if (paths.length === 0) return;
    clip.copy(paths, host.id);
    ex.clearSelection();
    toast.success(t('clipboardCopiedHint', { count: paths.length }));
  };

  const cutSelection = () => {
    const paths = [...ex.getState().selected];
    if (paths.length === 0) return;
    clip.cut(paths, host.id);
    ex.clearSelection();
    toast.success(t('clipboardCutHint', { count: paths.length }));
  };

  /** Pastes the in-app clipboard into the current folder with a pre-flight collision check. */
  async function paste() {
    const clipboard = useFileClipboard.getState().clip;
    if (!clipboard) return;
    const dest = currentPath(ex.getState());
    const isCut = clipboard.mode === 'cut';
    if (isCut && clipboard.paths.every((p) => parentDirOf(p) === dest)) {
      toast.info(t('alreadyInThisFolder'));
      return;
    }
    let duplicate = false;
    let overwrite = false;
    let sources = clipboard.paths;
    try {
      const colliding = await ex.collidingBasenames(dest, sources);
      if (colliding.size > 0) {
        const res = await askConflict(colliding.size, sources.length, dest);
        if (res === 'cancel') return;
        if (res === 'keepBoth') duplicate = true;
        if (res === 'overwrite') overwrite = true;
        if (res === 'skip') {
          sources = sources.filter((p) => !colliding.has(basenameOf(p)));
          if (sources.length === 0) {
            toast.info(t('clipboardAllExistNothing', { folder: folderLabel(dest), operation: isCut ? t('moveLabel') : t('copyLabel') }));
            return;
          }
        }
      }
    } catch (e) {
      toast.error(t('couldNotCheckFolder', { folder: folderLabel(dest), error: humanizeError(e) }), () => void paste());
      return;
    }
    try {
      const res = isCut ? await ex.moveSelected(dest, { sources, duplicate, overwrite }) : await ex.copySelected(dest, { sources, duplicate, overwrite });
      if (isCut) clip.clear();
      await reportBatch(res, isCut ? t('movedLabel') : t('copiedLabel'));
    } catch (e) {
      toast.error(t('operationFailed', { operation: isCut ? t('moveLabel') : t('copyLabel'), error: humanizeError(e) }), () => void paste());
    }
  }

  /** Delete: three-way dialog (cancel / delete forever / move to trash). */
  async function confirmDelete() {
    const count = ex.getState().selected.size;
    if (count === 0) return;
    const choice = await dialogs.choose<'forever' | 'trash'>({
      title: t('deleteTitle'),
      subtitle: `${t('moveNItemsToTrash', { count })} ${t('canRestoreFromTrash', { count })}`,
      tint: c.error,
      options: [
        { value: 'trash', label: t('moveToTrashButton') },
        { value: 'forever', label: t('deleteForeverButton'), tint: c.error },
      ],
    });
    if (choice === null) return;
    const permanent = choice === 'forever';
    try {
      const res = await ex.deleteSelected({ permanent });
      await reportBatch(res, permanent ? t('deletedLabel') : t('movedToTrashLabel'));
    } catch (e) {
      toast.error(t('deleteFailed', { error: humanizeError(e) }));
    }
  }

  async function compressSelected() {
    const paths = [...ex.getState().selected];
    if (paths.length === 0) return;
    const dir = currentPath(ex.getState());
    const sep = dir.includes('\\') ? '\\' : '/';
    const stem = paths.length === 1 ? basenameOf(paths[0]) : folderLabel(dir) === 'Root' ? 'Archive' : folderLabel(dir);
    const dest = dir.endsWith(sep) ? `${dir}${stem}.zip` : `${dir}${sep}${stem}.zip`;
    try {
      const entry = await ex.compressSelected(dest, paths);
      ex.clearSelection();
      toast.success(t('compressedTo', { name: entry.name }));
    } catch (e) {
      toast.error(t('compressFailed', { error: humanizeError(e) }));
    }
  }

  async function createNamed(isFolder: boolean) {
    const title = isFolder ? t('newFolderButton') : t('newFileButton');
    const name = await dialogs.prompt({ title, placeholder: t('nameHint'), confirmLabel: t('createButton') });
    if (!name) return;
    try {
      if (isFolder) await ex.createFolder(name);
      else await ex.createFile(name);
      toast.success(t('createdName', { name }));
    } catch (e) {
      toast.error(t('createFailed', { name, error: humanizeError(e) }));
    }
  }

  async function rename(entry: Entry) {
    const name = await dialogs.prompt({ title: 'Rename', initialValue: entry.name, confirmLabel: 'Rename' });
    if (!name || name === entry.name) return;
    try {
      await ex.rename(entry.path, name);
      toast.success(t('renamedLabel'));
    } catch (e) {
      toast.error(t('renameFailed', { error: humanizeError(e) }));
    }
  }

  /** Applies [newNames] (aligned with [paths]) through the store's two-phase rename, then reports per-item failures. */
  async function applyBatchRename(paths: string[], newNames: string[]) {
    try {
      const res = await ex.batchRename(paths.map((path, i) => ({ path, newName: newNames[i] })));
      ex.clearSelection();
      await reportBatch(res, t('renamedLabel'));
    } catch (e) {
      toast.error(t('renameFailed', { error: humanizeError(e) }));
    }
  }

  return { copySelection, cutSelection, paste, confirmDelete, compressSelected, createNamed, rename, applyBatchRename, askConflict, reportBatch };
}
