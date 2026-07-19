import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// ShadCard/ShadSwitch/etc. call `ShadTheme.of(context)` and throw without a
/// ShadTheme ancestor — real screens get one from main.dart's [ShadApp], but
/// widget tests that pump a screen directly under a bare [MaterialApp] need
/// this wrapped around it too.
Widget wrapShad(Widget child) => ShadTheme(
  data: ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadZincColorScheme.dark(),
  ),
  child: child,
);
