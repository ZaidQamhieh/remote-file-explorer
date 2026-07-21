import 'package:flutter/material.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/pressable.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Maximum size (in bytes) we'll happily load fully into memory for an
/// in-app preview (images, text, PDFs). Beyond this we show a
/// "too large to preview" state and suggest downloading instead.
const int kMaxInMemoryPreviewBytes = 50 * 1024 * 1024; // 50 MB

/// Maximum size (in bytes) we'll download to a temp cache file for audio
/// preview playback. Audio files are far smaller than video, so the cap is
/// lower; beyond it we suggest downloading via the transfer queue instead.
const int kMaxAudioPreviewBytes = 100 * 1024 * 1024; // 100 MB

/// Maximum size (in bytes) of a file we'll offer to edit in-app, matching
/// the agent's `PUT /v1/content` body cap. Saves over this limit are
/// rejected by the agent with `413 PAYLOAD_TOO_LARGE`; we hide the Edit
/// action below this size so the failure mode is rare rather than the norm.
const int kMaxEditableBytes = 5 * 1024 * 1024; // 5 MiB

/// A simple `Scaffold` shell shared by all preview viewers: an `AppBar`
/// with the file name, and a body that reflects [PreviewLoadState].
///
/// Two roles:
/// - **Standalone** (default) — used when a viewer is shown on its own (the
///   single-entry preview path, or a viewer's own internal screen): it builds
///   its own [AppBar] from [title]/[actions].
/// - **Chromeless** — when [chromeless] is `true`, the scaffold renders only
///   the [body] with no app bar. The host (the [PreviewPager]) then overlays a
///   single shared top bar across all pages so the action row stays identical
///   as the user swipes between sibling files. [title]/[actions] are ignored
///   in this mode.
class PreviewScaffold extends StatelessWidget {
  const PreviewScaffold({
    super.key,
    required this.title,
    required this.body,
    this.backgroundColor,
    this.actions,
    this.chromeless = false,
  });

  final String title;
  final Widget body;
  final Color? backgroundColor;
  final List<Widget>? actions;

  /// When `true`, render only [body] (no app bar) so a host can supply shared
  /// chrome. Defaults to `false` (standalone, builds its own app bar).
  final bool chromeless;

  @override
  Widget build(BuildContext context) {
    // Image/video previews sit on a black canvas — render the chrome as a
    // translucent overlay with light foreground so it reads on dark media
    // without fighting the surrounding theme.
    final onDark = backgroundColor == Colors.black;

    if (chromeless) {
      // No app bar — the pager owns a single shared top bar across all pages.
      // Keep the body transparent so the pager's canvas shows through.
      return Scaffold(backgroundColor: backgroundColor, body: body);
    }

    final scheme = Theme.of(context).colorScheme;
    final fg = onDark ? Colors.white : scheme.onSurface;

    // The mockup's literal `.appbar`: back iconbtn + h2 title, no Material
    // `AppBar` elevation/shadow.
    final appBar = PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 8),
      child: Container(
        color: onDark ? Colors.black.withValues(alpha: 0.45) : null,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Pressable(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(LucideIcons.arrowLeft, size: 19, color: fg),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.01,
                    color: fg,
                  ),
                ),
              ),
              if (actions != null)
                IconTheme.merge(
                  data: IconThemeData(color: fg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: onDark,
      appBar: appBar,
      body: body,
    );
  }
}

/// Centered loading indicator with an optional status message — used while
/// preview content is being fetched/decoded.
class PreviewLoading extends StatelessWidget {
  const PreviewLoading({super.key, this.message, this.progress});

  final String? message;

  /// Optional 0.0–1.0 progress value (e.g. download progress for video).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: progress),
          if (message != null) ...[
            const SizedBox(height: Spacing.md),
            Text(message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Centered error state with an icon and message — used when fetching or
/// decoding preview content fails.
class PreviewError extends StatelessWidget {
  const PreviewError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: Spacing.md),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: Spacing.md),
              _GhostButton(
                label: context.l10n.retryButton,
                icon: LucideIcons.refreshCw,
                onTap: onRetry!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The mockup's `.btn.btn-ghost` (surface-2 bg, 1px border, no elevation).
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: Radii.smR,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 7),
            Icon(icon, size: 16, color: scheme.onSurface),
          ],
        ),
      ),
    );
  }
}

/// Centered "file too large to preview" state, suggesting a download.
class PreviewTooLarge extends StatelessWidget {
  const PreviewTooLarge({super.key, required this.sizeLabel});

  final String sizeLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.file,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              context.l10n.fileTooLargeToPreview(sizeLabel),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
