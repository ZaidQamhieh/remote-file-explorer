import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/pressable.dart';

/// The mockup's `.files-fab .fab`: a single 52x52 circular button (violet
/// gradient, not the app-wide blue/violet primary FAB gradient) that opens
/// the new-folder/new-file/upload sheet. The mockup itself never defines
/// that sheet's contents (its "New folder / Upload" tap just shows a mock
/// toast) — see `CreateMenu` for the real menu, which keeps its existing
/// quick-action-circle content since there's no literal markup to match it
/// against.
class ExplorerFab extends StatelessWidget {
  const ExplorerFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.92,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Brand.accent, Color(0xFF7C6AE0)],
          ),
          boxShadow: [
            BoxShadow(
              color: Brand.accent.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(LucideIcons.plus, color: Colors.white, size: 22),
      ),
    );
  }
}
