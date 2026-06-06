import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/transfers/chunk_planner.dart';

void main() {
  group('planChunks', () {
    const mb = 1024 * 1024;
    const defaultChunk = 4 * mb;

    test('empty file produces 1 chunk', () {
      final plan = planChunks(0);
      expect(plan.totalChunks, 1);
      expect(plan.chunkSize, defaultChunk);
    });

    test('file exactly one chunk', () {
      final plan = planChunks(defaultChunk);
      expect(plan.totalChunks, 1);
    });

    test('file one byte over chunk boundary = 2 chunks', () {
      final plan = planChunks(defaultChunk + 1);
      expect(plan.totalChunks, 2);
    });

    test('file exactly two chunks', () {
      final plan = planChunks(defaultChunk * 2);
      expect(plan.totalChunks, 2);
    });

    test('custom chunk size respected', () {
      final plan = planChunks(100, chunkSize: 30);
      // ceil(100/30) = 4
      expect(plan.totalChunks, 4);
      expect(plan.chunkSize, 30);
    });

    test('1 byte file = 1 chunk', () {
      final plan = planChunks(1);
      expect(plan.totalChunks, 1);
    });

    test('large file produces correct count', () {
      // 1 GB file with 4 MB chunks = 256 chunks
      final plan = planChunks(1024 * mb);
      expect(plan.totalChunks, 256);
    });
  });
}
