import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/grouped_card.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/sheet_chrome.dart';
import '../settings/widgets/settings_section.dart';
import 'photo_backup_controller.dart';
import 'photo_backup_prefs.dart';
import 'package:photo_manager/photo_manager.dart';

/// Settings + manual trigger for one-way photo backup (DCIM → a PC).
class PhotoBackupScreen extends ConsumerStatefulWidget {
  const PhotoBackupScreen({super.key});

  @override
  ConsumerState<PhotoBackupScreen> createState() => _PhotoBackupScreenState();
}

class _PhotoBackupScreenState extends ConsumerState<PhotoBackupScreen> {
  PhotoBackupStore? _store;
  PhotoBackupPrefs _prefs = const PhotoBackupPrefs();
  List<Host> _hosts = const [];
  int _doneCount = 0;
  bool _loading = true;
  bool _running = false;
  final _nicknameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await PhotoBackupStore.open();
    final hostStore = await ref.read(hostStoreProvider.future);
    if (!mounted) return;
    setState(() {
      _store = store;
      _prefs = store.load();
      _nicknameCtrl.text = _prefs.deviceName ?? '';
      _hosts = hostStore.listHosts();
      _doneCount = store.doneIds().length;
      _loading = false;
    });
  }

  Future<void> _update(PhotoBackupPrefs next) async {
    setState(() => _prefs = next);
    await _store?.save(next);
  }

  Future<void> _backupNow() async {
    setState(() => _running = true);
    try {
      final result = await ref.read(photoBackupControllerProvider).backupNow();
      if (!mounted) return;
      switch (result.outcome) {
        case PhotoBackupOutcome.enqueued:
          showSuccess(context, context.l10n.backingUpPhotos(result.enqueued));
        case PhotoBackupOutcome.upToDate:
          showInfo(context, context.l10n.alreadyUpToDate);
        case PhotoBackupOutcome.notConfigured:
          showError(context, context.l10n.pickPcFirst);
        case PhotoBackupOutcome.permissionDenied:
          showError(context, context.l10n.photoAccessDenied);
        case PhotoBackupOutcome.skipped:
          showInfo(context, result.message ?? 'Skipped');
        case PhotoBackupOutcome.disabled:
          showInfo(context, context.l10n.enableBackupFirst);
        case PhotoBackupOutcome.serverNotConfigured:
          showError(context, context.l10n.serverDestNotConfigured);
      }
      // Refresh the backed-up count.
      final store = await PhotoBackupStore.open();
      if (mounted) setState(() => _doneCount = store.doneIds().length);
    } catch (e) {
      if (mounted) {
        showError(context, context.l10n.backupFailed(humanizeError(e)));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.photoBackupTitle)),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                children: _buildItems(context),
              ),
    );
  }

  /// Card-grouped sections matching the mockup's `photo-backup` screen shape
  /// (top standalone toggle card, then "Destination"/"Status" section
  /// cards). Two real differences from the mockup, kept rather than
  /// fabricated:
  /// - The mockup shows a literal remote path under Destination
  ///   ("/Photos/Mobile Backup/Zaid's Phone"); the real client never learns
  ///   the remote path — it's decided server-side (see [PhotoBackupPrefs]'s
  ///   doc comment) — so this shows the host label + device nickname
  ///   instead of a fabricated path.
  /// - The mockup has a single "Include videos" toggle; the real app has a
  ///   richer per-album picker (`_pickAlbums`) instead of a video/photo
  ///   split, which is kept since it's strictly more capable.
  /// - The mockup's Status card shows an "X of Y (97%)" progress bar; the
  ///   real store only tracks the backed-up count, not a total pending
  ///   count, so no true percentage is available without new tracking —
  ///   shown as a plain count instead of a fabricated bar.
  List<Widget> _buildItems(BuildContext context) {
    // Master switch off => every other control is disabled (nothing backs up).
    final on = _prefs.enabled;
    return [
      GroupedCard(
        padded: false,
        children: [
          _Row(
            title: context.l10n.enablePhotoBackup,
            subtitle: context.l10n.photoBackupSubtitle,
            trailing: _Switch(value: _prefs.enabled),
            onTap: () => _update(_prefs.copyWith(enabled: !_prefs.enabled)),
          ),
        ],
      ),
      const SizedBox(height: Spacing.md),
      SettingsSection(
        title: 'Destination',
        padded: false,
        children: [
          _Row(
            enabled: on,
            icon: LucideIcons.computer,
            title: context.l10n.backUpTo,
            subtitle: _hostLabel(context),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onTap: (!on || _hosts.isEmpty) ? null : _pickHost,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              Spacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.deviceNicknameLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: Spacing.xs),
                ShadInput(
                  controller: _nicknameCtrl,
                  enabled: on,
                  placeholder: Text(context.l10n.deviceNicknameHint),
                  onChanged:
                      (v) => _update(_prefs.copyWith(deviceName: v.trim())),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  context.l10n.deviceNicknameHelper,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _Row(
            enabled: on,
            icon: LucideIcons.images,
            title: context.l10n.albumsToBackUp,
            subtitle: _albumsLabel(context),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onTap: on ? _pickAlbums : null,
          ),
          const Divider(height: 1),
          _Row(
            enabled: on,
            title: context.l10n.onlyOnWifi,
            trailing: _Switch(value: _prefs.wifiOnly),
            onTap:
                on
                    ? () => _update(_prefs.copyWith(wifiOnly: !_prefs.wifiOnly))
                    : null,
          ),
          _Row(
            enabled: on,
            title: context.l10n.onlyWhileCharging,
            trailing: _Switch(value: _prefs.chargingOnly),
            onTap:
                on
                    ? () => _update(
                      _prefs.copyWith(chargingOnly: !_prefs.chargingOnly),
                    )
                    : null,
          ),
        ],
      ),
      const SizedBox(height: Spacing.md),
      SettingsSection(
        title: 'Status',
        padded: false,
        children: [
          _Row(
            enabled: on,
            icon: LucideIcons.cloudCheck,
            title: context.l10n.photosBackedUp(_doneCount),
            subtitle: context.l10n.resetBackupHint,
            onTap: (!on || _doneCount == 0) ? null : _resetRecord,
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: _GhostBlockButton(
          label:
              _running ? context.l10n.scanningStatus : context.l10n.backUpNow,
          icon: _running ? null : LucideIcons.cloudUpload,
          onTap: (!on || _running) ? null : _backupNow,
        ),
      ),
    ];
  }

  String _hostLabel(BuildContext context) {
    if (_hosts.isEmpty) return context.l10n.noPairedPcs;
    for (final h in _hosts) {
      if (h.id == _prefs.hostId) return h.label;
    }
    return context.l10n.choosePc;
  }

  Future<void> _pickHost() async {
    final picked = await showModalBottomSheet<Host>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SheetHero(
                    badge: const Icon(LucideIcons.computer),
                    title: ctx.l10n.choosePc,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    child: ActionListCard(
                      children: [
                        for (final h in _hosts)
                          ActionListTile(
                            icon: LucideIcons.computer,
                            label: '${h.label} • ${h.address}',
                            onTap: () => Navigator.pop(ctx, h),
                            trailing:
                                h.id == _prefs.hostId
                                    ? const Icon(LucideIcons.check)
                                    : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (picked != null) await _update(_prefs.copyWith(hostId: picked.id));
  }

  String _albumsLabel(BuildContext context) =>
      _prefs.albumIds.isEmpty
          ? context.l10n.allPhotos
          : context.l10n.albumsSelected(_prefs.albumIds.length);

  Future<void> _pickAlbums() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth && !perm.hasAccess) {
      if (mounted) showError(context, context.l10n.photoAccessDenied);
      return;
    }
    final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    // Album id -> display name + count, sorted by name for a stable list.
    final entries = <(String, String, int)>[];
    for (final a in albums) {
      entries.add((a.id, a.name, await a.assetCountAsync));
    }
    entries.sort((x, y) => x.$2.toLowerCase().compareTo(y.$2.toLowerCase()));
    if (!mounted) return;

    final selected = _prefs.albumIds.toSet();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => StatefulBuilder(
            builder:
                (ctx, setSheet) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SheetHero(
                        badge: const Icon(LucideIcons.images),
                        title: ctx.l10n.selectAlbums,
                        subtitle:
                            selected.isEmpty
                                ? null
                                : ctx.l10n.albumsSelected(selected.length),
                        onClose: () => Navigator.pop(ctx, selected),
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(
                            Spacing.lg,
                            0,
                            Spacing.lg,
                            Spacing.lg,
                          ),
                          children: [
                            ActionListCard(
                              children: [
                                for (final (id, name, count) in entries)
                                  ActionListTile(
                                    icon: LucideIcons.image,
                                    label:
                                        '$name (${ctx.l10n.albumPhotoCount(count)})',
                                    onTap:
                                        () => setSheet(() {
                                          if (selected.contains(id)) {
                                            selected.remove(id);
                                          } else {
                                            selected.add(id);
                                          }
                                        }),
                                    trailing:
                                        selected.contains(id)
                                            ? const Icon(LucideIcons.check)
                                            : const Icon(
                                              LucideIcons.circle,
                                              size: 16,
                                            ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
    if (result != null) {
      await _update(_prefs.copyWith(albumIds: result.toList()));
    }
  }

  Future<void> _resetRecord() async {
    await _store?.resetDone();
    if (mounted) setState(() => _doneCount = 0);
    if (mounted) showInfo(context, context.l10n.backupRecordCleared);
  }
}

/// The mockup's `.row` (optionally `.row-toggle` when there's no icon):
/// 38x38 tonal `.row-icon`, 14px/500 title + 11.5px/faint sub, trailing
/// chevron/switch. [enabled] dims the whole row and disables its tap,
/// matching this screen's real master-switch-gates-everything behavior.
class _Row extends StatelessWidget {
  const _Row({
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: Radii.smR,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Spacing.sm),
            trailing!,
          ],
        ],
      ),
    );
    final content = Opacity(opacity: enabled ? 1 : 0.5, child: row);
    if (onTap == null) return content;
    return Pressable(onTap: enabled ? onTap : null, child: content);
  }
}

/// The mockup's `.switch`: 42x25 pill track, 19x19 thumb — purely decorative
/// here since [_Row] wires the tap on the whole row.
class _Switch extends StatelessWidget {
  const _Switch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 25,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: Radii.stadiumR,
        border: Border.all(
          color: value ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The mockup's `.btn.btn-ghost.btn-block`: full-width, `surface-2`
/// background, 1px border, text then an optional trailing icon. `onTap` may
/// be null to render a disabled state (this screen gates the button on the
/// master switch + in-flight state).
class _GhostBlockButton extends StatelessWidget {
  const _GhostBlockButton({
    required this.label,
    this.icon,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.97,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: Radii.smR,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 7),
                Icon(icon, size: 16, color: scheme.onSurface),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
