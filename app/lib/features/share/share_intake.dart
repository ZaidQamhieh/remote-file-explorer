/// "Share to Remote File Explorer" intake — lets the user share one or more
/// files from any app (gallery, files, browser…) into this app, then pick a
/// paired PC and a destination folder and have the file(s) uploaded via the
/// existing [transferQueueProvider].
///
/// [ShareIntakeListener] wraps the app's `home` widget and, once mounted:
///  - reads [ReceiveSharingIntent.getInitialMedia] for a cold start (the app
///    was launched via the share sheet) and calls `.reset()` once handled so
///    the same share isn't replayed on the next app start;
///  - subscribes to [ReceiveSharingIntent.getMediaStream] for shares that
///    arrive while the app is already running.
///
/// v1 only supports items with a real file path (images/videos/generic
/// files). Pure text/URL shares are not uploadable — if *only* text/URL was
/// shared we show an info snackbar and stop.
///
/// This is intent-driven and doesn't care who sent the `ACTION_SEND`/
/// `ACTION_SEND_MULTIPLE` intent — another app's share sheet and Tasker's
/// "Send Intent" action (with a file URI extra) both land here the same way.
/// That makes this flow double as the Tasker "upload to PC" hook with no
/// extra code needed; see `app/android/app/src/main/AndroidManifest.xml`'s
/// SEND/SEND_MULTIPLE filters and `host_open_listener.dart` for the sibling
/// "open host" intent hook.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/models/host.dart';
import '../../core/storage/host_store.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../explorer/explorer_state.dart' show basenameOf;
import '../explorer/widgets/destination_picker_sheet.dart';
import '../hosts/host_list_screen.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_state.dart';

// ---------------------------------------------------------------------------
// Pure logic (unit-testable without the platform plugin)
// ---------------------------------------------------------------------------

/// Builds one [TransferTask.upload] per entry in [paths], targeting
/// `<destDir>/<basename>` on [host].
///
/// [paths] may contain nested paths (e.g. from a content-resolver temp cache
/// dir like `/data/.../cache/IMG_0001.jpg`) — only the basename is used for
/// the remote path. Uploads are enqueued with `overwrite: false`; any
/// collisions surface in the transfers UI as a normal failed-transfer
/// "already exists" error the user can retry with a different name (see
/// [ShareIntakeListener] doc comment for why a pre-flight collision check
/// isn't done here).
List<TransferTask> buildShareUploadTasks({
  required List<String> paths,
  required String destDir,
  required Host host,
}) {
  return paths.map((path) {
    final name = basenameOf(path);
    final dir = destDir == '/' ? '' : destDir;
    return TransferTask.upload(
      localPath: path,
      remotePath: '$dir/$name',
      host: host,
      overwrite: false,
    );
  }).toList();
}

// ---------------------------------------------------------------------------
// Listener widget
// ---------------------------------------------------------------------------

/// Wraps [child] (the app's `home`) and handles incoming "Share to…" intents.
///
/// Needs a [navigatorKey] because shares can arrive while the widget tree
/// below the current route doesn't have a [BuildContext] convenient for
/// pushing sheets/routes (e.g. right at cold start, before the first frame's
/// context is reliable) — all UI in this file goes through
/// `navigatorKey.currentState`/`currentContext`.
class ShareIntakeListener extends ConsumerStatefulWidget {
  const ShareIntakeListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<ShareIntakeListener> createState() =>
      _ShareIntakeListenerState();
}

class _ShareIntakeListenerState extends ConsumerState<ShareIntakeListener> {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  @override
  void initState() {
    super.initState();

    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) => _handleShared(files),
      onError: (_) {
        // Best-effort: a stream error just means "no share to handle now".
      },
    );

    // Cold start: the app was launched via the share sheet. Defer to after
    // the first frame so navigatorKey.currentContext is available.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        await _handleShared(initial);
      }
      // Tell the plugin we're done so a future cold start doesn't replay it.
      await ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  // ---------------------------------------------------------------------------
  // Handling
  // ---------------------------------------------------------------------------

  Future<void> _handleShared(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    final paths =
        files
            .where(
              (f) =>
                  f.type != SharedMediaType.text &&
                  f.type != SharedMediaType.url,
            )
            .map((f) => f.path)
            .where((p) => p.isNotEmpty)
            .toList();

    final context = widget.navigatorKey.currentContext;
    if (context == null) return;

    if (paths.isEmpty) {
      // Only text/url was shared — not supported in v1.
      if (context.mounted) {
        showInfo(context, 'Sharing files only for now');
      }
      return;
    }

    final store = await ref.read(hostStoreProvider.future);
    final hosts = store.listHosts();

    if (hosts.isEmpty) {
      if (!context.mounted) return;
      showInfo(context, 'Pair a PC first');
      widget.navigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => const HostListScreen()),
      );
      return;
    }

    Host host;
    if (hosts.length == 1) {
      host = hosts.first;
    } else {
      if (!context.mounted) return;
      final picked = await _pickHost(context, hosts);
      if (picked == null) return; // cancelled
      host = picked;
    }

    if (!context.mounted) return;
    final destDir = await showDestinationPicker(
      context,
      hostId: host.id,
      originPath: '/',
      itemCount: paths.length,
      isCopy: true,
    );
    if (destDir == null) return; // cancelled

    final tasks = buildShareUploadTasks(
      paths: paths,
      destDir: destDir,
      host: host,
    );

    final notifier = ref.read(transferQueueProvider.notifier);
    for (final task in tasks) {
      notifier.enqueue(task);
    }

    if (!context.mounted) return;
    showInfo(
      context,
      'Uploading ${tasks.length} file${tasks.length == 1 ? '' : 's'} to '
      '${host.label}…',
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TransferManagerSheet(),
    );
  }

  /// Shows a simple modal sheet listing [hosts] and returns the tapped
  /// [Host], or `null` if dismissed without a choice.
  Future<Host?> _pickHost(BuildContext context, List<Host> hosts) {
    return showModalBottomSheet<Host>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTopR),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.sm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Share to which PC?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
              ...hosts.map(
                (host) => ListTile(
                  leading: const Icon(Icons.computer_rounded),
                  title: Text(host.label),
                  subtitle: Text(host.address),
                  onTap: () => Navigator.pop(sheetContext, host),
                ),
              ),
              const SizedBox(height: Spacing.sm),
            ],
          ),
        );
      },
    );
  }
}
