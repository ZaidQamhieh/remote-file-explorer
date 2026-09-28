import 'package:flutter/material.dart';

import '../../../core/models/device.dart';

enum DeviceFileCapability { browse, download, upload, modify, delete, share }

/// Admin controls for one paired device's independent file-action grants.
class DeviceFileAccessControls extends StatelessWidget {
  const DeviceFileAccessControls({
    super.key,
    required this.device,
    required this.updating,
    required this.onChanged,
  });

  final Device device;
  final bool updating;
  final void Function(DeviceFileCapability capability, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final permissions =
        <({DeviceFileCapability capability, String label, bool enabled})>[
          (
            capability: DeviceFileCapability.browse,
            label: 'Browse files',
            enabled: device.browse ?? false,
          ),
          (
            capability: DeviceFileCapability.download,
            label: 'Download files',
            enabled: device.download ?? false,
          ),
          (
            capability: DeviceFileCapability.upload,
            label: 'Upload files',
            enabled: device.upload ?? false,
          ),
          (
            capability: DeviceFileCapability.modify,
            label: 'Modify files',
            enabled: device.modify ?? false,
          ),
          (
            capability: DeviceFileCapability.delete,
            label: 'Delete files',
            enabled: device.delete ?? false,
          ),
          (
            capability: DeviceFileCapability.share,
            label: 'Create share links',
            enabled: device.share ?? false,
          ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'File access',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const Text(
          'New paired devices can browse only. Upload also allows overwriting existing files. Read-only mode, allowed folders, and global sharing still apply.',
          style: TextStyle(fontSize: 11),
        ),
        for (final permission in permissions)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(permission.label),
            value: permission.enabled,
            onChanged:
                updating
                    ? null
                    : (enabled) => onChanged(permission.capability, enabled),
          ),
      ],
    );
  }
}
