import { bitsToOctal, bitsToSymbolic, isExtractableArchive, parseModeBits } from './metaLogic';
import { parentDirOf } from './paths';

describe('isExtractableArchive', () => {
  it('matches the formats the agent extracts, case-insensitively', () => {
    for (const n of ['a.zip', 'A.ZIP', 'x.tar.gz', 'x.TGZ']) expect(isExtractableArchive(n)).toBe(true);
    for (const n of ['a.tar', 'a.rar', 'a.gz', 'zip', 'a.zip.txt']) expect(isExtractableArchive(n)).toBe(false);
  });
});

describe('permission bits', () => {
  it('round-trips a listing mode through octal and symbolic forms', () => {
    const bits = parseModeBits('-rwxr-xr--');
    expect(bitsToOctal(bits)).toBe('0754');
    expect(bitsToSymbolic(bits)).toBe('rwxr-xr--');
  });
  it('reads a missing or short mode as no access', () => {
    expect(bitsToOctal(parseModeBits(undefined))).toBe('0000');
    expect(bitsToOctal(parseModeBits('rwx'))).toBe('0000');
  });
  it('encodes all bits', () => {
    expect(bitsToOctal(parseModeBits('-rwxrwxrwx'))).toBe('0777');
    expect(bitsToOctal(parseModeBits('drw-r-----'))).toBe('0640');
  });
});

describe('parentDirOf', () => {
  it('keeps the separator style and stops at the root', () => {
    expect(parentDirOf('/a/b.txt')).toBe('/a');
    expect(parentDirOf('/a')).toBe('/');
    expect(parentDirOf('C:\\a\\b.txt')).toBe('C:\\a');
    expect(parentDirOf('/')).toBe('/');
  });
});
