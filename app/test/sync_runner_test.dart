import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/core/models/listing.dart';
import 'package:remote_file_explorer/core/storage/sync_rules.dart';
import 'package:remote_file_explorer/features/sync/sync_runner.dart';

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

void main() {
  // ---------------------------------------------------------------------
  // Bug — same-size files were assumed unchanged
  // ---------------------------------------------------------------------
  group('needsSync', () {
    final remote = Entry(
      name: 'f.txt',
      path: '/remote/f.txt',
      isDir: false,
      size: 10,
      modified: DateTime(2026, 1, 2),
    );

    test('missing locally always needs sync', () {
      expect(needsSync(remote, localExists: false), isTrue);
    });

    test('different size needs sync', () {
      expect(
        needsSync(
          remote,
          localExists: true,
          localSize: 9,
          localModified: DateTime(2026, 1, 2),
        ),
        isTrue,
      );
    });

    test(
      'same size but remote modified after local mtime needs sync '
      '(PR-31 — an in-place edit with unchanged length must not be skipped)',
      () {
        expect(
          needsSync(
            remote,
            localExists: true,
            localSize: 10,
            localModified: DateTime(2026, 1, 1),
          ),
          isTrue,
        );
      },
    );

    test('same size and remote not newer does not need sync', () {
      expect(
        needsSync(
          remote,
          localExists: true,
          localSize: 10,
          localModified: DateTime(2026, 1, 2),
        ),
        isFalse,
      );
    });

    test('missing modified timestamps fall back to size-only comparison', () {
      final noModified = Entry(
        name: 'f.txt',
        path: '/remote/f.txt',
        isDir: false,
        size: 10,
      );
      expect(needsSync(noModified, localExists: true, localSize: 10), isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // Bug — only the first page of a directory listing was ever synced
  // ---------------------------------------------------------------------
  group('SyncRunner.run', () {
    test('pages through the entire remote listing before syncing', () async {
      final dir = await Directory.systemTemp.createTemp('sync_paging_');
      addTearDown(() => dir.delete(recursive: true));

      final pages = <String?, Listing>{
        null: Listing(
          path: '/r',
          entries: [
            Entry(name: 'a.txt', path: '/r/a.txt', isDir: false, size: 1),
          ],
          nextCursor: 'page2',
        ),
        'page2': Listing(
          path: '/r',
          entries: [
            Entry(name: 'b.txt', path: '/r/b.txt', isDir: false, size: 1),
          ],
          nextCursor: null,
        ),
      };

      final downloaded = <String>[];
      final client = _FakeSyncClient(
        host: _testHost,
        listPages: pages,
        onDownload: (remotePath, localFile) async {
          downloaded.add(remotePath);
          await localFile.writeAsBytes([1]);
        },
      );

      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/r',
        localPath: dir.path,
      );

      final synced = await SyncRunner().run(client, rule);

      expect(synced, 2);
      expect(downloaded, ['/r/a.txt', '/r/b.txt']);
    });

    test('downloads into a temp file and only the final rename lands at the '
        'real name (an interrupted transfer never looks synced)', () async {
      final dir = await Directory.systemTemp.createTemp('sync_atomic_');
      addTearDown(() => dir.delete(recursive: true));

      final client = _FakeSyncClient(
        host: _testHost,
        listPages: {
          null: Listing(
            path: '/r',
            entries: [
              Entry(name: 'a.txt', path: '/r/a.txt', isDir: false, size: 3),
            ],
            nextCursor: null,
          ),
        },
        onDownload: (remotePath, localFile) async {
          expect(
            localFile.path,
            isNot('${dir.path}/a.txt'),
            reason: 'must stream into a temp path, not the final name',
          );
          await localFile.writeAsBytes([1, 2, 3]);
        },
      );

      final rule = SyncRule(
        id: '1',
        hostId: 'h1',
        remotePath: '/r',
        localPath: dir.path,
      );

      await SyncRunner().run(client, rule);

      expect(await File('${dir.path}/a.txt').readAsBytes(), [1, 2, 3]);
    });
  });
}

class _FakeSyncClient extends AgentClient {
  _FakeSyncClient({
    required Host host,
    required this.listPages,
    required this.onDownload,
  }) : super(host);

  final Map<String?, Listing> listPages;
  final Future<void> Function(String remotePath, File localFile) onDownload;

  @override
  Future<Listing> list(String path, {String? cursor, int limit = 200}) async {
    return listPages[cursor]!;
  }

  @override
  Future<void> downloadFile({
    required String remotePath,
    required File localFile,
    int startByte = 0,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await onDownload(remotePath, localFile);
  }
}
