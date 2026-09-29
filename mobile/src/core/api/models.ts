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
