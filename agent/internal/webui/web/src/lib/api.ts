// Typed client for the real agent REST API (protocol/openapi.yaml — the
// contract's source of truth). Same-origin (this bundle is served by the
// agent itself via go:embed), so requests are relative to "/v1".
import { getDevicePublicKeyB64, signNonce } from './deviceIdentity';

const TOKEN_KEY = 'rfe_device_token';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}
export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

export class ApiError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

async function request<T>(
  method: string,
  path: string,
  body?: unknown,
  opts: { auth?: boolean } = { auth: true },
): Promise<T> {
  const headers: Record<string, string> = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (opts.auth !== false) {
    const token = getToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;
  }
  const res = await fetch(`/v1${path}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return undefined as T;
  const isJson = res.headers.get('content-type')?.includes('application/json');
  const data = isJson ? await res.json() : undefined;
  if (!res.ok) {
    throw new ApiError(res.status, data?.code ?? 'UNKNOWN', data?.message ?? res.statusText);
  }
  return data as T;
}

const get = <T>(path: string) => request<T>('GET', path);
const post = <T>(path: string, body?: unknown) => request<T>('POST', path, body);
const patch = <T>(path: string, body?: unknown) => request<T>('PATCH', path, body);
const put = <T>(path: string, body?: unknown) => request<T>('PUT', path, body);
const del = <T>(path: string) => request<T>('DELETE', path);

// Chunk uploads are raw octet-stream bodies with a custom header, not JSON —
// bypasses the JSON-only `request` helper above.
async function rawPut(path: string, body: ArrayBuffer, headers: Record<string, string>): Promise<void> {
  const token = getToken();
  const res = await fetch(`/v1${path}`, {
    method: 'PUT',
    headers: { ...headers, ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body,
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new ApiError(res.status, data?.code ?? 'UNKNOWN', data?.message ?? res.statusText);
  }
}

async function sha256Hex(data: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

const UPLOAD_CHUNK_SIZE = 4 * 1024 * 1024; // 4MiB, under the agent's 32MiB cap

/** Drives the full resumable-upload contract: open session, hash + PUT each
 * chunk, then complete. Whole file is read into memory to compute the
 * whole-file SHA-256 upfront (per POST /transfers's required `sha256` field)
 * — fine for the LAN-transfer file sizes this tool targets. */
async function uploadFileImpl(path: string, file: File, onProgress?: (fraction: number) => void): Promise<void> {
  const buf = await file.arrayBuffer();
  const wholeHash = await sha256Hex(buf);
  const session = await post<UploadSession>('/transfers', {
    path,
    size: file.size,
    sha256: wholeHash,
    chunkSize: UPLOAD_CHUNK_SIZE,
  });
  const totalChunks = session.totalChunks;
  for (let n = 0; n < totalChunks; n++) {
    const start = n * UPLOAD_CHUNK_SIZE;
    const chunk = buf.slice(start, Math.min(start + UPLOAD_CHUNK_SIZE, buf.byteLength));
    const chunkHash = await sha256Hex(chunk);
    await rawPut(`/transfers/${session.id}/chunks/${n}`, chunk, { 'X-Chunk-Sha256': chunkHash });
    onProgress?.((n + 1) / totalChunks);
  }
  await post(`/transfers/${session.id}/complete`);
}

// ---------- device identity / proof-of-possession ----------

async function proofFields() {
  const challenge = await post<{ nonce: string }>('/auth/challenge', undefined);
  const devicePublicKey = await getDevicePublicKeyB64();
  const signature = await signNonce(challenge.nonce);
  return { devicePublicKey, nonce: challenge.nonce, signature };
}

// ---------- schemas (protocol/openapi.yaml) ----------

export interface Health {
  status: string;
  name?: string;
  version?: string;
  os?: 'windows' | 'linux';
  readOnly?: boolean;
  address?: string;
  tailscaleAddress?: string;
  macAddress?: string;
}
export interface AgentStatus {
  version: string;
  uptimeSeconds: number;
  platform: string;
  freeBytes: number;
  totalBytes: number;
}
export interface Metrics {
  rxBytes: number;
  txBytes: number;
  cpuPercent: number;
  ramPercent: number;
  tsMs: number;
}
export interface PairResponse {
  deviceToken: string;
  deviceId: string;
  agentName: string;
  certFingerprint: string;
  address?: string;
  tailscaleAddress?: string;
}
export interface Device {
  id: string;
  label: string;
  created: number;
  lastSeen: number;
  revoked: boolean;
  current: boolean;
  lastAddress?: string;
  lastVersion?: string;
  jailRoot?: string;
  readOnly?: boolean;
  viaLogin?: boolean;
}
export interface Entry {
  name: string;
  path: string;
  isDir: boolean;
  size: number;
  mimeType?: string;
  mode?: string;
  modified?: string;
  created?: string;
  isSymlink?: boolean;
  symlinkTarget?: string;
}
export interface Listing {
  path: string;
  entries: Entry[];
  nextCursor?: string | null;
}
export interface TrashEntry {
  id: string;
  name: string;
  originalPath: string;
  deletedAt: string;
  size: number;
  isDir: boolean;
}
export interface ShareLink {
  token: string;
  tokenHash: string;
  expiresAt: number;
  url: string;
}
export interface ShareLinkSummary {
  tokenHash: string;
  path: string;
  expiresAt: number;
}
export interface AgentSettings {
  readOnly: boolean;
  roots: string[];
  agentName: string;
  allowSharing: boolean;
  photoBackupRoot: string;
}
export interface BandwidthSettings {
  maxUploadBytesPerSec: number;
  maxDownloadBytesPerSec: number;
}
export interface TransfersList {
  total: number;
  counts: Record<string, number>;
  transfers: TransferRow[];
  activeNow: number;
  devices: { id: string; label: string; username: string }[];
  users: string[];
}
export interface TransferRow {
  id: string;
  name: string;
  path: string;
  totalSize: number;
  receivedBytes: number;
  progress: number;
  status: 'open' | 'completed' | 'failed';
  deviceId: string;
  updatedAt: number;
}
export interface UserAccount {
  username: string;
  created: number;
}
export interface LogLine {
  ts: string;
  message: string;
}
export interface UploadSession {
  id: string;
  path: string;
  size: number;
  chunkSize: number;
  totalChunks: number;
  receivedChunks: number[];
  status: 'open' | 'completed' | 'failed';
}
export interface Drive {
  path: string;
  label: string;
  totalBytes: number;
  freeBytes: number;
  isOS: boolean;
}

// ---------- auth flows (unauthenticated) ----------

export const api = {
  health: () => get<Health>('/health'),
  status: () => get<AgentStatus>('/status'),
  metrics: () => get<Metrics>('/metrics'),

  async login(username: string, password: string, deviceLabel = 'Browser'): Promise<PairResponse> {
    const proof = await proofFields();
    return post<PairResponse>('/login', { username, password, deviceLabel, ...proof });
  },
  async register(
    pairingCode: string,
    username: string,
    password: string,
    deviceLabel = 'Browser',
  ): Promise<PairResponse> {
    const proof = await proofFields();
    return post<PairResponse>('/register', { pairingCode, username, password, deviceLabel, ...proof });
  },
  async pair(pairingCode: string, deviceLabel = 'Browser'): Promise<PairResponse> {
    const proof = await proofFields();
    return post<PairResponse>('/pair', { pairingCode, deviceLabel, ...proof });
  },

  // devices
  listDevices: () => get<Device[]>('/devices'),
  patchDevice: (id: string, body: Partial<Pick<Device, 'jailRoot' | 'readOnly'>> & { revoked?: boolean }) =>
    patch<Device>(`/devices/${id}`, body),
  deleteDevice: (id: string) => del<void>(`/devices/${id}`),
  generatePairingCode: async () => {
    const res = await post<{ pairingCode: string; expiresInSeconds: number; qrPngBase64?: string }>('/pairing/generate');
    return {
      code: res.pairingCode,
      expiresAt: Math.floor(Date.now() / 1000) + res.expiresInSeconds,
      qrPngBase64: res.qrPngBase64,
    };
  },

  // users
  listUsers: () => get<UserAccount[]>('/users'),
  deleteUser: (username: string) => del<void>(`/users/${username}`),

  // logs
  listLogs: () => get<LogLine[]>('/logs'),

  // transfers
  listTransfers: (params?: { device?: string; user?: string }) => {
    const qs = new URLSearchParams(params as Record<string, string>).toString();
    return get<TransfersList>(`/transfers/list${qs ? `?${qs}` : ''}`);
  },
  deleteTransfer: (id: string) => del<void>(`/transfers/${id}`),

  // resumable chunked upload (see uploadFile below for the driver)
  openUploadSession: (body: { path: string; size: number; sha256: string; chunkSize: number; overwrite?: boolean }) =>
    post<UploadSession>('/transfers', body),
  uploadChunk: (id: string, n: number, chunk: ArrayBuffer, chunkSha256: string) =>
    rawPut(`/transfers/${id}/chunks/${n}`, chunk, { 'X-Chunk-Sha256': chunkSha256 }),
  completeUpload: (id: string) => post<Entry & { sha256: string; verified: boolean }>(`/transfers/${id}/complete`),
  uploadFile: (path: string, file: File, onProgress?: (fraction: number) => void) =>
    uploadFileImpl(path, file, onProgress),

  // settings
  getSettings: () => get<AgentSettings>('/settings'),
  patchSettings: (body: Partial<AgentSettings>) => patch<AgentSettings>('/settings', body),
  getBandwidth: () => get<BandwidthSettings>('/settings/bandwidth'),
  putBandwidth: (body: BandwidthSettings) => put<BandwidthSettings>('/settings/bandwidth', body),

  // filesystem
  listDir: (path: string, cursor?: string) => {
    const qs = new URLSearchParams({ path, ...(cursor ? { cursor } : {}) }).toString();
    return get<Listing>(`/fs?${qs}`);
  },
  listDrives: () => get<Drive[]>('/system/drives'),
  mkdir: (path: string) => post<void>('/fs/folder', { path }),
  rename: (path: string, newName: string) => patch<void>('/fs/rename', { path, newName }),
  recent: () => get<Entry[]>('/fs/recent'),
  search: (query: string, path?: string) => {
    const qs = new URLSearchParams({ q: query, ...(path ? { path } : {}) }).toString();
    return get<Entry[]>(`/search?${qs}`);
  },

  // trash
  listTrash: () => get<TrashEntry[]>('/trash'),
  restoreTrash: (id: string) => post<void>('/trash/restore', { id }),
  deleteTrashForever: (id: string) => del<void>(`/trash?id=${encodeURIComponent(id)}`),

  // shares
  listShares: () => get<ShareLinkSummary[]>('/share'),
  mintShare: (path: string, ttlSeconds?: number) =>
    post<ShareLink>('/share/mint', { path, ...(ttlSeconds ? { ttlSeconds } : {}) }),
  revokeShare: (tokenHash: string) => del<void>(`/share/${tokenHash}`),

  // agent lifecycle
  restartAgent: () => post<void>('/agent/restart'),
  wakeOnLan: (macAddress: string) => post<void>('/wol', { macAddress }),
};

export function contentUrl(path: string): string {
  return `/v1/content?path=${encodeURIComponent(path)}`;
}
export function thumbUrl(path: string): string {
  return `/v1/thumb?path=${encodeURIComponent(path)}`;
}
