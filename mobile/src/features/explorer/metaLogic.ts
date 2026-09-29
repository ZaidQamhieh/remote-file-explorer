// Pure helpers behind the entry details sheet: archive detection and POSIX permission bits.

/** Whether the agent's `/fs/extract` can unpack [name] (`.zip`, `.tar.gz`, `.tgz`; case-insensitive). */
export function isExtractableArchive(name: string): boolean {
  const lower = name.toLowerCase();
  return lower.endsWith('.zip') || lower.endsWith('.tar.gz') || lower.endsWith('.tgz');
}

/** Nine rwx flags (owner, group, other) from a listing mode such as `-rwxr-xr--`; anything shorter reads as no access. */
export function parseModeBits(mode: string | undefined): boolean[] {
  const perms = mode && mode.length >= 10 ? mode.slice(1, 10) : '---------';
  return Array.from({ length: 9 }, (_, i) => perms[i] !== '-');
}

/** `0754` from nine flags. */
export function bitsToOctal(bits: boolean[]): string {
  let v = 0;
  for (let i = 0; i < 9; i++) if (bits[i]) v |= 1 << (8 - i);
  return v.toString(8).padStart(4, '0');
}

/** `rwxr-xr--` from nine flags. */
export function bitsToSymbolic(bits: boolean[]): string {
  const chars = 'rwxrwxrwx';
  return Array.from({ length: 9 }, (_, i) => (bits[i] ? chars[i] : '-')).join('');
}
