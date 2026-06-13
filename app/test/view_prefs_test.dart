import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/storage/view_prefs.dart';

// view_prefs.dart now holds only the shared view value types (SortOrder,
// SortField, EntryDensity); persistence/resolution moved to
// `core/settings/` (see settings_controller_test.dart). These tests pin the
// value-type semantics widgets and the resolver rely on.

void main() {
  group('SortOrder value semantics', () {
    test('equality compares field and direction', () {
      const a = SortOrder(field: SortField.date, ascending: false);
      const b = SortOrder(field: SortField.date, ascending: false);
      const c = SortOrder(field: SortField.date, ascending: true);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('copyWith flips direction independently of field', () {
      const original = SortOrder(field: SortField.name, ascending: true);
      final flipped = original.copyWith(ascending: false);
      expect(flipped.field, SortField.name);
      expect(flipped.ascending, isFalse);
    });

    test('defaults to name ascending', () {
      const sort = SortOrder();
      expect(sort.field, SortField.name);
      expect(sort.ascending, isTrue);
    });
  });
}
