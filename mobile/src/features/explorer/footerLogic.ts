import { can, type FileCapability } from '../../core/api/models';

export type FooterAction = { key: 'paste' | 'upload' | 'new'; primary: boolean };

/**
 * Buttons of the Files footer, in order, gated by the same predicates as the create menu. Primary is Paste while the
 * clipboard holds items from this host, else Upload; "New" (opens the create menu) needs modify. When Paste is primary
 * and the device may upload but not modify, Upload stays reachable as the secondary button.
 */
export function footerActions({ caps, showPaste }: { caps: Record<FileCapability, boolean> | undefined; showPaste: boolean }): FooterAction[] {
  const upload = can(caps, 'upload');
  const modify = can(caps, 'modify');
  const out: FooterAction[] = [];
  if (showPaste) out.push({ key: 'paste', primary: true });
  else if (upload) out.push({ key: 'upload', primary: true });
  if (modify) out.push({ key: 'new', primary: out.length === 0 });
  else if (showPaste && upload) out.push({ key: 'upload', primary: false });
  return out;
}

/** Height of the footer row (52 dp button + 2 x 8 dp padding); list content needs this plus 8 dp so the last row is never covered. */
export const FOOTER_HEIGHT = 68;
export const FOOTER_LIST_PADDING = FOOTER_HEIGHT + 8;
