import { File as FileIcon, FileArchive, FileText, Folder, Image as ImageIcon, Music, Video, type LucideIcon } from 'lucide-react-native';

import type { Entry } from '../../core/api/models';
import { iconKindFor, roleOf } from '../../core/entryCategory';
import { roleTint, useRoles, useScheme } from '../../design/theme';

const ICONS: Record<ReturnType<typeof iconKindFor>['icon'], LucideIcon> = { folder: Folder, image: ImageIcon, video: Video, music: Music, fileArchive: FileArchive, fileText: FileText, file: FileIcon };

/** File-type glyph + role colour shared by list tiles, grid cells and search results (EntryLeading). */
export function EntryLeading({ entry, size = 24 }: { entry: Pick<Entry, 'isDir' | 'mimeType'>; size?: number }) {
  const c = useScheme();
  const roles = useRoles();
  const role = roleOf(entry);
  const Icon = ICONS[iconKindFor(entry).icon];
  return <Icon size={size} color={role ? roles[role] : c.onSurfaceVariant} />;
}

/** Tonal chip behind the glyph: the entry's role colour over the surface, neutral for unknown types. */
export function useIconChipBg(entry: Pick<Entry, 'isDir' | 'mimeType'> & { name?: string }): string {
  const c = useScheme();
  const roles = useRoles();
  const role = roleOf(entry);
  return role ? roleTint(roles[role], c) : c.surfaceContainerHighest;
}
