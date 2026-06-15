import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/share/share_intake.dart';
import 'package:remote_file_explorer/features/transfers/transfer_state.dart';

void main() {
  const host = Host(
    id: 'host-1',
    label: 'Desk PC',
    address: '192.168.1.20:8765',
  );

  group('buildShareUploadTasks', () {
    test('builds one upload task per path', () {
      final tasks = buildShareUploadTasks(
        paths: ['/cache/IMG_0001.jpg', '/cache/report.pdf'],
        destDir: '/Pictures',
        host: host,
      );

      expect(tasks, hasLength(2));
      expect(tasks.every((t) => t.kind == TransferKind.upload), isTrue);
      expect(tasks.every((t) => t.host.id == host.id), isTrue);
      expect(tasks.every((t) => t.overwrite == false), isTrue);
    });

    test('remotePath is destDir + "/" + basename', () {
      final tasks = buildShareUploadTasks(
        paths: ['/cache/IMG_0001.jpg'],
        destDir: '/Pictures',
        host: host,
      );

      expect(tasks.single.remotePath, '/Pictures/IMG_0001.jpg');
      expect(tasks.single.localPath, '/cache/IMG_0001.jpg');
    });

    test('handles nested local paths by extracting the basename', () {
      final tasks = buildShareUploadTasks(
        paths: ['/data/user/0/com.app/cache/share/2026-06-15/photo.png'],
        destDir: '/Downloads',
        host: host,
      );

      expect(tasks.single.remotePath, '/Downloads/photo.png');
    });

    test('handles Windows-style nested local paths', () {
      final tasks = buildShareUploadTasks(
        paths: [r'C:\Users\me\AppData\Local\Temp\share\doc.docx'],
        destDir: '/Documents',
        host: host,
      );

      expect(tasks.single.remotePath, '/Documents/doc.docx');
    });

    test('destDir of root ("/") does not double the leading slash', () {
      final tasks = buildShareUploadTasks(
        paths: ['/cache/file.txt'],
        destDir: '/',
        host: host,
      );

      expect(tasks.single.remotePath, '/file.txt');
    });

    test('preserves order and count for multiple shared files', () {
      final paths = ['/cache/a.jpg', '/cache/b.png', '/cache/c.mp4'];
      final tasks = buildShareUploadTasks(
        paths: paths,
        destDir: '/Media',
        host: host,
      );

      expect(tasks.map((t) => t.remotePath), [
        '/Media/a.jpg',
        '/Media/b.png',
        '/Media/c.mp4',
      ]);
    });
  });
}
