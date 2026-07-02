import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
import 'features/share/share_intake.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final info = await PackageInfo.fromPlatform();
  appClientVersion = '${info.version}+${info.buildNumber}';
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
        locale: app.locale,
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
          locale: app.locale,
        );
      },
    );
  }

  Widget _app({
    required ThemeData light,
    required ThemeData dark,
    required ThemeMode mode,
    Locale? locale,
  }) {
    return MaterialApp(
      title: 'Remote File Explorer',
      navigatorKey: navigatorKey,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
