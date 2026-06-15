import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import 'photo_backup_controller.dart';
import 'photo_backup_prefs.dart';

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
  final _destCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _destCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await PhotoBackupStore.open();
    final hostStore = await ref.read(hostStoreProvider.future);
    if (!mounted) return;
    setState(() {
      _store = store;
      _prefs = store.load();
      _destCtrl.text = _prefs.destRoot ?? '';
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
          showSuccess(context, 'Backing up ${result.enqueued} photo(s)');
        case PhotoBackupOutcome.upToDate:
          showInfo(context, 'Already up to date');
        case PhotoBackupOutcome.notConfigured:
          showError(context, 'Pick a PC and destination folder first');
        case PhotoBackupOutcome.permissionDenied:
          showError(
            context,
            'Photo access denied — grant it in system settings',
          );
        case PhotoBackupOutcome.skipped:
          showInfo(context, result.message ?? 'Skipped');
      }
      // Refresh the backed-up count.
      final store = await PhotoBackupStore.open();
      if (mounted) setState(() => _doneCount = store.doneIds().length);
    } catch (e) {
      if (mounted) showError(context, 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photo backup')),
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
    return [
      SwitchListTile(
        title: const Text('Enable photo backup'),
        subtitle: const Text('One-way: copies new photos to your PC'),
        value: _prefs.enabled,
        onChanged: (v) => _update(_prefs.copyWith(enabled: v)),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.computer_outlined),
        title: const Text('Back up to'),
        subtitle: Text(_hostLabel()),
        trailing: const Icon(Icons.chevron_right),
        onTap: _hosts.isEmpty ? null : _pickHost,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.sm,
        ),
        child: TextField(
          controller: _destCtrl,
          decoration: const InputDecoration(
            labelText: 'Destination folder on PC',
            hintText: '/home/you/PhoneBackup',
            helperText: 'Photos land in <folder>/YYYY/YYYY-MM/',
          ),
          onChanged: (v) => _update(_prefs.copyWith(destRoot: v.trim())),
        ),
      ),
      const Divider(),
      SwitchListTile(
        title: const Text('Only on Wi-Fi'),
        value: _prefs.wifiOnly,
        onChanged: (v) => _update(_prefs.copyWith(wifiOnly: v)),
      ),
      SwitchListTile(
        title: const Text('Only while charging'),
        value: _prefs.chargingOnly,
        onChanged: (v) => _update(_prefs.copyWith(chargingOnly: v)),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.cloud_done_outlined),
        title: Text('$_doneCount photo(s) backed up'),
        subtitle: const Text(
          'Tap to forget the record (re-backs-up everything)',
        ),
        onTap: _doneCount == 0 ? null : _resetRecord,
      ),
      Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: FilledButton.icon(
          onPressed: _running ? null : _backupNow,
          icon:
              _running
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.backup_outlined),
          label: Text(_running ? 'Scanning…' : 'Back up now'),
        ),
      ),
    ];
  }

  String _hostLabel() {
    if (_hosts.isEmpty) return 'No paired PCs — pair one first';
    for (final h in _hosts) {
      if (h.id == _prefs.hostId) return h.label;
    }
    return 'Choose a PC';
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
                    leading: const Icon(Icons.computer),
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

  Future<void> _resetRecord() async {
    await _store?.resetDone();
    if (mounted) setState(() => _doneCount = 0);
    if (mounted) showInfo(context, 'Backup record cleared');
  }
}
