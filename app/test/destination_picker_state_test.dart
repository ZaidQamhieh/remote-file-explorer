import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/api/providers.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/features/explorer/destination_picker_state.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

/// Polls [predicate] until it's true or [timeout] elapses, pumping the event
/// loop between checks so the microtask-scheduled initial load gets a chance
/// to complete.
Future<void> _waitUntil(bool Function() predicate,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Entry _dir(String path) => Entry(
      name: path.split('/').last,
      path: path,
      isDir: true,
    );

Entry _file(String path) => Entry(
      name: path.split('/').last,
      path: path,
      isDir: false,
      size: 10,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _FakeAgentClient client;

  setUp(() {
    client = _FakeAgentClient(host: _testHost);
    container = ProviderContainer(
      overrides: [
        clientProvider.overrideWith((ref, hostId) async => client),
      ],
    );
    addTearDown(container.dispose);
  });

  group('DestinationPickerNotifier', () {
    test('initial load filters out files, keeping only directories',
        () async {
      client.pages['/root'] = Listing(path: '/root', entries: [
        _dir('/root/Documents'),
        _file('/root/notes.txt'),
        _dir('/root/Photos'),
      ]);

      final arg = (hostId: 'h1', startPath: '/root');
      container.listen(destinationPickerProvider(arg), (_, _) {});
      await _waitUntil(
          () => container.read(destinationPickerProvider(arg)).folders.isNotEmpty);

      final state = container.read(destinationPickerProvider(arg));
      expect(state.folders.map((e) => e.name), ['Documents', 'Photos']);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
    });

    test('navigate pushes onto the path stack and loads the new directory',
        () async {
      client.pages['/root'] =
          Listing(path: '/root', entries: [_dir('/root/Documents')]);
      client.pages['/root/Documents'] = Listing(
          path: '/root/Documents', entries: [_dir('/root/Documents/Sub')]);

      final arg = (hostId: 'h1', startPath: '/root');
      container.listen(destinationPickerProvider(arg), (_, _) {});
      final notifier = container.read(destinationPickerProvider(arg).notifier);
      await _waitUntil(
          () => container.read(destinationPickerProvider(arg)).folders.isNotEmpty);

      notifier.navigate('/root/Documents');
      await _waitUntil(() => container
          .read(destinationPickerProvider(arg))
          .folders
          .any((e) => e.name == 'Sub'));

      final state = container.read(destinationPickerProvider(arg));
      expect(state.pathStack, ['/', '/root', '/root/Documents']);
      expect(state.currentPath, '/root/Documents');
    });

    test('navigateTo truncates the path stack and reloads', () async {
      client.pages['/root'] =
          Listing(path: '/root', entries: [_dir('/root/Documents')]);
      client.pages['/root/Documents'] = Listing(
          path: '/root/Documents', entries: [_dir('/root/Documents/Sub')]);

      final arg = (hostId: 'h1', startPath: '/root');
      container.listen(destinationPickerProvider(arg), (_, _) {});
      final notifier = container.read(destinationPickerProvider(arg).notifier);
      await _waitUntil(
          () => container.read(destinationPickerProvider(arg)).folders.isNotEmpty);

      notifier.navigate('/root/Documents');
      await _waitUntil(() => container
          .read(destinationPickerProvider(arg))
          .pathStack
          .length == 3);

      notifier.navigateTo(1);
      await _waitUntil(() => container
          .read(destinationPickerProvider(arg))
          .pathStack
          .length == 2);

      final state = container.read(destinationPickerProvider(arg));
      expect(state.pathStack, ['/', '/root']);
      expect(state.currentPath, '/root');
    });

    test('createFolder posts a separator-joined path then refreshes',
        () async {
      client.pages['/root'] = Listing(path: '/root', entries: []);

      final arg = (hostId: 'h1', startPath: '/root');
      container.listen(destinationPickerProvider(arg), (_, _) {});
      final notifier = container.read(destinationPickerProvider(arg).notifier);
      await _waitUntil(
          () => container.read(destinationPickerProvider(arg)).loading == false);

      // Refresh after createFolder will re-list '/root' and should now
      // include the new folder.
      client.pages['/root'] =
          Listing(path: '/root', entries: [_dir('/root/New folder')]);

      await notifier.createFolder('New folder');

      expect(client.createdFolders, ['/root/New folder']);
      final state = container.read(destinationPickerProvider(arg));
      expect(state.folders.map((e) => e.name), ['New folder']);
    });

    test('error is captured in state when list() throws', () async {
      // No pages registered for '/root' -> the fake throws.
      final arg = (hostId: 'h1', startPath: '/root');
      container.listen(destinationPickerProvider(arg), (_, _) {});
      await _waitUntil(
          () => container.read(destinationPickerProvider(arg)).error != null);

      final state = container.read(destinationPickerProvider(arg));
      expect(state.error, isNotNull);
      expect(state.folders, isEmpty);
    });
  });
}

/// Fake [AgentClient] serving canned [Listing] responses (keyed by path,
/// returned as-is on every call — overwrite [pages] entries to change what a
/// subsequent reload sees) and recording [createFolder] calls.
class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({required Host host}) : super(host);

  final Map<String, Listing> pages = {};
  final List<String> createdFolders = [];

  @override
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    final listing = pages[path];
    if (listing == null) {
      throw StateError('No fake page registered for path "$path"');
    }
    return listing;
  }

  @override
  Future<Entry> createFolder(String path) async {
    createdFolders.add(path);
    return Entry(name: path.split('/').last, path: path, isDir: true);
  }
}
