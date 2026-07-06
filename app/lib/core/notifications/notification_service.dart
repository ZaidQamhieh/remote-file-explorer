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

  /// Initialises the plugin (idempotent — only the first call's [onTap] is
  /// wired up). Called lazily by [showNewFileNotification] etc.; pass [onTap]
  /// when you need to react to a notification being tapped while the app is
  /// running (e.g. [RemoteFileExplorerApp] wiring the update-ready tap before
  /// anything else can call [init] without one).
  Future<void> init({void Function(NotificationResponse)? onTap}) async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: onTap,
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

  /// Shows the weekly storage-trend digest (L4) with [summary] as the body.
  ///
  /// Uses a fixed notification id so each week's digest replaces the last
  /// one rather than stacking up. Separate channel (`rfe_weekly_digest`) from
  /// watched-folder notifications so the user can mute one without the other.
  Future<void> showWeeklyDigest(String summary) async {
    await init();
    await _plugin.show(
      _weeklyDigestNotificationId,
      'Weekly storage digest',
      summary,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rfe_weekly_digest',
          'Weekly storage digest',
          channelDescription: 'Weekly summary of free-space trends per host',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  /// Shows "Update ready — tap to install" for a background-downloaded APK
  /// ([versionCode]/[versionName]). Payload carries [versionCode] as a string
  /// so a tap handler can locate the cached APK via `apkCacheFileFor`.
  Future<void> showUpdateReadyNotification(
    int versionCode,
    String versionName,
  ) async {
    await init();
    await _plugin.show(
      _updateReadyNotificationId,
      'Update ready',
      'Version $versionName downloaded — tap to install',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rfe_update_ready',
          'App update ready',
          channelDescription: 'A downloaded app update is ready to install',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: '$versionCode',
    );
  }
}

const _weeklyDigestNotificationId = 0x57446967; // 'WDig'
const _updateReadyNotificationId = 0x55706452; // 'UpdR'

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
