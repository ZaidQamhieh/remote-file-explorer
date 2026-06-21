import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart';
import 'package:remote_file_explorer/core/models/entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/preview/audio_preview.dart';

import 'l10n_helpers.dart';

// ---------------------------------------------------------------------------
// Fake just_audio platform
// ---------------------------------------------------------------------------

class _MockJustAudioPlatform extends JustAudioPlatform
    with MockPlatformInterfaceMixin {
  final _players = <String, _MockAudioPlayerPlatform>{};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final p = _MockAudioPlayerPlatform(request.id);
    _players[request.id] = p;
    return p;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
          DisposePlayerRequest request) async =>
      DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async {
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

class _MockAudioPlayerPlatform extends AudioPlayerPlatform {
  _MockAudioPlayerPlatform(super.id);

  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  final _dataController = StreamController<PlayerDataMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _eventController.stream;
  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      _dataController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    const dur = Duration(seconds: 30);
    Future.microtask(() {
      if (!_eventController.isClosed) {
        _eventController.add(PlaybackEventMessage(
          processingState: ProcessingStateMessage.ready,
          updateTime: DateTime.now(),
          updatePosition: Duration.zero,
          bufferedPosition: dur,
          duration: dur,
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        ));
      }
    });
    return LoadResponse(duration: dur);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _dataController.add(PlayerDataMessage(playing: true));
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _dataController.add(PlayerDataMessage(playing: false));
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    _dataController.add(PlayerDataMessage(speed: request.speed));
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _eventController.close();
    await _dataController.close();
    return DisposeResponse();
  }
}

// ---------------------------------------------------------------------------
// Fake AgentClient
// ---------------------------------------------------------------------------

const _testHost = Host(id: 'h1', label: 'Test PC', address: '127.0.0.1:1');

class _FakeAgentClient extends AgentClient {
  _FakeAgentClient({this.shouldFail = false}) : super(_testHost);
  final bool shouldFail;

  @override
  Future<void> downloadFile({
    required String remotePath,
    required File localFile,
    int startByte = 0,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (shouldFail) throw Exception('Network error');
    await localFile.parent.create(recursive: true);
    await localFile.writeAsBytes([0]);
    onProgress?.call(1, 1);
  }
}

Entry _audio(String name, {int? size}) =>
    Entry(name: name, path: '/music/$name', isDir: false, size: size);

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(localizationsDelegates: l10nDelegates, home: child),
    );

/// Pumps the widget inside runAsync so real I/O + platform calls complete,
/// then pumps frames in fake-async for the UI, and adds a teardown to
/// properly dispose the AudioPlayer and its timers.
Future<void> _pumpAndWait(WidgetTester tester, Widget widget) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(widget);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Disposes the widget tree and waits for async cleanup (AudioPlayer.dispose).
/// The position stream timer (fake, ~37ms periodic) self-cancels on its next
/// tick once _durationSubject is closed. We pump past that interval to
/// trigger the self-cancel.
Future<void> _disposeAndClean(WidgetTester tester) async {
  // Unmount: triggers State.dispose() → _player?.dispose() (fire-and-forget).
  await tester.runAsync(() async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    // Let AudioPlayer.dispose() complete its async close chain.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  // Advance the fake clock past the timer's interval so the next tick
  // detects _durationSubject.isClosed and cancels itself.
  await tester.pump(const Duration(milliseconds: 100));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    JustAudioPlatform.instance = _MockJustAudioPlatform();
    tempDir = Directory.systemTemp.createTempSync('audio_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'), null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('shows transport UI after loading', (tester) async {
    final client = _FakeAgentClient();
    await _pumpAndWait(
      tester,
      _wrap(AudioPreviewScreen(entry: _audio('song.mp3'), client: client)),
    );

    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.text('song.mp3'), findsWidgets);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await _disposeAndClean(tester);
  });

  testWidgets('shows error state on download failure', (tester) async {
    final client = _FakeAgentClient(shouldFail: true);
    await _pumpAndWait(
      tester,
      _wrap(AudioPreviewScreen(entry: _audio('song.mp3'), client: client)),
    );

    expect(find.textContaining('Could not load this audio'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows too-large state for oversized files', (tester) async {
    final client = _FakeAgentClient();
    final entry = _audio('huge.flac', size: 200 * 1024 * 1024);
    await _pumpAndWait(
      tester,
      _wrap(AudioPreviewScreen(entry: entry, client: client)),
    );

    expect(find.textContaining('too large to preview'), findsOneWidget);
  });

  testWidgets('speed button opens menu with presets', (tester) async {
    final client = _FakeAgentClient();
    await _pumpAndWait(
      tester,
      _wrap(AudioPreviewScreen(entry: _audio('podcast.mp3'), client: client)),
    );

    expect(find.text('1x'), findsOneWidget);
    await tester.tap(find.text('1x'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('0.75x'), findsOneWidget);
    expect(find.text('1.25x'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);

    // Dismiss the popup menu.
    await tester.tapAt(Offset.zero);
    await tester.pump();
    await _disposeAndClean(tester);
  });

  testWidgets('chromeless mode hides app bar', (tester) async {
    final client = _FakeAgentClient();
    await _pumpAndWait(
      tester,
      _wrap(AudioPreviewScreen(
        entry: _audio('song.mp3'), client: client, chromeless: true)),
    );

    expect(find.byType(AppBar), findsNothing);
    expect(find.byIcon(Icons.music_note), findsOneWidget);

    await _disposeAndClean(tester);
  });
}
