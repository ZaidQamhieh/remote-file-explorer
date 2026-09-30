import type { TransferRecord } from '../../core/native';
import { groupTransfers, savedWhere, isActive, isFinished, isUpload, transferErrorMessage, transferName, transferProgress } from './transferLogic';

const rec = (o: Partial<TransferRecord> = {}): TransferRecord => ({ id: 'x', hostId: 'h', address: 'a', remotePath: '/docs/a.txt', destPath: '/tmp/a.txt', state: 'RUNNING', received: 0, total: -1, error: null, ...o });

describe('transfer logic', () => {
  it('names a transfer by its host-side file', () => {
    expect(transferName(rec())).toBe('a.txt');
    expect(transferName(rec({ remotePath: 'C:\\x\\b.bin' }))).toBe('b.bin');
  });

  it('treats records without a direction as downloads', () => {
    expect(isUpload(rec())).toBe(false);
    expect(isUpload(rec({ direction: 'UPLOAD' }))).toBe(true);
  });

  it('reports progress only when the size is known', () => {
    expect(transferProgress(rec())).toBeNull();
    expect(transferProgress(rec({ received: 25, total: 100 }))).toBe(0.25);
    expect(transferProgress(rec({ received: 150, total: 100 }))).toBe(1);
    expect(transferProgress(rec({ state: 'DONE' }))).toBe(1);
  });

  it('classifies states', () => {
    expect(isActive(rec({ state: 'QUEUED' }))).toBe(true);
    expect(isActive(rec({ state: 'PAUSED' }))).toBe(false);
    expect(isFinished(rec({ state: 'DONE' }))).toBe(true);
    expect(isFinished(rec({ state: 'FAILED' }))).toBe(false);
  });

  it('explains agent and engine errors', () => {
    expect(transferErrorMessage('CONFLICT')).toMatch(/already exists/);
    expect(transferErrorMessage('READ_ONLY')).toMatch(/not allowed/);
    expect(transferErrorMessage('ERR_CONNECTION: timeout')).toMatch(/Could not reach/);
    expect(transferErrorMessage('source file is missing')).toMatch(/no longer on this phone/);
    expect(transferErrorMessage('HTTP 500')).toBe('HTTP 500');
    expect(transferErrorMessage(null)).toBe('');
  });
});

describe('transfer grouping', () => {
  it('orders newest first across kinds and groups by state', () => {
    const all = [
      rec({ id: 'd0000000a', state: 'DONE' }),
      rec({ id: 'u0000000c', state: 'RUNNING' }),
      rec({ id: 'd0000000b', state: 'FAILED' }),
      rec({ id: 'u0000000d', state: 'PAUSED' }),
      rec({ id: 'd0000000e', state: 'CANCELLED' }),
    ];
    const g = groupTransfers(all);
    expect(g.active.map((r) => r.id)).toEqual(['u0000000d', 'u0000000c']);
    expect(g.failed.map((r) => r.id)).toEqual(['d0000000b']);
    expect(g.finished.map((r) => r.id)).toEqual(['d0000000e', 'd0000000a']);
  });
});

describe('saved location', () => {
  it('says where a finished transfer went', () => {
    expect(savedWhere(rec({ direction: 'UPLOAD' }))).toBe('Uploaded');
    expect(savedWhere(rec({ publicUri: 'content://media/external/downloads/1' }))).toBe('Saved to Downloads');
    expect(savedWhere(rec())).toBe('Saved in app storage');
  });
});
