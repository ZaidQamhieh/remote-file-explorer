import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import 'photo_backup_controller.dart';
import 'photo_backup_prefs.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
      if (mounted) showError(context, context.l10n.backupFailed('$e'));
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
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                children: _buildItems(context),
              ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    // Master switch off => every other control is disabled (nothing backs up).
    final on = _prefs.enabled;
    return [
      SwitchListTile(
        title: Text(context.l10n.enablePhotoBackup),
        subtitle: Text(context.l10n.photoBackupSubtitle),
        value: _prefs.enabled,
        onChanged: (v) => _update(_prefs.copyWith(enabled: v)),
      ),
      const Divider(),
      ListTile(
        enabled: on,
        leading: const Icon(LucideIcons.computer),
        title: Text(context.l10n.backUpTo),
        subtitle: Text(_hostLabel(context)),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: (!on || _hosts.isEmpty) ? null : _pickHost,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.sm,
        ),
        child: TextField(
          controller: _nicknameCtrl,
          enabled: on,
          decoration: InputDecoration(
            labelText: context.l10n.deviceNicknameLabel,
            hintText: context.l10n.deviceNicknameHint,
            helperText: context.l10n.deviceNicknameHelper,
          ),
          onChanged: (v) => _update(_prefs.copyWith(deviceName: v.trim())),
        ),
      ),
      ListTile(
        enabled: on,
        leading: const Icon(LucideIcons.images),
        title: Text(context.l10n.albumsToBackUp),
        subtitle: Text(_albumsLabel(context)),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: on ? _pickAlbums : null,
      ),
      const Divider(),
      SwitchListTile(
        title: Text(context.l10n.onlyOnWifi),
        value: _prefs.wifiOnly,
        onChanged: on ? (v) => _update(_prefs.copyWith(wifiOnly: v)) : null,
      ),
      SwitchListTile(
        title: Text(context.l10n.onlyWhileCharging),
        value: _prefs.chargingOnly,
        onChanged: on ? (v) => _update(_prefs.copyWith(chargingOnly: v)) : null,
      ),
      const Divider(),
      ListTile(
        enabled: on,
        leading: const Icon(LucideIcons.cloudCheck),
        title: Text(context.l10n.photosBackedUp(_doneCount)),
        subtitle: Text(context.l10n.resetBackupHint),
        onTap: (!on || _doneCount == 0) ? null : _resetRecord,
      ),
      Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: FilledButton.icon(
          onPressed: (!on || _running) ? null : _backupNow,
          icon:
              _running
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(LucideIcons.cloudUpload),
          label: Text(
            _running ? context.l10n.scanningStatus : context.l10n.backUpNow,
          ),
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
          (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final h in _hosts)
                  ListTile(
                    leading: const Icon(LucideIcons.computer),
                    title: Text(h.label),
                    subtitle: Text(h.address),
                    selected: h.id == _prefs.hostId,
                    onTap: () => Navigator.pop(context, h),
                  ),
              ],
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
                      Padding(
                        padding: const EdgeInsets.all(Spacing.lg),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                ctx.l10n.selectAlbums,
                                style: Theme.of(ctx).textTheme.titleMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, selected),
                              child: Text(ctx.l10n.applyButton),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final (id, name, count) in entries)
                              CheckboxListTile(
                                value: selected.contains(id),
                                title: Text(name),
                                subtitle: Text(ctx.l10n.albumPhotoCount(count)),
                                onChanged:
                                    (v) => setSheet(() {
                                      if (v ?? false) {
                                        selected.add(id);
                                      } else {
                                        selected.remove(id);
                                      }
                                    }),
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
