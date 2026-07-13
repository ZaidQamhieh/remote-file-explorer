import 'package:flutter/material.dart';

import '../../../core/api/agent_client.dart';
import '../../../core/models/entry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/feedback.dart';
import '../../../core/ui/sheet_chrome.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Dialog with a 3x3 checkbox grid (owner/group/other x read/write/execute)
/// for editing POSIX file permissions. Calls [AgentClient.chmod] on apply.
class ChmodDialog extends StatefulWidget {
  const ChmodDialog({super.key, required this.entry, required this.client});

  final Entry entry;
  final AgentClient client;

  /// Shows the dialog and returns the updated [Entry] on success, or null if
  /// the user cancels.
  static Future<Entry?> show(
    BuildContext context, {
    required Entry entry,
    required AgentClient client,
  }) {
    return showDialog<Entry>(
      context: context,
      builder: (_) => ChmodDialog(entry: entry, client: client),
    );
  }

  @override
  State<ChmodDialog> createState() => _ChmodDialogState();
}

class _ChmodDialogState extends State<ChmodDialog> {
  // 9 permission bits: rwx for owner, group, other.
  late List<bool> _bits;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _bits = _parseBits(widget.entry.mode ?? '----------');
  }

  /// Parses a POSIX mode string like `-rwxr-xr--` into 9 booleans.
  static List<bool> _parseBits(String mode) {
    final perms = mode.length >= 10 ? mode.substring(1, 10) : '---------';
    return List.generate(9, (i) => perms[i] != '-');
  }

  /// Converts the 9 bits to an octal string like `0754`.
  String get _octal {
    int val = 0;
    for (var i = 0; i < 9; i++) {
      if (_bits[i]) val |= (1 << (8 - i));
    }
    return val.toRadixString(8).padLeft(4, '0');
  }

  /// Converts the 9 bits to a symbolic string like `rwxr-xr--`.
  String get _symbolic {
    const chars = 'rwxrwxrwx';
    return String.fromCharCodes([
      for (var i = 0; i < 9; i++)
        _bits[i] ? chars.codeUnitAt(i) : '-'.codeUnitAt(0),
    ]);
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final updated = await widget.client.chmod(widget.entry.path, _octal);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) showError(context, 'chmod failed: $e');
      setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['Owner', 'Group', 'Other'];
    const perms = ['R', 'W', 'X'];
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: Radii.lgR),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHero(
            showGrabber: false,
            badge: const Icon(LucideIcons.lock),
            title: 'Permissions',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _symbolic,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 4),
                Text(_octal, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                for (var row = 0; row < 3; row++)
                  Row(
                    children: [
                      SizedBox(width: 60, child: Text(labels[row])),
                      for (var col = 0; col < 3; col++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _bits[row * 3 + col],
                              onChanged:
                                  _applying
                                      ? null
                                      : (v) {
                                        setState(
                                          () => _bits[row * 3 + col] = v!,
                                        );
                                      },
                            ),
                            Text(perms[col]),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _applying ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: Spacing.sm),
                FilledButton(
                  onPressed: _applying ? null : _apply,
                  child:
                      _applying
                          ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
