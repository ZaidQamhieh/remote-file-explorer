import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/device.dart';
import 'package:remote_file_explorer/features/settings/widgets/device_file_access_controls.dart';

void main() {
  Device device() => Device(
    id: 'guest',
    label: 'Guest phone',
    created: DateTime.fromMillisecondsSinceEpoch(0),
    lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
    revoked: false,
    current: false,
    browse: true,
    download: false,
    upload: false,
    modify: false,
    delete: false,
    share: false,
  );

  testWidgets(
    'shows six independent file grants and forwards the selected toggle',
    (tester) async {
      DeviceFileCapability? changedCapability;
      bool? changedValue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceFileAccessControls(
              device: device(),
              updating: false,
              onChanged: (capability, enabled) {
                changedCapability = capability;
                changedValue = enabled;
              },
            ),
          ),
        ),
      );

      expect(find.byType(SwitchListTile), findsNWidgets(6));
      expect(find.text('Browse files'), findsOneWidget);
      expect(find.text('Download files'), findsOneWidget);
      expect(find.text('Upload files'), findsOneWidget);
      expect(find.text('Modify files'), findsOneWidget);
      expect(find.text('Delete files'), findsOneWidget);
      expect(find.text('Create share links'), findsOneWidget);

      await tester.tap(find.text('Download files'));
      expect(changedCapability, DeviceFileCapability.download);
      expect(changedValue, isTrue);
    },
  );

  testWidgets('disables all switches while a permission update is in flight', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceFileAccessControls(
            device: device(),
            updating: true,
            onChanged: (_, _) => fail('disabled control should not call back'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Browse files'));
    expect(tester.takeException(), isNull);
  });
}
