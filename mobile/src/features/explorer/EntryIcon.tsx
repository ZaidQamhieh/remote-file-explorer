import { File as FileIcon, FileArchive, FileText, Folder, Image as ImageIcon, Music, Video, type LucideIcon } from 'lucide-react-native';

import type { Entry } from '../../core/api/models';
import { iconKindFor } from '../../core/entryCategory';
import { useScheme } from '../../design/theme';

const ICONS: Record<ReturnType<typeof iconKindFor>['icon'], LucideIcon> = { folder: Folder, image: ImageIcon, video: Video, music: Music, fileArchive: FileArchive, fileText: FileText, file: FileIcon };

/** File-type glyph + tint shared by list tiles, grid cells and search results (EntryLeading). */
export function EntryLeading({ entry, size = 24 }: { entry: Pick<Entry, 'isDir' | 'mimeType'>; size?: number }) {
  const c = useScheme();
  const k = iconKindFor(entry);
  const Icon = ICONS[k.icon];
  return <Icon size={size} color={k.color ?? c.onSurfaceVariant} />;
}

/** Tonal chip background: per-type tint in dark, primary/neutral in light (figmaIconBg rules). */
export function useIconChipBg(entry: Pick<Entry, 'isDir' | 'mimeType'>): string {
  const c = useScheme();
  if (c.dark) return iconKindFor(entry).bg ?? '#191C24';
  return entry.isDir ? `${c.primary}29` : c.surfaceContainerHighest;
}
