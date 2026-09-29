// Response models ported from app/lib/core/models/*.dart. Parsers are total:
// missing fields take the same defaults the Dart fromJson used.

type Json = Record<string, unknown>;

const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined);
const num = (v: unknown): number | undefined => (typeof v === 'number' ? v : undefined);
const bool = (v: unknown, d: boolean): boolean => (typeof v === 'boolean' ? v : d);
const nonEmpty = (v: unknown): string | undefined => {
  const s = str(v);
  return s === undefined || s.length === 0 ? undefined : s;
};

export type Health = {
  status: string;
  name: string;
  version: string;
  os: string;
  readOnly: boolean;
  address?: string;
  tailscaleAddress?: string;
  macAddress?: string;
};

export const parseHealth = (j: Json): Health => ({
  status: str(j.status) ?? 'unknown',
  name: str(j.name) ?? '',
  version: str(j.version) ?? '',
  os: str(j.os) ?? '',
  readOnly: bool(j.readOnly, false),
  address: nonEmpty(j.address),
  tailscaleAddress: nonEmpty(j.tailscaleAddress),
  macAddress: nonEmpty(j.macAddress),
});

export type PairResponse = {
  deviceToken: string;
  deviceId: string;
  agentName: string;
  certFingerprint?: string;
  address?: string;
  tailscaleAddress?: string;
};

export const parsePairResponse = (j: Json): PairResponse => ({
  deviceToken: str(j.deviceToken) ?? '',
  deviceId: str(j.deviceId) ?? '',
  agentName: str(j.agentName) ?? '',
  certFingerprint: str(j.certFingerprint),
  address: nonEmpty(j.address),
  tailscaleAddress: nonEmpty(j.tailscaleAddress),
});

export type Drive = { path: string; label?: string; totalBytes?: number; freeBytes?: number; isOS: boolean };

export const parseDrive = (j: Json): Drive => ({
  path: str(j.path) ?? '',
  label: str(j.label),
  totalBytes: num(j.totalBytes),
  freeBytes: num(j.freeBytes),
  isOS: bool(j.isOS, false),
});

export type Entry = {
  name: string;
  path: string;
  isDir: boolean;
  size?: number;
  mimeType?: string;
  mode?: string;
  modified?: string;
  created?: string;
  isSymlink: boolean;
  symlinkTarget?: string;
};

export const parseEntry = (j: Json): Entry => ({
  name: str(j.name) ?? '',
  path: str(j.path) ?? '',
  isDir: bool(j.isDir, false),
  size: num(j.size),
  mimeType: str(j.mimeType),
  mode: str(j.mode),
  modified: str(j.modified),
  created: str(j.created),
  isSymlink: bool(j.isSymlink, false),
  symlinkTarget: str(j.symlinkTarget),
});

export type Listing = { path: string; entries: Entry[]; nextCursor?: string };

export const parseListing = (j: Json): Listing => ({
  path: str(j.path) ?? '',
  entries: Array.isArray(j.entries) ? (j.entries as Json[]).map(parseEntry) : [],
  nextCursor: str(j.nextCursor),
});

export type AgentStatus = {
  agentName: string;
  roots: string[];
  readOnly: boolean;
  isAdmin: boolean;
  effectiveScope: 'global' | 'device';
  /** True when the device's jail is outside all host roots: no filesystem access at all. */
  accessDenied: boolean;
};

export const parseStatus = (j: Json): AgentStatus => ({
  agentName: str(j.agentName) ?? '',
  roots: Array.isArray(j.roots) ? (j.roots as unknown[]).filter((x): x is string => typeof x === 'string') : [],
  readOnly: bool(j.readOnly, false),
  isAdmin: bool(j.isAdmin, false),
  effectiveScope: j.effectiveScope === 'device' ? 'device' : 'global',
  accessDenied: bool(j.accessDenied, false),
});

export type BatchItemResult = { path: string; ok: boolean; errorCode?: string; errorMessage?: string };
export type BatchResult = { results: BatchItemResult[]; failed: BatchItemResult[] };

export const parseBatchResult = (j: Json): BatchResult => {
  const results = (Array.isArray(j.results) ? (j.results as Json[]) : []).map((r): BatchItemResult => {
    const err = typeof r.error === 'object' && r.error !== null ? (r.error as Json) : undefined;
    return { path: str(r.path) ?? '', ok: r.ok === true, errorCode: err ? str(err.code) : undefined, errorMessage: err ? str(err.message) : undefined };
  });
  return { results, failed: results.filter((r) => !r.ok) };
};

export type TrashEntry = { id: string; name: string; originalPath: string; deletedAt?: string; size?: number; isDir: boolean };

export const parseTrashEntry = (j: Json): TrashEntry => ({
  id: str(j.id) ?? '',
  name: str(j.name) ?? '',
  originalPath: str(j.originalPath) ?? '',
  deletedAt: str(j.deletedAt),
  size: num(j.size),
  isDir: bool(j.isDir, false),
});

export type ArchiveEntry = { path: string; size: number; modified?: string; isDir: boolean };

export const parseArchiveEntry = (j: Json): ArchiveEntry => ({
  path: str(j.path) ?? '',
  size: num(j.size) ?? 0,
  modified: str(j.modified),
  isDir: bool(j.isDir, false),
});

export type SearchResult = { entries: Entry[]; truncated: boolean; timeBudgetHit: boolean };

const flagSet = (headers: Record<string, string>, name: string) =>
  Object.entries(headers).some(([k, v]) => k.toLowerCase() === name && v.trim() === '1');

/** Search and recent bodies are bare arrays; truncation state arrives in `X-Search-*` response headers (case-insensitive). */
export const parseSearchResult = (body: unknown, headers: Record<string, string>): SearchResult => ({
  entries: Array.isArray(body) ? (body as Json[]).map(parseEntry) : [],
  truncated: flagSet(headers, 'x-search-truncated'),
  timeBudgetHit: flagSet(headers, 'x-search-time-budget'),
});

/** A one-time share link. `token` and `url` exist only in the mint response; list entries carry `tokenHash` and `path`. */
export type ShareLink = { token: string; tokenHash: string; path: string; expiresAt: number; url: string };

export const parseShareLink = (j: Json): ShareLink => ({
  token: str(j.token) ?? '',
  tokenHash: str(j.tokenHash) ?? '',
  path: str(j.path) ?? '',
  expiresAt: num(j.expiresAt) ?? 0,
  url: str(j.url) ?? '',
});
