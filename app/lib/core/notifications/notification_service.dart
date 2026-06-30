import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Wraps [FlutterLocalNotificationsPlugin] for the watched-folder feature (L3).
///
/// Inject a [FlutterLocalNotificationsPlugin] in tests to avoid platform calls.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// Initialises the plugin (idempotent). Called lazily by [showNewFileNotification].
  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Shows "New file in `folderName`" with [fileName] as the body.
  ///
  /// Uses [folderPath].hashCode as the notification id so multiple files in the
  /// same folder collapse into one notification (replacing the previous one).
  Future<void> showNewFileNotification(
    String folderPath,
    String fileName,
  ) async {
    await init();
    await _plugin.show(
      folderPath.hashCode.abs(),
      'New file in ${p.basename(folderPath)}',
      fileName,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rfe_watched_folders',
          'Watched folder changes',
          channelDescription: 'New files in folders you are watching',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
