import { hostCardActions } from './hostCardLogic';

describe('hostCardActions', () => {
  it('enables everything when online', () => {
    expect(hostCardActions({ online: true, checking: false })).toEqual({ open: true, search: true, apps: true, transfers: true });
  });

  it('keeps Open and Transfers offline but disables Search and Apps', () => {
    expect(hostCardActions({ online: false, checking: false })).toEqual({ open: true, search: false, apps: false, transfers: true });
  });

  it('disables Open, Search and Apps while checking', () => {
    expect(hostCardActions({ online: true, checking: true })).toEqual({ open: false, search: false, apps: false, transfers: true });
  });
});
