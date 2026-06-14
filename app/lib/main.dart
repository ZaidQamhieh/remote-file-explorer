import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/app_info.dart';
import 'core/settings/settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/hosts/host_list_screen.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    if (!app.dynamicColor) {
      return _app(
        light: AppTheme.light,
        dark: AppTheme.dark,
        mode: app.themeMode,
      );
    }

    // Dynamic color requested: use the platform scheme when available, else
    // fall back to the seed palette. Harmonize keeps brand accents legible
    // against the wallpaper-derived primary.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light = lightDynamic != null
            ? AppTheme.lightFrom(lightDynamic.harmonized())
            : AppTheme.light;
        final dark = darkDynamic != null
            ? AppTheme.darkFrom(darkDynamic.harmonized())
            : AppTheme.dark;
        return _app(light: light, dark: dark, mode: app.themeMode);
      },
    );
  }

  Widget _app({
    required ThemeData light,
    required ThemeData dark,
    required ThemeMode mode,
  }) {
    return MaterialApp(
      title: 'Remote File Explorer',
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      home: const HostListScreen(),
    );
  }
}
