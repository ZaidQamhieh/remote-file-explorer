/** Which quick actions of a host card are usable right now. Open stays available offline (cached browsing). */
export function hostCardActions({ online, checking }: { online: boolean; checking: boolean }) {
  return {
    open: !checking,
    search: online && !checking,
    apps: online && !checking,
    transfers: true,
  };
}
