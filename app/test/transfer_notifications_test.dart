import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/platform/transfer_notifications.dart';
import 'package:remote_file_explorer/features/transfers/transfer_state.dart';

const _host = Host(id: 'h1', label: 'PC', address: '127.0.0.1:1');

TransferTask _task(TransferStatus status, {String name = 'file.bin'}) {
  return TransferTask.download(
    remotePath: '/remote/$name',
    localPath: '/tmp/$name',
    host: _host,
  ).copyWith(status: status);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('rfe/transfers');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('active transfers start the foreground service with progress', () {
    TransferNotifications(
      channel: channel,
    ).sync([_task(TransferStatus.running), _task(TransferStatus.queued)]);
    expect(calls.single.method, 'start');
    final args = calls.single.arguments as Map;
    expect(args['progress'], 0); // totalBytes 0 → 0%
    expect(args['text'], contains('2 transfers'));
  });

  test('a single active transfer names the file', () {
    TransferNotifications(
      channel: channel,
    ).sync([_task(TransferStatus.running, name: 'photo.jpg')]);
    expect((calls.single.arguments as Map)['text'], 'photo.jpg');
  });

  test('draining the queue stops the service and posts completion', () {
    final n = TransferNotifications(channel: channel);
    n.sync([_task(TransferStatus.running)]); // becomes active
    calls.clear();
    n.sync([_task(TransferStatus.completed), _task(TransferStatus.failed)]);
    expect(
      calls.map((c) => c.method),
      containsAllInOrder(['stop', 'complete']),
    );
    final completeArgs =
        calls.firstWhere((c) => c.method == 'complete').arguments as Map;
    expect(completeArgs['text'], '1 done · 1 failed');
  });

  test('no active transfers and nothing was running is a no-op', () {
    TransferNotifications(
      channel: channel,
    ).sync([_task(TransferStatus.completed)]);
    expect(calls, isEmpty);
  });
}
