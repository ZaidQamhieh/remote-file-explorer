import type { TransferRecord } from '../../core/native';
import { basenameOf } from '../explorer/paths';

export const isUpload = (r: TransferRecord) => r.direction === 'UPLOAD';

/** The file name shown for a transfer: the target's name on the host for both directions. */
export const transferName = (r: TransferRecord) => basenameOf(r.remotePath) || r.remotePath;

/** 0..1, or null while the size is unknown. */
export function transferProgress(r: TransferRecord): number | null {
  if (r.state === 'DONE') return 1;
  if (r.total <= 0) return null;
  return Math.min(1, Math.max(0, r.received / r.total));
}

export const isActive = (r: TransferRecord) => r.state === 'RUNNING' || r.state === 'QUEUED';
export const isFinished = (r: TransferRecord) => r.state === 'DONE' || r.state === 'CANCELLED';

/** Plain-language reason for a failed transfer, from the engine's error text (an agent API code or an ERR_ tag). */
export function transferErrorMessage(error: string | null): string {
  if (!error) return '';
  const code = error.split(':')[0].trim();
  switch (code) {
    case 'CONFLICT':
      return 'A file with this name already exists on the computer.';
    case 'FORBIDDEN':
    case 'READ_ONLY':
      return 'This device is not allowed to upload here.';
    case 'HASH_MISMATCH':
    case 'CHUNK_HASH_MISMATCH':
      return 'The file changed or was damaged in transit. Try again.';
    case 'PAYLOAD_TOO_LARGE':
      return 'The file is too large for this computer to accept.';
    case 'RESOURCE_LIMIT':
      return 'The computer has too many uploads open. Wait for one to finish.';
    case 'NOT_FOUND':
      return 'The computer no longer has this upload. Try again.';
    case 'ERR_CERT_PIN_MISMATCH':
      return 'The computer’s identity changed. Check it in Devices.';
    case 'ERR_CONNECTION':
      return 'Could not reach the computer.';
    default:
      return error.startsWith('source file is missing') ? 'The file to upload is no longer on this phone.' : error;
  }
}

/** Newest first. Ids are a kind letter then the enqueue time in base 36, so the time orders them across kinds. */
export function newestFirst(a: TransferRecord, b: TransferRecord): number {
  const at = parseInt(a.id.slice(1, 9), 36);
  const bt = parseInt(b.id.slice(1, 9), 36);
  if (Number.isNaN(at) || Number.isNaN(bt)) return b.id.localeCompare(a.id);
  return bt - at || b.id.localeCompare(a.id);
}

export type TransferGroups = { active: TransferRecord[]; failed: TransferRecord[]; finished: TransferRecord[] };

export function groupTransfers(all: TransferRecord[]): TransferGroups {
  const sorted = [...all].sort(newestFirst);
  return {
    active: sorted.filter((r) => isActive(r) || r.state === 'PAUSED'),
    failed: sorted.filter((r) => r.state === 'FAILED'),
    finished: sorted.filter(isFinished),
  };
}
