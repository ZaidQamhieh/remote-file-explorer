import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/core/models/agent_status.dart';

void main() {
  group('AgentStatus.fromJson', () {
    test('parses all 5 fields', () {
      final json = {
        'version': '1.5.0',
        'platform': 'linux',
        'uptimeSeconds': 7325,
        'freeBytes': 42949672960,
        'totalBytes': 107374182400,
      };
      final s = AgentStatus.fromJson(json);
      expect(s.version, '1.5.0');
      expect(s.platform, 'linux');
      expect(s.uptimeSeconds, 7325);
      expect(s.freeBytes, 42949672960);
      expect(s.totalBytes, 107374182400);
    });

    test('defaults missing fields to empty string / zero', () {
      final s = AgentStatus.fromJson({});
      expect(s.version, '');
      expect(s.platform, '');
      expect(s.uptimeSeconds, 0);
      expect(s.freeBytes, 0);
      expect(s.totalBytes, 0);
    });
  });
}
