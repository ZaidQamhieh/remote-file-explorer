import { Directory, File, Paths } from 'expo-file-system';

import type { Host } from '../../core/models/host';
import { transfers } from '../../core/native';
import { clientForHost } from '../../services';
import { joinRemotePath } from '../explorer/paths';
import type { UploadItem } from './uploadPlan';

const newTransferId = () => `u${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const toPath = (uri: string) => decodeURIComponent(uri.replace('file://', ''));

/**
 * Queues durable native uploads of [items] into [destDir]. Each picked file is moved from the picker's cache into
 * app-private storage first so it survives a cleared cache and a restart, and the engine deletes it when the
 * upload is done or cancelled. Returns how many were queued.
 */
export async function enqueueUploads(host: Host, destDir: string, items: UploadItem[]): Promise<number> {
  const address = (await clientForHost(host)).activeAddress ?? host.address;
  let queued = 0;
  for (const item of items) {
    const id = newTransferId();
    const dir = new Directory(Paths.document, 'uploads', id);
    dir.create({ idempotent: true, intermediates: true });
    const staged = new File(dir, item.targetName);
    new File(item.source.uri).move(staged);
    await transfers.enqueueUpload(id, host.id, address, toPath(staged.uri), joinRemotePath(destDir, item.targetName), item.overwrite, true);
    queued++;
  }
  return queued;
}
