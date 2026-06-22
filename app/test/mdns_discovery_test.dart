import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/hosts/mdns_discovery.dart';

void main() {
  group('DiscoveredAgent', () {
    test('hostAddress formats address and port', () {
      const agent = DiscoveredAgent(
        name: 'MyPC',
        address: '192.168.1.10',
        port: 8765,
      );
      expect(agent.hostAddress, '192.168.1.10:8765');
    });

    test('hostAddress works with IPv6', () {
      const agent = DiscoveredAgent(name: 'Server', address: '::1', port: 443);
      expect(agent.hostAddress, '::1:443');
    });

    test('version is optional', () {
      const agent = DiscoveredAgent(
        name: 'MyPC',
        address: '10.0.0.1',
        port: 8765,
      );
      expect(agent.version, isNull);

      const withVersion = DiscoveredAgent(
        name: 'MyPC',
        address: '10.0.0.1',
        port: 8765,
        version: '1.2.0',
      );
      expect(withVersion.version, '1.2.0');
    });
  });

  group('MdnsDiscovery', () {
    test('current starts empty', () {
      final discovery = MdnsDiscovery();
      expect(discovery.current, isEmpty);
    });
  });
}
