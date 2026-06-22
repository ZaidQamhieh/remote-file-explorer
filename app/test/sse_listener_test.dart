import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_file_explorer/features/explorer/sse_listener.dart';

void main() {
  group('SseEvent.fromJson', () {
    test('parses fs.change event', () {
      final event = SseEvent.fromJson({
        'type': 'fs.change',
        'path': '/home/user/test.txt',
        'action': 'created',
      });
      expect(event.type, 'fs.change');
      expect(event.path, '/home/user/test.txt');
      expect(event.action, 'created');
    });

    test('handles missing fields gracefully', () {
      final event = SseEvent.fromJson({});
      expect(event.type, '');
      expect(event.path, '');
      expect(event.action, '');
    });

    test('handles partial fields', () {
      final event = SseEvent.fromJson({'type': 'fs.change'});
      expect(event.type, 'fs.change');
      expect(event.path, '');
      expect(event.action, '');
    });

    test('handles null values as empty strings', () {
      final event = SseEvent.fromJson({
        'type': null,
        'path': null,
        'action': null,
      });
      expect(event.type, '');
      expect(event.path, '');
      expect(event.action, '');
    });
  });

  group('SseListener', () {
    test('connected is false before start', () {
      final listener = SseListener(() => const Stream.empty());
      addTearDown(listener.dispose);
      expect(listener.connected, isFalse);
    });

    test('connected is true after start', () async {
      final controller = StreamController<String>();
      addTearDown(controller.close);
      final listener = SseListener(() => controller.stream);
      addTearDown(listener.dispose);

      listener.start();
      await Future<void>.delayed(Duration.zero);
      expect(listener.connected, isTrue);
    });

    test('emits parsed SseEvents from JSON lines', () async {
      final controller = StreamController<String>();
      addTearDown(controller.close);
      final listener = SseListener(() => controller.stream);
      addTearDown(listener.dispose);

      final events = <SseEvent>[];
      listener.events.listen(events.add);
      listener.start();

      controller.add(
        '{"type":"fs.change","path":"/tmp/a.txt","action":"created"}',
      );
      controller.add(
        '{"type":"fs.change","path":"/tmp/b.txt","action":"deleted"}',
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events[0].type, 'fs.change');
      expect(events[0].path, '/tmp/a.txt');
      expect(events[0].action, 'created');
      expect(events[1].path, '/tmp/b.txt');
      expect(events[1].action, 'deleted');
    });

    test('skips malformed JSON lines silently', () async {
      final controller = StreamController<String>();
      addTearDown(controller.close);
      final listener = SseListener(() => controller.stream);
      addTearDown(listener.dispose);

      final events = <SseEvent>[];
      listener.events.listen(events.add);
      listener.start();

      controller.add('not-json');
      controller.add('{"type":"fs.change","path":"/ok","action":"created"}');
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events[0].path, '/ok');
    });

    test('dispose stops listening', () async {
      final controller = StreamController<String>();
      addTearDown(controller.close);
      final listener = SseListener(() => controller.stream);

      listener.events.listen((_) {}, onDone: () {});
      listener.start();
      await Future<void>.delayed(Duration.zero);

      listener.dispose();
      expect(listener.connected, isFalse);
    });
  });
}
