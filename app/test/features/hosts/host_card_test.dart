import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/hosts/widgets/host_card.dart';

void main() {
  group('hostAccentColor', () {
    test('is deterministic for the same id', () {
      expect(hostAccentColor('host-1'), hostAccentColor('host-1'));
    });

    test(
      'differs across a spread of ids (not everything collapses to one)',
      () {
        final colors = {
          for (var i = 0; i < 8; i++) 'host-$i': hostAccentColor('host-$i'),
        };
        expect(colors.values.toSet().length, greaterThan(1));
      },
    );
  });
}
