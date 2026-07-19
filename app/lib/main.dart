import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:workmanager/workmanager.dart';

import 'core/app_info.dart';
import 'core/platform/transfer_notifications.dart';
import 'core/settings/settings_controller.dart';
import 'core/update/auto_update.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/lock_gate.dart';
import 'features/home/home_shell.dart';
import 'features/hosts/host_open_listener.dart';
import 'features/hosts/weekly_digest_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/update_tile.dart';
import 'features/share/share_intake.dart';

/// WorkManager's unique + task name for the periodic background update check
/// (see [callbackDispatcher]). Same string for both since this app only ever
/// schedules one such task.
const _kUpdateCheckTask = 'rfe_update_check';

/// Entry point WorkManager relaunches in a headless background isolate to
/// run scheduled tasks — has no widget tree/`ProviderScope`, hence
/// [checkAndDownloadUpdateInBackground] being ref-free. Must stay a top-level
/// (or static) function annotated `@pragma('vm:entry-point')` so it survives
/// tree-shaking/obfuscation.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _kUpdateCheckTask) {
      await checkAndDownloadUpdateInBackground();
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final info = await PackageInfo.fromPlatform();
  appClientVersion = '${info.version}+${info.buildNumber}';
  if (Platform.isAndroid) {
    // Cold-launch case: the app process was killed (the common case, since
    // the background check runs precisely while it's not open) and the user
    // tapped the "Update ready" notification, which launched this process.
    // [updateNotificationTapProvider]'s onDidReceiveNotificationResponse only
    // fires for taps while the process is already alive, so this is the only
    // place a cold-launch tap can be observed — flutter_local_notifications
    // buffers it for `getNotificationAppLaunchDetails()` instead.
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final launchDetails = await plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        await installFromNotificationTap(
          launchDetails!.notificationResponse?.payload,
        );
      }
    } catch (_) {
      /* best effort */
    }

    // Best effort: WorkManager setup failing (e.g. OEM quirk) shouldn't block
    // app startup — the passive in-app check ([latestUpdateProvider]) still
    // covers updates whenever the app is opened.
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _kUpdateCheckTask,
        _kUpdateCheckTask,
        // ponytail: 6h/unmetered+not-low-battery are reasonable defaults, not
        // a spec'd requirement — revisit if the owner wants a tighter check
        // interval or to allow metered networks.
        frequency: const Duration(hours: 6),
        constraints: Constraints(
          networkType: NetworkType.unmetered,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      /* best effort — see comment above */
    }
  }
  runApp(const ProviderScope(child: RemoteFileExplorerApp()));
}

/// Root app widget. Watches the app-global appearance settings (theme mode +
/// dynamic color) and builds the [MaterialApp] accordingly.
///
/// **Dynamic-color fallback:** when `dynamicColor` is on we wrap in a
/// [DynamicColorBuilder] and build the themes from the platform's
/// `lightDynamic`/`darkDynamic` schemes, harmonized toward the brand seed. If
/// the platform supplies no dynamic scheme (older Android, desktop, iOS) — or
/// when `dynamicColor` is off — we fall back to the seed-based
/// [AppTheme.light]/[AppTheme.dark]. While settings are still loading we use
/// those seed-based defaults + [ThemeMode.system] so the first frame is
/// unaffected.
class RemoteFileExplorerApp extends ConsumerWidget {
  const RemoteFileExplorerApp({super.key});

  /// App-wide navigator key so [ShareIntakeListener] can push routes and show
  /// sheets/snackbars from outside the widget tree (e.g. right at cold start,
  /// in response to a "Share to…" intent).
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the transfer foreground-service/notification bridge alive for the
    // whole app lifetime so backgrounded transfers stay running + visible.
    ref.watch(transferNotificationsProvider);
    // Silently pre-download an available update's APK so tapping "Update" in
    // Settings is instant instead of waiting through the full download.
    ref.watch(backgroundApkDownloadProvider);
    // Wire the "Update ready" notification's tap action to the installer
    // (see checkAndDownloadUpdateInBackground / callbackDispatcher above).
    ref.watch(updateNotificationTapProvider);

    final settings = ref.watch(settingsProvider).valueOrNull;

    // First frame (settings still loading): seed-based themes + system mode.
    if (settings == null) {
      return _app(
        light: AppTheme.light,
        dark: AppTheme.dark,
        mode: ThemeMode.system,
      );
    }

    final app = settings.app;

    ThemeData Function(ThemeData) maybePatchDark =
        app.amoledDark ? AppTheme.toAmoled : (d) => d;

    if (!app.dynamicColor) {
      final seed = app.seedColor;
      final light =
          seed != null ? AppTheme.lightWithSeed(seed) : AppTheme.light;
      final dark = seed != null ? AppTheme.darkWithSeed(seed) : AppTheme.dark;
      return _app(
        light: light,
        dark: maybePatchDark(dark),
        mode: app.themeMode,
      );
    }

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light =
            lightDynamic != null
                ? AppTheme.lightFrom(lightDynamic.harmonized())
                : AppTheme.light;
        final dark =
            darkDynamic != null
                ? AppTheme.darkFrom(darkDynamic.harmonized())
                : AppTheme.dark;
        return _app(
          light: light,
          dark: maybePatchDark(dark),
          mode: app.themeMode,
        );
      },
    );
  }

  Widget _app({
    required ThemeData light,
    required ThemeData dark,
    required ThemeMode mode,
  }) {
    // ShadApp wraps the same WidgetsApp/Navigator/Localizations machinery
    // MaterialApp used — existing Material widgets, routes, and l10n are
    // unaffected. materialThemeBuilder hands back our hand-tuned [light]/
    // [dark] ThemeData verbatim (dynamic color, AMOLED, accent picker all
    // still flow through unchanged); the ShadThemeData below only drives the
    // new Shad* widgets being introduced screen-by-screen.
    return ShadApp(
      title: 'Remote File Explorer',
      navigatorKey: navigatorKey,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: AppTheme.shadColorSchemeFrom(light.colorScheme),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: AppTheme.shadColorSchemeFrom(dark.colorScheme),
      ),
      themeMode: mode,
      // `theme` here is ShadApp's already-resolved brightness for the
      // current themeMode/platform — defer to it rather than re-deriving.
      materialThemeBuilder:
          (context, theme) =>
              theme.brightness == Brightness.dark ? dark : light,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // ShadApp (unlike MaterialApp) doesn't insert a root ScaffoldMessenger
      // on its own, so every `ScaffoldMessenger.maybeOf(context)` call in
      // feedback.dart silently found nothing and no-op'd, and every direct
      // `ScaffoldMessenger.of(context)` call (video_preview.dart,
      // update_banner.dart, host_card.dart) would have thrown. One root
      // messenger here fixes both call-site styles at once (PR-62).
      builder:
          (context, child) =>
              ScaffoldMessenger(child: child ?? const SizedBox.shrink()),
      home: ShareIntakeListener(
        navigatorKey: navigatorKey,
        child: HostOpenListener(
          navigatorKey: navigatorKey,
          child: const LockGate(
            child: WeeklyDigestChecker(child: _HomeRouter()),
          ),
        ),
      ),
    );
  }
}

class _HomeRouter extends ConsumerWidget {
  const _HomeRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(onboardingCompleteProvider);
    return onboarded.when(
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const HomeShell(),
      data: (complete) {
        if (complete) return const HomeShell();
        return OnboardingScreen(
          onComplete: () => ref.invalidate(onboardingCompleteProvider),
        );
      },
    );
  }
}
