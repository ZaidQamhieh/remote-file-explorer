import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/ui/state_views.dart';

void main() {
  group('resolveEmptyState', () {
    test('no raw entries -> emptyFolder', () {
      expect(
        resolveEmptyState(hasRawEntries: false),
        EmptyStateKind.emptyFolder,
      );
    });

    test('raw entries exist but all filtered out -> noMatches', () {
      expect(resolveEmptyState(hasRawEntries: true), EmptyStateKind.noMatches);
    });
  });
}
