import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/clipboard_state.dart';

void main() {
  group('ClipboardNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('starts empty (null)', () {
      expect(container.read(clipboardProvider), isNull);
    });

    test('copy sets mode/paths/hostId', () {
      final notifier = container.read(clipboardProvider.notifier);
      notifier.copy(['/root/a.txt', '/root/b.txt'], 'host-1');

      final clip = container.read(clipboardProvider);
      expect(clip, isNotNull);
      expect(clip!.mode, ClipboardMode.copy);
      expect(clip.paths, ['/root/a.txt', '/root/b.txt']);
      expect(clip.hostId, 'host-1');
      expect(clip.isEmpty, isFalse);
    });

    test('cut sets mode/paths/hostId', () {
      final notifier = container.read(clipboardProvider.notifier);
      notifier.cut(['/root/c.txt'], 'host-2');

      final clip = container.read(clipboardProvider);
      expect(clip, isNotNull);
      expect(clip!.mode, ClipboardMode.cut);
      expect(clip.paths, ['/root/c.txt']);
      expect(clip.hostId, 'host-2');
    });

    test('clear empties the clipboard', () {
      final notifier = container.read(clipboardProvider.notifier);
      notifier.copy(['/root/a.txt'], 'host-1');
      expect(container.read(clipboardProvider), isNotNull);

      notifier.clear();
      expect(container.read(clipboardProvider), isNull);
    });

    test('copy with empty paths leaves the clipboard null', () {
      final notifier = container.read(clipboardProvider.notifier);
      notifier.copy(const [], 'host-1');
      expect(container.read(clipboardProvider), isNull);
    });

    test('cut with empty paths leaves the clipboard null', () {
      final notifier = container.read(clipboardProvider.notifier);
      notifier.cut(const [], 'host-1');
      expect(container.read(clipboardProvider), isNull);
    });

    test('copy with empty paths does not clear an existing clipboard', () {
      final notifier = container.read(clipboardProvider.notifier);
      notifier.cut(['/root/a.txt'], 'host-1');
      notifier.copy(const [], 'host-2');

      final clip = container.read(clipboardProvider);
      expect(clip, isNotNull);
      expect(clip!.mode, ClipboardMode.cut);
      expect(clip.paths, ['/root/a.txt']);
      expect(clip.hostId, 'host-1');
    });

    test('a later cut/copy replaces the previous clipboard contents', () {
      final notifier = container.read(clipboardProvider.notifier);
      notifier.copy(['/root/a.txt'], 'host-1');
      notifier.cut(['/root/b.txt', '/root/c.txt'], 'host-2');

      final clip = container.read(clipboardProvider);
      expect(clip!.mode, ClipboardMode.cut);
      expect(clip.paths, ['/root/b.txt', '/root/c.txt']);
      expect(clip.hostId, 'host-2');
    });
  });
}
