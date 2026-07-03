import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// App-wide action feedback: one consistent surface for success / error / info,
/// so every action gives the same legible, modern confirmation instead of the
/// ad-hoc plain snackbars scattered across the app.
///
/// Each helper shows a floating, rounded snackbar with a leading status icon and
/// colour, plus matching haptics (light tap on success, a firmer buzz on error).
/// [runWithFeedback] wraps an async action with an optional in-progress snackbar
/// and a terminal success/error message, removing the repetitive
/// try/catch + showSnackBar boilerplate at call sites.

enum _Kind { success, error, info }

/// Shows a success confirmation (green, check icon) with a light haptic.
/// Pass [action] to offer an inline button (e.g. Undo).
void showSuccess(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  HapticFeedback.lightImpact();
  _show(context, message, _Kind.success, action: action);
}

/// Shows an error (error colour, alert icon) with a firmer haptic. Pass
/// [onRetry] to offer a Retry button wired to it.
void showError(BuildContext context, String message, {VoidCallback? onRetry}) {
  HapticFeedback.heavyImpact();
  final action =
      onRetry == null
          ? null
          : SnackBarAction(label: 'Retry', onPressed: onRetry);
  _show(context, message, _Kind.error, action: action);
}

/// Shows a neutral informational message (no haptic).
void showInfo(BuildContext context, String message) {
  _show(context, message, _Kind.info);
}

/// Runs [action], showing an optional in-progress snackbar ([running]) while it
/// runs, then a terminal message: [success] (built from the result) on success
/// or [error] (with the exception appended) on failure. Returns the result, or
/// null if it threw. Safe to call with an unmounted context — it no-ops the UI.
Future<T?> runWithFeedback<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? running,
  String Function(T value)? success,
  String error = 'Action failed',
  VoidCallback? onRetry,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (running != null && messenger != null) {
    messenger.showSnackBar(_progressBar(context, running));
  }
  try {
    final value = await action();
    messenger?.hideCurrentSnackBar();
    if (context.mounted && success != null) {
      showSuccess(context, success(value));
    }
    return value;
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    if (context.mounted) {
      showError(context, '$error: $e', onRetry: onRetry);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

void _show(
  BuildContext context,
  String message,
  _Kind kind, {
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;

  late final Color bg;
  late final Color fg;
  late final IconData icon;
  switch (kind) {
    case _Kind.success:
      // No "success" role in Material's scheme; use a green tuned per brightness
      // so the floating snackbar reads well in both light and dark.
      bg = isDark ? const Color(0xFF2E7D32) : const Color(0xFF1B5E20);
      fg = Colors.white;
      icon = LucideIcons.circleCheck;
    case _Kind.error:
      bg = scheme.error;
      fg = scheme.onError;
      icon = LucideIcons.circleAlert;
    case _Kind.info:
      bg = scheme.inverseSurface;
      fg = scheme.onInverseSurface;
      icon = LucideIcons.info;
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        duration: Duration(seconds: kind == _Kind.error ? 5 : 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: fg))),
          ],
        ),
        action:
            action == null
                ? null
                : SnackBarAction(
                  label: action.label,
                  textColor: fg,
                  onPressed: action.onPressed,
                ),
      ),
    );
}

SnackBar _progressBar(BuildContext context, String message) {
  final scheme = Theme.of(context).colorScheme;
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: scheme.inverseSurface,
    duration: const Duration(minutes: 1), // dismissed when the action resolves
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    content: Row(
      children: [
        SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(scheme.onInverseSurface),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: scheme.onInverseSurface),
          ),
        ),
      ],
    ),
  );
}
