import { Directory, File, Paths } from 'expo-file-system';

import type { Host } from '../../core/models/host';
import { transfers } from '../../core/native';
import { clientForHost } from '../../services';

/** Local, non-secret id for a transfer journal entry. */
const newTransferId = () => `d${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

/**
 * Queues durable native downloads of [paths] into the app's downloads folder (public Downloads via
 * MediaStore is rfe-bvw.7). Uses the route the client last reached the host on.
 */
export async function enqueueDownloads(host: Host, paths: string[]): Promise<void> {
  const dir = new Directory(Paths.document, 'downloads');
  dir.create({ idempotent: true, intermediates: true });
  const address = (await clientForHost(host)).activeAddress ?? host.address;
  for (const p of paths) {
    const name = p.split(/[/\\]/).pop() || 'file';
    const dest = decodeURIComponent(new File(dir, name).uri.replace('file://', ''));
    await transfers.enqueue(newTransferId(), host.id, address, p, dest);
  }
}
