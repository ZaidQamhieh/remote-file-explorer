import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('showNewFileNotification builds correct title and body', () async {
    final fake = _FakePlugin();
    final svc = NotificationService(plugin: fake);

    await svc.showNewFileNotification('/home/user/Downloads', 'photo.jpg');

    expect(fake.lastTitle, 'New file in Downloads');
    expect(fake.lastBody, 'photo.jpg');
  });

  test('showNewFileNotification uses folderPath hashCode as id', () async {
    final fake = _FakePlugin();
    final svc = NotificationService(plugin: fake);
    const folder = '/home/user/Documents';

    await svc.showNewFileNotification(folder, 'file.txt');

    expect(fake.lastId, folder.hashCode.abs());
  });

  test('init is idempotent — called only once per instance', () async {
    final fake = _FakePlugin();
    final svc = NotificationService(plugin: fake);

    await svc.init();
    await svc.init();

    expect(fake.initCount, 1);
  });
}

// ---------------------------------------------------------------------------
// Fake plugin — avoids platform channel calls in tests.
// ---------------------------------------------------------------------------

class _FakePlugin extends Fake implements FlutterLocalNotificationsPlugin {
  int? lastId;
  String? lastTitle;
  String? lastBody;
  int initCount = 0;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    void Function(NotificationResponse)? onDidReceiveNotificationResponse,
    void Function(NotificationResponse)?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initCount++;
    return true;
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    lastId = id;
    lastTitle = title;
    lastBody = body;
  }
}
