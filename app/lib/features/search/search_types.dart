import 'package:flutter/material.dart';

import '../../core/l10n_ext.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Selectable entry-type categories for the search filter chips, mapped to
/// the server's `types` query parameter values.
enum SearchCategory {
  folder(LucideIcons.folder, 'folder'),
  image(LucideIcons.image, 'image'),
  video(LucideIcons.video, 'video'),
  audio(LucideIcons.music, 'audio'),
  document(LucideIcons.fileText, 'document'),
  archive(LucideIcons.fileArchive, 'archive'),
  other(LucideIcons.file, 'other');

  const SearchCategory(this.icon, this.apiValue);

  final IconData icon;
  final String apiValue;

  String localizedLabel(BuildContext context) => switch (this) {
    folder => context.l10n.searchCategoryFolders,
    image => context.l10n.searchCategoryImages,
    video => context.l10n.searchCategoryVideos,
    audio => context.l10n.searchCategoryAudio,
    document => context.l10n.searchCategoryDocs,
    archive => context.l10n.searchCategoryArchives,
    other => context.l10n.searchCategoryOther,
  };
}

/// Minimum-size filter presets, mapped to the server's `minSize` (bytes).
enum SizePreset {
  any(null),
  mb1(1024 * 1024),
  mb10(10 * 1024 * 1024),
  mb100(100 * 1024 * 1024),
  gb1(1024 * 1024 * 1024);

  const SizePreset(this.minBytes);

  final int? minBytes;

  String localizedLabel(BuildContext context) => switch (this) {
    any => context.l10n.sizePresetAny,
    mb1 => context.l10n.sizePresetMb1,
    mb10 => context.l10n.sizePresetMb10,
    mb100 => context.l10n.sizePresetMb100,
    gb1 => context.l10n.sizePresetGb1,
  };
}

/// Modified-date filter presets. [resolve] computes the `modifiedAfter`
/// timestamp at query time (relative to "now").
enum DatePreset {
  any(null),
  last24h(Duration(hours: 24)),
  last7d(Duration(days: 7)),
  last30d(Duration(days: 30)),
  thisYear(null);

  const DatePreset(this.lookback);

  final Duration? lookback;

  String localizedLabel(BuildContext context) => switch (this) {
    any => context.l10n.datePresetAny,
    last24h => context.l10n.datePresetLast24h,
    last7d => context.l10n.datePresetLast7d,
    last30d => context.l10n.datePresetLast30d,
    thisYear => context.l10n.datePresetThisYear,
  };

  /// Computes the `modifiedAfter` bound for this preset, or `null` for
  /// [DatePreset.any].
  DateTime? resolve(DateTime now) {
    if (this == DatePreset.any) return null;
    if (this == DatePreset.thisYear) return DateTime(now.year, 1, 1);
    return now.subtract(lookback!);
  }
}
