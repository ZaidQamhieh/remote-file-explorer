import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

class LoadMoreIndicator extends StatelessWidget {
  const LoadMoreIndicator({super.key, required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
      child: Center(
        child:
            loading
                ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const SizedBox.square(dimension: 24),
      ),
    );
  }
}
