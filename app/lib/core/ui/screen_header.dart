import 'package:flutter/material.dart';

/// The mockup's `.appbar-row h2` + `.appbar-sub` — used as an [AppBar.title]
/// on the app's top-level tabs (Devices, Transfers, Settings) in place of a
/// plain [Text] title. Literal values from `docs/mockup-reference/mockup.css`
/// (19px/700/-0.01em title, 11.5px faint subtitle) — not the earlier 32px/800
/// Figma-derived size, which never matched the real mockup.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.19,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
