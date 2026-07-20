import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/gradient_blob_hero.dart';

class CenteredMessage extends StatelessWidget {
  const CenteredMessage({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GradientBlobHero(icon: icon, size: 96),
            const SizedBox(height: Spacing.sm + Spacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
